import Foundation
import Observation

@MainActor @Observable
final class SocialStore {
    private(set) var profile: ExplorerProfile?
    private(set) var friends: [ExplorerFriend] = []
    private(set) var isSignedIn = false
    private(set) var isBusy = false
    private(set) var isCheckingProfile = false
    private(set) var profileCheckFailed = false
    private(set) var profileSaveMessage: String?
    private(set) var profilePhotoRefreshID = UUID()
    var errorMessage: String?
    private(set) var emailForCode: String?
    private(set) var pendingInvitation: InvitationPreview?
    private(set) var invitationURL: URL?
    private(set) var isConnectingInvitation = false
    private(set) var invitationConnected = false
    private(set) var invitationMessage: String?
    private(set) var deletionPending: Bool
    private(set) var appleUserID: String?
    private(set) var requiresAppleAuthorizationForDeletion = false
    private(set) var appleRevocationNeedsManualAction = false
    var presentsInvitation = false
    private let configuration: SocialConfiguration?
    private let api: SocialAPI?
    private let defaults: UserDefaults
    private let photoDirectory: URL?
    private let journal: DiscoveryJournal
    private let culture: LiveCultureService
    private let appleCredentialIsAuthorized: @Sendable (String) async -> Bool?
    private var pendingToken: String?
    private var generation = UUID()
    private var refreshing = false
    private var refreshingVisibleProfiles = false
    private var lastVisibleProfileRefresh: Date?
    private var profileCheckTask: Task<Void, Never>?
    private var profileCheckID = UUID()
    private var lastCodeSent: Date?
    private var localOwnerID: UUID?
    private var deletionTargetID: UUID?
    private var invitationGeneration = UUID()
    private var invitationNeedsAttempt = false
    private var completedInvitationToken: String?
    private var completedInvitationOwner: UUID?

    private struct SavedInvitation: Codable {
        let url: URL
        let receivedAt: Date
    }
    private static let pendingInvitationKey = "niche.pendingInvitation.v1"

    private struct LocalWorkspace: Codable {
        let profile: ExplorerProfile?
        let explored: [String]
        let saved: [String]
    }

    private var exportDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WorldNiche-Exports", isDirectory: true)
    }

    static let avatars = ["globe", "leaf", "sun", "moon", "mountain", "wave"]
    static func symbol(for avatar: String) -> String {
        switch avatar {
        case "leaf": "leaf.fill"
        case "sun": "sun.max.fill"
        case "moon": "moon.stars.fill"
        case "mountain": "mountain.2.fill"
        case "wave": "water.waves"
        default: "globe.europe.africa.fill"
        }
    }

    var isConfigured: Bool { configuration != nil }
    var isAppleSignInAvailable: Bool { configuration?.appleSignInEnabled == true }
    var emailCodeResendAvailableAt: Date? { lastCodeSent?.addingTimeInterval(60) }
    var privacyPolicyURL: URL? { URL(string: "https://worldniche.app/privacy") }
    var supportURL: URL? { URL(string: "https://worldniche.app/support") }
    var communityURL: URL { URL(string: "https://worldniche.app/community")! }

    init(journal: DiscoveryJournal, defaults: UserDefaults = .standard, photoDirectory: URL? = nil,
         configuration: SocialConfiguration? = .load(), api: SocialAPI? = nil,
         culture: LiveCultureService = .shared,
         appleCredentialIsAuthorized: @escaping @Sendable (String) async -> Bool? = { _ in nil }) {
        self.journal = journal
        self.culture = culture
        self.defaults = defaults
        self.photoDirectory = photoDirectory
        self.configuration = configuration
        self.api = api ?? configuration.map { SocialAPI(configuration: $0) }
        self.appleCredentialIsAuthorized = appleCredentialIsAuthorized
        appleRevocationNeedsManualAction = defaults.bool(forKey: "niche.appleRevocationNeedsManualAction")
        deletionPending = defaults.bool(forKey: "niche.deletionPending")
        if let data = defaults.data(forKey: "niche.profile") {
            profile = try? JSONDecoder().decode(ExplorerProfile.self, from: data)
        }
        localOwnerID = defaults.string(forKey: "niche.localOwnerID").flatMap(UUID.init(uuidString:)) ?? profile?.id
        deletionTargetID = defaults.string(forKey: "niche.deletionTargetID").flatMap(UUID.init(uuidString:))
        if deletionPending, deletionTargetID == nil { deletionTargetID = localOwnerID }
        defaults.set(localOwnerID?.uuidString, forKey: "niche.localOwnerID")
        defaults.set(deletionTargetID?.uuidString, forKey: "niche.deletionTargetID")
        if let data = defaults.data(forKey: Self.pendingInvitationKey),
           let saved = try? JSONDecoder().decode(SavedInvitation.self, from: data),
           Date().timeIntervalSince(saved.receivedAt) >= 0,
           Date().timeIntervalSince(saved.receivedAt) < 7 * 24 * 60 * 60,
           let token = InvitationLink.token(from: saved.url, allowedHost: configuration?.invitationHost) {
            pendingToken = token
            invitationNeedsAttempt = true
            presentsInvitation = true
        } else { defaults.removeObject(forKey: Self.pendingInvitationKey) }
    }

    func refresh() async {
        guard let api, !refreshing, !refreshingVisibleProfiles, !isBusy else { return }
        refreshing = true
        var current = generation
        defer { refreshing = false }
        let userID = await api.currentUserID()
        guard generation == current, !Task.isCancelled else { return }
        guard let userID else {
            isSignedIn = false
            appleUserID = nil
            requiresAppleAuthorizationForDeletion = false
            friends = []
            if !deletionPending { switchWorkspace(to: nil) }
            return
        }
        let appleID = await api.currentAppleUserID()
        let hasApple = await api.hasAppleIdentity()
        guard generation == current, !Task.isCancelled else { return }
        appleUserID = appleID
        requiresAppleAuthorizationForDeletion = hasApple
        if deletionPending {
            guard deletionTargetID == userID else { await rejectDeletionIdentity(api: api); return }
            isSignedIn = true
            return
        }
        if let appleID {
            let authorized = await appleCredentialIsAuthorized(appleID)
            guard generation == current, !Task.isCancelled else { return }
            if authorized == false {
                await invalidateAppleSession(userID: appleID)
                return
            }
        }
        switchWorkspace(to: userID)
        current = generation
        isSignedIn = true
        do {
            var remote = try await api.profile()
            guard generation == current, !Task.isCancelled, !deletionPending else { return }
            guard remote == nil || remote?.id == userID else { throw SocialError.invalidResponse }
            // A previous sign-in may have saved its session before profile
            // creation lost connectivity. Resume that setup before connecting.
            remote = try await finishProfileSetup(remote, userID: userID, api: api,
                                                createIfMissing: pendingToken != nil || pendingAppleName(for: userID) != nil
                                                    || defaults.object(forKey: profileSharingKey(userID)) != nil)
            let remoteFriends = try await api.friends()
            guard generation == current, !Task.isCancelled, !deletionPending else { return }
            guard remote == nil || remote?.id == userID else { throw SocialError.invalidResponse }
            profile = remote
            persistProfile()
            friends = remoteFriends
            profilePhotoRefreshID = UUID()
            lastVisibleProfileRefresh = Date()
            if !presentsInvitation { errorMessage = nil }
            await synchronizeExploration()
            await resumeInvitation()
            resumeProfileCheckIfNeeded()
        } catch {
            guard generation == current, !Task.isCancelled, !deletionPending else { return }
            record(error)
        }
    }

    func saveProfile(name: String, avatar: String, sharing: Bool, photoData: Data? = nil,
                     removePhoto: Bool = false, automaticChecks: Bool? = nil) async {
        guard beginMutation() else { return }
        defer { isBusy = false }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...32).contains(name.count), !name.contains("://"),
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              Self.avatars.contains(avatar) else { record(SocialError.invalidName); return }
        if let photoData, !AvatarPhotoReference.isValidJPEG(photoData) { record(SocialError.invalidPhoto); return }
        do {
            if isSignedIn, let api {
                let hadProfile = profile?.id == localOwnerID && profile != nil
                if let automaticChecks, hadProfile {
                    let consent = try await api.setProfileCheckConsent(enabled: automaticChecks)
                    guard consent.id == localOwnerID else { throw SocialError.invalidResponse }
                    profile = consent
                    persistProfile()
                }
                let saved = try await api.updateProfile(name: name, avatar: avatar, sharing: sharing)
                guard saved.id == localOwnerID else { throw SocialError.invalidResponse }
                profile = saved
                persistProfile()
                if let owner = localOwnerID {
                    defaults.removeObject(forKey: appleNameKey(owner))
                    defaults.removeObject(forKey: profileSharingKey(owner))
                }
                // A session can exist before profile creation finishes. The
                // first consent RPC needs that row, so save it before asking.
                if let automaticChecks, !hadProfile {
                    let consent = try await api.setProfileCheckConsent(enabled: automaticChecks)
                    guard consent.id == localOwnerID else { throw SocialError.invalidResponse }
                    profile = consent
                    persistProfile()
                }
                if photoData != nil || removePhoto {
                    let updated = try await api.updateProfilePhoto(photoData)
                    guard updated.id == localOwnerID else { throw SocialError.invalidResponse }
                    profile = updated
                }
            } else {
                let previous = profile?.localAvatarID
                let next = try photoData.map { try AvatarPhotoFiles.save($0, directory: photoDirectory) } ?? (removePhoto ? nil : previous)
                profile = ExplorerProfile(id: nil, displayName: name, avatar: avatar, shareExploration: false, localAvatarID: next)
                if let previous, previous != next { AvatarPhotoFiles.remove(previous, directory: photoDirectory) }
            }
            persistProfile()
            profileSaveMessage = profile?.hasPendingContent == true ? "Saved to your profile." : "Profile saved."
            profileCheckFailed = false
            if isSignedIn, sharing { await synchronizeExploration() }
            resumeProfileCheckIfNeeded()
        } catch { record(error) }
    }

    /// Fetch only profiles while a social screen is visible. Journal uploads and
    /// credential checks remain in the normal foreground refresh.
    func refreshVisibleProfiles(force: Bool = false, now: Date = Date()) async {
        guard let api, isSignedIn, let owner = localOwnerID, !deletionPending,
              !isBusy, !refreshing, !refreshingVisibleProfiles else { return }
        if !force, let lastVisibleProfileRefresh, now.timeIntervalSince(lastVisibleProfileRefresh) < 4 { return }
        refreshingVisibleProfiles = true
        lastVisibleProfileRefresh = now
        let current = generation
        defer { refreshingVisibleProfiles = false }
        let refreshOwner = profile?.hasPendingContent == true && !isCheckingProfile
        await withTaskGroup(of: VisibleProfileRefresh.self) { group in
            group.addTask {
                do { return .friends(try await api.friends()) }
                catch { return .failure(error) }
            }
            if refreshOwner {
                group.addTask {
                    do { return .owner(try await api.profile()) }
                    catch { return .failure(error) }
                }
            }
            for await result in group {
                guard current == generation, owner == localOwnerID, isSignedIn, !deletionPending, !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                switch result {
                case .friends(let updated):
                    friends = updated
                    profilePhotoRefreshID = UUID()
                case .owner(let updated):
                    guard let updated, updated.id == owner else { continue }
                    profile = updated
                    persistProfile()
                    if !updated.hasPendingContent { profileCheckFailed = false }
                    resumeProfileCheckIfNeeded()
                case .failed(let signInRequired):
                    // Independent refresh failures retain the successful side
                    // and the last saved profile instead of replacing it.
                    if signInRequired { record(SocialError.signInRequired) }
                }
            }
        }
    }

    private enum VisibleProfileRefresh: Sendable {
        case friends([ExplorerFriend])
        case owner(ExplorerProfile?)
        case failed(Bool)

        static func failure(_ error: Error) -> Self {
            if case SocialError.signInRequired = error { return .failed(true) }
            return .failed(false)
        }
    }

    func retryProfileCheck() async {
        guard let api, isSignedIn, let owner = localOwnerID, profile?.id == owner,
              profile?.automaticProfileChecksEnabled == true,
              profile?.needsAutomaticCheck == true || profile?.canRetryCheck == true || profileCheckFailed,
              profile?.hasPendingContent == true, !isBusy, !deletionPending, !isCheckingProfile else { return }
        let current = generation
        let checkID = UUID()
        profileCheckID = checkID
        isCheckingProfile = true
        profileCheckFailed = false
        defer { if profileCheckID == checkID { isCheckingProfile = false } }
        do {
            let updated = try await api.checkProfileContent()
            guard current == generation, checkID == profileCheckID, owner == localOwnerID,
                  isSignedIn, !deletionPending, !Task.isCancelled else { return }
            guard updated.id == owner else { throw SocialError.invalidResponse }
            profile = updated
            profileCheckFailed = updated.canRetryCheck
            profileSaveMessage = updated.hasPendingContent ? "Saved to your profile." : "Profile saved."
            persistProfile()
        } catch {
            guard current == generation, checkID == profileCheckID, owner == localOwnerID,
                  isSignedIn, !deletionPending, !Task.isCancelled else { return }
            profileCheckFailed = true
            if case SocialError.signInRequired = error { record(error) }
        }
    }

    private func resumeProfileCheckIfNeeded() {
        guard isSignedIn, profile?.automaticProfileChecksEnabled == true,
              profile?.needsAutomaticCheck == true, !isCheckingProfile,
              !profileCheckFailed, !deletionPending else { return }
        profileCheckTask?.cancel()
        profileCheckTask = Task { [weak self] in
            // Saving owns the mutation lock until its caller returns. The task
            // then checks the persisted revision without holding the editor open.
            await Task.yield()
            guard !Task.isCancelled else { return }
            await self?.retryProfileCheck()
        }
    }

    private func cancelProfileCheck() {
        profileCheckTask?.cancel()
        profileCheckTask = nil
        profileCheckID = UUID()
        isCheckingProfile = false
    }

    func setProfileCheckConsent(enabled: Bool) async {
        guard beginMutation() else { return }
        defer { isBusy = false }
        guard let api, isSignedIn, let owner = localOwnerID else { record(SocialError.signInRequired); return }
        let current = generation
        do {
            let updated = try await api.setProfileCheckConsent(enabled: enabled)
            guard current == generation, owner == localOwnerID, isSignedIn, !Task.isCancelled else { return }
            guard updated.id == owner else { throw SocialError.invalidResponse }
            profile = updated
            profileCheckFailed = false
            persistProfile()
            if enabled { resumeProfileCheckIfNeeded() }
        } catch { if current == generation, owner == localOwnerID { record(error) } }
    }

    func avatarData(path: String) async -> Data? {
        func isVisible() -> Bool {
            isSignedIn && !deletionPending && (profile?.referencesPhoto(path) == true || friends.contains { $0.avatarPath == path })
        }
        guard let api, isVisible() else { return nil }
        let current = generation
        let owner = localOwnerID
        for attempt in 0..<2 {
            guard current == generation, owner == localOwnerID, isVisible(), !Task.isCancelled else { return nil }
            do {
                let data = try await api.avatarData(path: path)
                guard current == generation, owner == localOwnerID, isVisible(), !Task.isCancelled else { return nil }
                return data
            } catch SocialError.unavailable where attempt == 0 {
                do { try await Task.sleep(for: .milliseconds(350)) }
                catch { return nil }
            } catch { return nil }
        }
        return nil
    }

    func requestCode(email: String, existingAccountOnly: Bool = false) async {
        guard !isBusy else { return }
        errorMessage = nil
        guard let api else { record(SocialError.notConfigured); return }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.utf8.count <= 254, email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil else {
            record(SocialError.invalidEmail); return
        }
        if let lastCodeSent, Date().timeIntervalSince(lastCodeSent) < 60 { record(SocialError.rateLimited); return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await api.requestCode(email: email, allowNewAccount: !deletionPending && !existingAccountOnly)
            emailForCode = email
            lastCodeSent = Date()
        } catch { record(error) }
    }

    func verifyCode(code: String, shareExplorationForNewAccount: Bool = true) async {
        guard !isBusy else { return }
        errorMessage = nil
        guard let api else { record(SocialError.notConfigured); return }
        guard let emailForCode else { record(SocialError.invalidEmail); return }
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }) else { record(SocialError.invalidCode); return }
        await authenticate(.email(emailForCode, code), api: api, newProfileSharing: shareExplorationForNewAccount)
    }

    func signInWithApple(identityToken: String, nonce: String, name: String?, appleUserID: String? = nil,
                         shareExplorationForNewAccount: Bool = true) async {
        guard !isBusy else { return }
        errorMessage = nil
        guard !deletionPending else {
            errorMessage = "Use an email code for the existing account to finish deletion. Apple sign-in could create a new account if the original was already deleted."
            return
        }
        guard let api else { record(SocialError.notConfigured); return }
        if let appleUserID, !appleUserID.isEmpty, appleUserID.utf8.count <= 256,
           let name = Self.meaningfulProfileName(name) {
            // Preserve Apple's one-time name even if the session exchange is
            // offline. It is only used after the server verifies that Apple ID.
            defaults.set(name, forKey: appleAuthorizationNameKey(appleUserID))
        }
        await authenticate(.apple(identityToken, nonce), api: api, suggestedName: name,
                           newProfileSharing: shareExplorationForNewAccount)
    }

    func linkAppleIdentity(identityToken: String, nonce: String) async {
        guard beginMutation() else { return }
        defer { isBusy = false }
        guard let api, isSignedIn, let owner = localOwnerID else { record(SocialError.signInRequired); return }
        let current = generation
        do {
            try await api.linkAppleIdentity(identityToken: identityToken, nonce: nonce)
            guard generation == current, localOwnerID == owner, !Task.isCancelled else { return }
            appleUserID = await api.currentAppleUserID()
            requiresAppleAuthorizationForDeletion = await api.hasAppleIdentity()
        } catch {
            guard generation == current, localOwnerID == owner else { return }
            errorMessage = "We couldn’t connect this Apple account. Your existing account is unchanged. Try again, or contact support if Apple is already connected to another WorldNiche account."
        }
    }

    private enum AuthenticationMethod { case email(String, String), apple(String, String) }

    private func authenticate(_ method: AuthenticationMethod, api: SocialAPI, suggestedName: String? = nil,
                              newProfileSharing: Bool = true) async {
        isBusy = true
        generation = UUID()
        var current = generation
        let suggestedProfile = localOwnerID == nil ? profile : nil
        isSignedIn = false
        defer { isBusy = false }
        do {
            let userID: UUID
            switch method {
            case .email(let email, let code): userID = try await api.verifyCode(email: email, code: code)
            case .apple(let token, let nonce): userID = try await api.signInWithApple(identityToken: token, nonce: nonce)
            }
            guard generation == current, !Task.isCancelled else { return }
            let appleID = await api.currentAppleUserID()
            let hasApple = await api.hasAppleIdentity()
            guard generation == current, !Task.isCancelled else { return }
            if case .apple = method {
                let remembered = appleID.flatMap { defaults.string(forKey: appleAuthorizationNameKey($0)) }
                if let name = Self.meaningfulProfileName(suggestedName) ?? Self.meaningfulProfileName(remembered) {
                    defaults.set(name, forKey: appleNameKey(userID))
                    if let appleID { defaults.removeObject(forKey: appleAuthorizationNameKey(appleID)) }
                }
            }
            appleUserID = appleID
            requiresAppleAuthorizationForDeletion = hasApple
            if deletionPending {
                guard deletionTargetID == userID else { await rejectDeletionIdentity(api: api); return }
                isSignedIn = true
                self.emailForCode = nil
                return
            }
            switchWorkspace(to: userID)
            current = generation
            isSignedIn = true
            self.emailForCode = nil
            defaults.set(newProfileSharing, forKey: profileSharingKey(userID))
            let remote = try await api.profile()
            guard remote == nil || remote?.id == userID else { throw SocialError.invalidResponse }
            profile = try await finishProfileSetup(remote, userID: userID, api: api,
                                                  suggestedProfile: suggestedProfile, createIfMissing: true)
            guard generation == current, !Task.isCancelled, !deletionPending else { return }
            persistProfile()
            friends = try await api.friends()
            await synchronizeExploration()
            await resumeInvitation(allowWhileBusy: true)
            resumeProfileCheckIfNeeded()
        } catch { record(error) }
    }

    private func appleNameKey(_ userID: UUID) -> String { "niche.pendingAppleName.\(userID.uuidString)" }
    private func appleAuthorizationNameKey(_ appleID: String) -> String { "niche.pendingAppleAuthorizationName.\(appleID)" }
    private func profileSharingKey(_ userID: UUID) -> String { "niche.pendingProfileSharing.\(userID.uuidString)" }

    private func pendingAppleName(for userID: UUID) -> String? {
        Self.meaningfulProfileName(defaults.string(forKey: appleNameKey(userID)))
    }

    private func finishProfileSetup(_ remote: ExplorerProfile?, userID: UUID, api: SocialAPI,
                                    suggestedProfile: ExplorerProfile? = nil,
                                    createIfMissing: Bool) async throws -> ExplorerProfile? {
        let current = generation
        let appleName = pendingAppleName(for: userID)
        let existingName = Self.meaningfulProfileName(remote?.editableDisplayName)
        if let remote, existingName != nil || appleName == nil {
            defaults.removeObject(forKey: appleNameKey(userID))
            defaults.removeObject(forKey: profileSharingKey(userID))
            return remote
        }
        guard remote != nil || createIfMissing else { return nil }
        let selectedName = existingName ?? Self.meaningfulProfileName(profile?.editableDisplayName)
            ?? Self.meaningfulProfileName(suggestedProfile?.editableDisplayName) ?? appleName ?? "Explorer"
        let saved = try await api.updateProfile(name: selectedName,
                                                avatar: remote?.avatar ?? profile?.avatar ?? suggestedProfile?.avatar ?? "globe",
                                                sharing: remote?.shareExploration
                                                    ?? (defaults.object(forKey: profileSharingKey(userID)) as? Bool ?? false))
        guard generation == current, localOwnerID == userID, saved.id == userID, !Task.isCancelled else {
            throw CancellationError()
        }
        defaults.removeObject(forKey: appleNameKey(userID))
        defaults.removeObject(forKey: profileSharingKey(userID))
        return saved
    }

    private static func meaningfulProfileName(_ name: String?) -> String? {
        let value = profileName(name)
        return value.caseInsensitiveCompare("Explorer") == .orderedSame ? nil : value
    }

    private static func profileName(_ name: String?) -> String {
        let value = String((name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        guard !value.isEmpty, !value.contains("://"),
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return "Explorer" }
        return value
    }

    func invalidateAppleSession(userID: String) async {
        guard !isBusy, !deletionPending, appleUserID == userID, let api else { return }
        isBusy = true
        defer { isBusy = false }
        generation = UUID()
        let current = generation
        isSignedIn = false
        friends = []
        var storageError: (any Error)?
        do {
            try await api.revokeAppleSession(userID: userID)
        } catch { storageError = error }
        guard generation == current, await api.currentUserID() == nil else { return }
        isSignedIn = false
        appleUserID = nil
        requiresAppleAuthorizationForDeletion = false
        friends = []
        switchWorkspace(to: nil)
        if let storageError { record(storageError) }
        else { errorMessage = "Apple access has changed. Sign in again to reconnect your account." }
    }

    func dismissAppleRevocationNotice() {
        appleRevocationNeedsManualAction = false
        defaults.removeObject(forKey: "niche.appleRevocationNeedsManualAction")
    }

    func synchronizeExploration() async {
        guard let api, isSignedIn, let owner = localOwnerID,
              profile?.id == owner, profile?.shareExploration == true, !deletionPending else { return }
        let current = generation
        do {
            let uploaded = try await api.syncExplorations(journal.visitedIDs)
            guard current == generation, !Task.isCancelled, !deletionPending,
                  localOwnerID == owner, profile?.shareExploration == true else { return }
            journal.mergeExplored(uploaded)
        } catch {
            guard current == generation, !Task.isCancelled, !deletionPending, localOwnerID == owner else { return }
            record(error)
        }
    }

    func createInvitation() async -> URL? {
        guard beginMutation() else { return nil }
        defer { isBusy = false }
        guard let api, let configuration else { record(SocialError.notConfigured); return nil }
        guard isSignedIn else { record(SocialError.signInRequired); return nil }
        do {
            let invite = try await api.createInvite()
            guard let url = configuration.invitationURL(token: invite.token) else { throw SocialError.invalidResponse }
            invitationURL = url
            return url
        } catch { record(error); return nil }
    }

    func openInvitation(_ url: URL) async {
        guard let token = InvitationLink.token(from: url, allowedHost: configuration?.invitationHost) else {
            dismissInvitation()
            invitationMessage = SocialError.invalidInvitation.localizedDescription
            presentsInvitation = true
            return
        }
        if token == completedInvitationToken, localOwnerID == completedInvitationOwner, invitationConnected {
            presentsInvitation = true
            return
        }
        if token != pendingToken {
            invitationGeneration = UUID()
            pendingToken = token
            pendingInvitation = nil
            invitationConnected = false
            invitationMessage = nil
            invitationNeedsAttempt = true
            defaults.set(try? JSONEncoder().encode(SavedInvitation(url: url, receivedAt: Date())), forKey: Self.pendingInvitationKey)
        }
        // Universal links and onOpenURL can deliver the same launch together.
        // One in-flight redemption owns that token until its response arrives.
        if !isConnectingInvitation { invitationNeedsAttempt = true }
        presentsInvitation = true
        if !refreshing { await resumeInvitation() }
    }

    var canRetryInvitation: Bool { pendingToken != nil && isSignedIn && !isConnectingInvitation && !deletionPending }
    var hasPendingInvitation: Bool { pendingToken != nil }

    func resumeInvitation() async { await resumeInvitation(allowWhileBusy: false) }

    private func resumeInvitation(allowWhileBusy: Bool) async {
        guard invitationNeedsAttempt, !isConnectingInvitation, !isBusy || allowWhileBusy,
              let api, isSignedIn, profile?.id == localOwnerID, localOwnerID != nil, !deletionPending else { return }
        let ownedBusy = !isBusy
        if ownedBusy { isBusy = true }
        isConnectingInvitation = true
        defer {
            isConnectingInvitation = false
            if ownedBusy { isBusy = false }
        }
        while let token = pendingToken, invitationNeedsAttempt {
            invitationNeedsAttempt = false
            invitationMessage = nil
            let current = generation
            let invitation = invitationGeneration
            let owner = localOwnerID
            do {
                let preview = try await api.previewInvite(token)
                guard current == generation, owner == localOwnerID, isSignedIn, !deletionPending, !Task.isCancelled else { return }
                guard token == pendingToken, invitation == invitationGeneration else { continue }
                if preview.status == "self" {
                    finishUnavailableInvitation("This is your own invitation. Share it with a friend to explore together.")
                    return
                }
                guard preview.status == "available", let name = preview.displayName else {
                    finishUnavailableInvitation(SocialError.invalidInvitation.localizedDescription)
                    return
                }
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let date = preview.expiresAt.flatMap { formatter.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
                pendingInvitation = InvitationPreview(displayName: name, avatar: preview.avatar ?? "globe", expiresAt: date, alreadyFriends: preview.alreadyFriends ?? false)
                let accepted = try await api.acceptInvite(token)
                guard current == generation, owner == localOwnerID, isSignedIn, !deletionPending, !Task.isCancelled else { return }
                guard token == pendingToken, invitation == invitationGeneration else { continue }
                guard ["accepted", "already_friends"].contains(accepted.status), let friendID = accepted.friendId, friendID != owner else {
                    finishUnavailableInvitation(accepted.status == "self" ? "This is your own invitation. Share it with a friend." : SocialError.invalidInvitation.localizedDescription)
                    return
                }
                // Clear before the optional list refresh: a confirmed friendship
                // must not be redeemed again just because that next fetch fails.
                pendingToken = nil
                defaults.removeObject(forKey: Self.pendingInvitationKey)
                invitationConnected = true
                completedInvitationToken = token
                completedInvitationOwner = owner
                invitationMessage = accepted.status == "already_friends" ? "You’re already friends." : "You’re now friends."
                if let updated = try? await api.friends(), current == generation, owner == localOwnerID {
                    friends = updated
                    lastVisibleProfileRefresh = Date()
                }
            } catch {
                guard current == generation, owner == localOwnerID, isSignedIn, !deletionPending, !Task.isCancelled else { return }
                guard token == pendingToken, invitation == invitationGeneration else { continue }
                invitationMessage = (error as? SocialError)?.localizedDescription ?? SocialError.unavailable.localizedDescription
                if case SocialError.signInRequired = error { record(error); invitationNeedsAttempt = true }
                return
            }
        }
    }

    /// Retry only an unresolved request. The server makes a lost response safe:
    /// replay returns already_friends and cannot create a duplicate relationship.
    func acceptInvitation() async {
        invitationNeedsAttempt = pendingToken != nil
        if isSignedIn, profile?.id != localOwnerID { await refresh() }
        else { await resumeInvitation() }
    }

    private func finishUnavailableInvitation(_ message: String) {
        pendingToken = nil
        pendingInvitation = nil
        invitationNeedsAttempt = false
        defaults.removeObject(forKey: Self.pendingInvitationKey)
        invitationMessage = message
    }

    func dismissInvitation() {
        invitationGeneration = UUID()
        pendingToken = nil
        pendingInvitation = nil
        invitationNeedsAttempt = false
        invitationConnected = false
        invitationMessage = nil
        completedInvitationToken = nil
        completedInvitationOwner = nil
        defaults.removeObject(forKey: Self.pendingInvitationKey)
        presentsInvitation = false
    }

    func revokeInvitations() async {
        guard beginMutation() else { return }
        defer { isBusy = false }
        guard let api, isSignedIn else { record(SocialError.signInRequired); return }
        do { try await api.revokeInvites(); invitationURL = nil }
        catch { record(error) }
    }

    func removeFriend(id: UUID) async { await removeFriend(id: id, block: false) }
    func blockFriend(id: UUID) async { await removeFriend(id: id, block: true) }
    private func removeFriend(id: UUID, block: Bool) async {
        guard beginMutation() else { return }
        defer { isBusy = false }
        guard let api, isSignedIn else { record(SocialError.signInRequired); return }
        do {
            try await api.removeFriend(id, block: block)
            friends.removeAll { $0.id == id }
        } catch { record(error) }
    }

    func reportFriend(id: UUID, reason: String, details: String = "") async {
        guard beginMutation() else { return }
        defer { isBusy = false }
        guard let api, isSignedIn else { record(SocialError.signInRequired); return }
        do { try await api.report(id, reason: reason, details: details) }
        catch { record(error) }
    }

    func signOut() async {
        guard !isBusy, !deletionPending else { return }
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await api?.signOut()
            generation = UUID()
            isSignedIn = false
            appleUserID = nil
            requiresAppleAuthorizationForDeletion = false
            friends = []
            emailForCode = nil
            invitationURL = nil
            dismissInvitation()
            switchWorkspace(to: nil)
            removeExports()
        } catch { record(error) }
    }

    /// Local clearing explicitly signs out here; it never claims remote deletion.
    func clearLocalData() async {
        guard !isBusy, !deletionPending else { return }
        errorMessage = nil
        isBusy = true
        generation = UUID()
        defer { isBusy = false }
        do { try await api?.forgetSession(); await clearLocalState() }
        catch { record(error) }
    }

    enum DeletionAttempt: Equatable { case complete, appleAuthorizationRequired, incomplete }

    @discardableResult
    func deleteAccountAndData(appleAuthorizationCode: String? = nil, appleNonce: String? = nil, appleManualRevocation: Bool = false) async -> DeletionAttempt {
        guard !isBusy else { return .incomplete }
        errorMessage = nil
        if !isSignedIn {
            if deletionPending {
                errorMessage = "Sign in to your existing account to retry deletion. If it has already been removed and you can’t sign in, contact support to confirm completion."
            } else { await clearLocalData() }
            return errorMessage == nil ? .complete : .incomplete
        }
        guard let api else { record(SocialError.notConfigured); return .incomplete }
        isBusy = true
        defer { isBusy = false }
        guard let userID = await api.currentUserID() else {
            record(SocialError.signInRequired)
            return .incomplete
        }
        if deletionPending {
            guard deletionTargetID == userID else { await rejectDeletionIdentity(api: api); return .incomplete }
        } else {
            guard localOwnerID == userID else { record(SocialError.signInRequired); return .incomplete }
            deletionTargetID = userID
            defaults.set(userID.uuidString, forKey: "niche.deletionTargetID")
        }
        deletionPending = true
        defaults.set(true, forKey: "niche.deletionPending")
        if appleManualRevocation { defaults.set(true, forKey: "niche.deletionManualAppleRevocation") }
        generation = UUID()
        do {
            let result = try await api.deleteAccount(appleAuthorizationCode: appleAuthorizationCode, appleNonce: appleNonce, appleManualRevocation: appleManualRevocation)
            let manualRevocation = result.appleRevocation == "manual_required" || defaults.bool(forKey: "niche.deletionManualAppleRevocation")
            await clearLocalState()
            if manualRevocation {
                appleRevocationNeedsManualAction = true
                defaults.set(true, forKey: "niche.appleRevocationNeedsManualAction")
            }
            return .complete
        } catch {
            record(error)
            if case SocialError.appleReauthenticationRequired = error {
                requiresAppleAuthorizationForDeletion = true
                return .appleAuthorizationRequired
            }
            errorMessage = "Deletion hasn’t been confirmed. Your online account may still exist. Reconnect and retry here; exploration sharing from this device is paused."
            return .incomplete
        }
    }

    func exportData() async -> URL? {
        guard !isBusy else { return nil }
        guard !deletionPending else {
            errorMessage = "Finish deleting your account before exporting data."
            return nil
        }
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            struct LocalExport: Encodable {
                let profile: ExplorerProfile?
                let exploredCountryIDs: [String]
                let savedCountryIDs: [String]
            }
            let local = LocalExport(profile: profile, exploredCountryIDs: journal.visitedIDs, savedCountryIDs: journal.savedIDs.sorted())
            var document: [String: Any] = ["local": try JSONSerialization.jsonObject(with: JSONEncoder().encode(local))]
            if let localID = profile?.localAvatarID, let data = AvatarPhotoFiles.load(localID, directory: photoDirectory) {
                document["profile_photo_jpeg_base64"] = data.base64EncodedString()
            } else if let path = profile?.avatarPath, let api, isSignedIn {
                document["profile_photo_jpeg_base64"] = try await api.avatarData(path: path).base64EncodedString()
            }
            if let path = profile?.pendingAvatarPath, let api, isSignedIn {
                document["pending_profile_photo_jpeg_base64"] = try await api.avatarData(path: path).base64EncodedString()
            }
            if isSignedIn, let api {
                let accountData = try await api.exportData()
                document["account"] = try JSONSerialization.jsonObject(with: accountData)
            }
            let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
            let directory = exportDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("WorldNiche-\(UUID().uuidString).json")
            try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            return url
        } catch { record(error); return nil }
    }

    func friendsWhoExplored(_ countryID: String) -> [ExplorerFriend] {
        friends.filter { $0.sharesExploration && $0.exploredCountryIDs.contains(countryID) }
    }

    private func beginMutation() -> Bool {
        guard !isBusy else { return false }
        errorMessage = nil
        guard !deletionPending else {
            errorMessage = "Finish deleting your account in Settings before making other changes."
            return false
        }
        generation = UUID()
        cancelProfileCheck()
        profileSaveMessage = nil
        isBusy = true
        return true
    }

    private func persistProfile() {
        defaults.set(try? JSONEncoder().encode(profile), forKey: "niche.profile")
    }

    /// A guest journal and each account have separate local workspaces. Signing
    /// into an already-sharing account never silently publishes guest activity.
    private func switchWorkspace(to owner: UUID?) {
        guard owner != localOwnerID else { return }
        cancelProfileCheck()
        profileCheckFailed = false
        profileSaveMessage = nil
        lastVisibleProfileRefresh = nil
        generation = UUID()
        let previous = LocalWorkspace(profile: profile, explored: journal.visitedIDs, saved: journal.savedIDs.sorted())
        defaults.set(try? JSONEncoder().encode(previous), forKey: workspaceKey(localOwnerID))
        localOwnerID = owner
        defaults.set(owner?.uuidString, forKey: "niche.localOwnerID")
        let workspace = defaults.data(forKey: workspaceKey(owner)).flatMap { try? JSONDecoder().decode(LocalWorkspace.self, from: $0) }
        profile = workspace?.profile
        if profile?.id != owner { profile = nil }
        friends = []
        journal.clear()
        if let workspace {
            for id in workspace.saved {
                if let country = CountryRepository.country(id: id), !journal.savedIDs.contains(id) { journal.toggleSaved(country) }
            }
            for id in workspace.explored.reversed() {
                if let country = CountryRepository.country(id: id) { journal.visit(country) }
            }
        }
        persistProfile()
    }

    private func workspaceKey(_ owner: UUID?) -> String { "niche.workspace.\(owner?.uuidString ?? "guest")" }

    private func rejectDeletionIdentity(api: SocialAPI) async {
        generation = UUID()
        try? await api.forgetSession()
        isSignedIn = false
        appleUserID = nil
        requiresAppleAuthorizationForDeletion = false
        friends = []
        emailForCode = nil
        errorMessage = "Sign in to the same account that requested deletion. No other account or its data has been deleted."
    }

    private func removeExports() {
        try? FileManager.default.removeItem(at: exportDirectory)
    }

    private func clearLocalState() async {
        cancelProfileCheck()
        profileCheckFailed = false
        profileSaveMessage = nil
        lastVisibleProfileRefresh = nil
        generation = UUID()
        await culture.clearHistory()
        profile = nil
        friends = []
        isSignedIn = false
        appleUserID = nil
        requiresAppleAuthorizationForDeletion = false
        emailForCode = nil
        invitationURL = nil
        deletionPending = false
        deletionTargetID = nil
        localOwnerID = nil
        dismissInvitation()
        defaults.removeObject(forKey: "niche.profile")
        defaults.removeObject(forKey: "niche.deletionPending")
        defaults.removeObject(forKey: "niche.deletionTargetID")
        defaults.removeObject(forKey: "niche.deletionManualAppleRevocation")
        defaults.removeObject(forKey: "niche.localOwnerID")
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("niche.workspace.")
            || key.hasPrefix("niche.pendingAppleName.") || key.hasPrefix("niche.pendingAppleAuthorizationName.")
            || key.hasPrefix("niche.pendingProfileSharing.") {
            defaults.removeObject(forKey: key)
        }
        journal.clear()
        AvatarPhotoFiles.removeAll(directory: photoDirectory)
        URLCache.shared.removeAllCachedResponses()
        removeExports()
    }

    private func record(_ error: any Error) {
        guard !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
        errorMessage = (error as? SocialError)?.localizedDescription ?? SocialError.unavailable.localizedDescription
        if pendingToken != nil, !invitationConnected { invitationMessage = errorMessage }
        if case SocialError.signInRequired = error {
            isSignedIn = false
            appleUserID = nil
            friends = []
            if !deletionPending { switchWorkspace(to: nil) }
        }
    }
}

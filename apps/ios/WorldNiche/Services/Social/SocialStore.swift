import Foundation
import Observation

@MainActor @Observable
final class SocialStore {
    private(set) var profile: ExplorerProfile?
    private(set) var friends: [ExplorerFriend] = []
    private(set) var isSignedIn = false
    private(set) var isBusy = false
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
    private let appleCredentialIsAuthorized: @Sendable (String) async -> Bool?
    private var pendingToken: String?
    private var generation = UUID()
    private var refreshing = false
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
    var privacyPolicyURL: URL? { configuration?.privacyPolicyURL }
    var supportURL: URL? { configuration?.supportURL }

    init(journal: DiscoveryJournal, defaults: UserDefaults = .standard, photoDirectory: URL? = nil,
         configuration: SocialConfiguration? = .load(), api: SocialAPI? = nil,
         appleCredentialIsAuthorized: @escaping @Sendable (String) async -> Bool? = { _ in nil }) {
        self.journal = journal
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
        guard let api, !refreshing, !isBusy else { return }
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
            // A previous sign-in may have saved its session before profile
            // creation lost connectivity. Resume that setup before connecting.
            if remote == nil, pendingToken != nil {
                remote = try await api.updateProfile(name: profile?.displayName ?? "Explorer", avatar: profile?.avatar ?? "globe", sharing: false)
            }
            let remoteFriends = try await api.friends()
            guard generation == current, !Task.isCancelled, !deletionPending else { return }
            guard remote == nil || remote?.id == userID else { throw SocialError.invalidResponse }
            profile = remote
            persistProfile()
            friends = remoteFriends
            if !presentsInvitation { errorMessage = nil }
            await synchronizeExploration()
            await resumeInvitation()
        } catch {
            guard generation == current, !Task.isCancelled, !deletionPending else { return }
            record(error)
        }
    }

    func saveProfile(name: String, avatar: String, sharing: Bool, photoData: Data? = nil, removePhoto: Bool = false) async {
        guard beginMutation() else { return }
        defer { isBusy = false }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...32).contains(name.count), !name.contains("://"),
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              Self.avatars.contains(avatar) else { record(SocialError.invalidName); return }
        if let photoData, !AvatarPhotoReference.isValidJPEG(photoData) { record(SocialError.invalidPhoto); return }
        do {
            if isSignedIn, let api {
                let saved = try await api.updateProfile(name: name, avatar: avatar, sharing: sharing)
                guard saved.id == localOwnerID else { throw SocialError.invalidResponse }
                profile = saved
                persistProfile()
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
            if isSignedIn, sharing { await synchronizeExploration() }
        } catch { record(error) }
    }

    func avatarData(path: String) async -> Data? {
        func isVisible() -> Bool {
            isSignedIn && !deletionPending && (profile?.avatarPath == path || friends.contains { $0.avatarPath == path })
        }
        guard let api, isVisible() else { return nil }
        let current = generation
        let owner = localOwnerID
        let data = try? await api.avatarData(path: path)
        guard current == generation, owner == localOwnerID, isVisible(), !Task.isCancelled else { return nil }
        return data
    }

    func requestCode(email: String) async {
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
            try await api.requestCode(email: email, allowNewAccount: !deletionPending)
            emailForCode = email
            lastCodeSent = Date()
        } catch { record(error) }
    }

    func verifyCode(code: String) async {
        guard !isBusy else { return }
        errorMessage = nil
        guard let api else { record(SocialError.notConfigured); return }
        guard let emailForCode else { record(SocialError.invalidEmail); return }
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }) else { record(SocialError.invalidCode); return }
        await authenticate(.email(emailForCode, code), api: api)
    }

    func signInWithApple(identityToken: String, nonce: String, name: String?) async {
        guard !isBusy else { return }
        errorMessage = nil
        guard !deletionPending else {
            errorMessage = "Use an email code for the existing account to finish deletion. Apple sign-in could create a new account if the original was already deleted."
            return
        }
        guard let api else { record(SocialError.notConfigured); return }
        await authenticate(.apple(identityToken, nonce), api: api, suggestedName: name)
    }

    private enum AuthenticationMethod { case email(String, String), apple(String, String) }

    private func authenticate(_ method: AuthenticationMethod, api: SocialAPI, suggestedName: String? = nil) async {
        isBusy = true
        generation = UUID()
        let current = generation
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
            appleUserID = appleID
            requiresAppleAuthorizationForDeletion = hasApple
            if deletionPending {
                guard deletionTargetID == userID else { await rejectDeletionIdentity(api: api); return }
                isSignedIn = true
                self.emailForCode = nil
                return
            }
            switchWorkspace(to: userID)
            isSignedIn = true
            self.emailForCode = nil
            let remote = try await api.profile()
            guard remote == nil || remote?.id == userID else { throw SocialError.invalidResponse }
            if let remote { profile = remote }
            else {
                profile = try await api.updateProfile(name: profile?.displayName ?? suggestedProfile?.displayName ?? Self.profileName(suggestedName),
                                                      avatar: profile?.avatar ?? suggestedProfile?.avatar ?? "globe", sharing: false)
            }
            persistProfile()
            friends = try await api.friends()
            await synchronizeExploration()
            await resumeInvitation(allowWhileBusy: true)
        } catch { record(error) }
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

    func reportFriend(id: UUID, reason: String) async {
        guard beginMutation() else { return }
        defer { isBusy = false }
        guard let api, isSignedIn else { record(SocialError.signInRequired); return }
        do { try await api.report(id, reason: reason) }
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
        do { try await api?.forgetSession(); clearLocalState() }
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
            clearLocalState()
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

    private func clearLocalState() {
        generation = UUID()
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
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("niche.workspace.") {
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

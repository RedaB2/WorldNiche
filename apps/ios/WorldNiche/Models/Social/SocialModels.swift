import Foundation

struct ExplorerProfile: Codable, Sendable {
    var id: UUID?
    var displayName: String
    var avatar: String
    var shareExploration: Bool
    var avatarPath: String? = nil
    var localAvatarID: String? = nil
    var pendingDisplayName: String? = nil
    var pendingAvatarPath: String? = nil
    var nameModerationStatus: ProfileModerationStatus? = nil
    var photoModerationStatus: ProfileModerationStatus? = nil
    var nameCheckState: ProfileContentCheckState? = nil
    var photoCheckState: ProfileContentCheckState? = nil
    var automaticProfileChecksEnabled: Bool? = nil
    var profileCheckConsentRecorded: Bool? = nil
    var nameModerationNote: String? = nil
    var photoModerationNote: String? = nil
    var communityRestricted: Bool? = nil
    var communityRestrictionNote: String? = nil

    var editableDisplayName: String { pendingDisplayName ?? displayName }
    var editableAvatarPath: String? { pendingAvatarPath ?? avatarPath }
    var ownerDisplayName: String { nameModerationStatus == .pending ? pendingDisplayName ?? displayName : displayName }
    var ownerAvatarPath: String? { photoModerationStatus == .pending ? pendingAvatarPath ?? avatarPath : avatarPath }
    var hasPendingContent: Bool { nameModerationStatus == .pending || photoModerationStatus == .pending }
    var needsAutomaticCheck: Bool {
        (nameModerationStatus == .pending && nameCheckState?.shouldResume != false)
            || (photoModerationStatus == .pending && photoCheckState?.shouldResume != false)
    }
    var canRetryCheck: Bool {
        (nameModerationStatus == .pending && nameCheckState == .retry)
            || (photoModerationStatus == .pending && photoCheckState == .retry)
    }
    var hasModerationNotice: Bool {
        communityRestricted == true || nameModerationStatus == .pending || nameModerationStatus == .rejected
            || photoModerationStatus == .pending || photoModerationStatus == .rejected
    }

    func referencesPhoto(_ path: String) -> Bool { avatarPath == path || pendingAvatarPath == path }
}

enum ProfileModerationStatus: String, Codable, Sendable {
    case pending, approved, rejected
}

enum ProfileContentCheckState: String, Codable, Sendable {
    case queued, checking, retry, review, complete
    var shouldResume: Bool { self == .queued || self == .checking }
}

struct ExplorerFriend: Codable, Identifiable, Sendable {
    let id: UUID
    let displayName: String
    let avatar: String
    let shareExploration: Bool
    let countryIds: [String]
    let exploredCount: Int
    var avatarPath: String? = nil
    var exploredCountryIDs: [String] { countryIds }
    var sharesExploration: Bool { shareExploration }
}

struct InvitationPreview: Identifiable, Sendable {
    let id = UUID()
    let displayName: String
    let avatar: String
    let expiresAt: Date?
    let alreadyFriends: Bool
}

struct SocialConfiguration: Sendable {
    let serviceURL: URL
    let publicAPIKey: String
    let invitationHost: String
    let privacyPolicyURL: URL?
    let supportURL: URL?
    var appleSignInEnabled: Bool = false

    static func load(bundle: Bundle = .main) -> SocialConfiguration? {
        struct Settings: Decodable {
            let serviceURL: String
            let publicAPIKey: String
            let invitationHost: String
            let privacyPolicyURL: String
            let supportURL: String
            let appleSignInEnabled: Bool?
        }
        let path = bundle.url(forResource: "SocialConfiguration.local", withExtension: "json")
            ?? bundle.url(forResource: "SocialConfiguration", withExtension: "json")
        guard let path,
              let data = try? Data(contentsOf: path),
              let settings = try? JSONDecoder().decode(Settings.self, from: data),
              let url = URL(string: settings.serviceURL), url.scheme == "https",
              url.host != nil, url.user == nil, url.password == nil,
              isPublicAPIKey(settings.publicAPIKey),
              !settings.invitationHost.isEmpty,
              settings.invitationHost.range(of: #"^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z]{2,}$"#, options: .regularExpression) != nil else { return nil }
        func secureURL(_ value: String) -> URL? {
            guard let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
            return url
        }
        return SocialConfiguration(serviceURL: url, publicAPIKey: settings.publicAPIKey,
                                   invitationHost: settings.invitationHost,
                                   privacyPolicyURL: secureURL(settings.privacyPolicyURL), supportURL: secureURL(settings.supportURL),
                                   appleSignInEnabled: settings.appleSignInEnabled ?? false)
    }

    func invitationURL(token: String) -> URL? {
        guard InvitationLink.isValidToken(token) else { return nil }
        return URL(string: "https://\(invitationHost)/invite/\(token)")
    }

    static func isPublicAPIKey(_ key: String) -> Bool {
        if key.hasPrefix("sb_publishable_") { return key.count > 30 && !key.contains(where: \.isWhitespace) }
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["role"] as? String == "anon" else { return false }
        return true
    }
}

enum InvitationLink {
    static func isValidToken(_ token: String) -> Bool {
        token.utf8.count == 64 && token.allSatisfy { $0.isASCII && ("0123456789abcdef".contains($0)) }
    }

    static func token(from url: URL, allowedHost: String?) -> String? {
        guard url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        let token: String
        if url.scheme == "https", let allowedHost, url.host == allowedHost,
           parts.count == 2, parts[0] == "invite" {
            token = parts[1]
        } else if url.scheme == "worldniche", url.host == "invite", parts.count == 1 {
            token = parts[0]
        } else { return nil }
        let expected = url.scheme == "https" ? "https://\(allowedHost ?? "")/invite/\(token)" : "worldniche://invite/\(token)"
        guard isValidToken(token), url.absoluteString == expected else { return nil }
        return token
    }
}

enum ProfileReportReason: String, CaseIterable, Sendable {
    case inappropriateName = "inappropriate_name"
    case inappropriatePhoto = "inappropriate_photo"
    case harassment, spam, other

    var title: String {
        switch self {
        case .inappropriateName: "Inappropriate name"
        case .inappropriatePhoto: "Inappropriate photo"
        case .harassment: "Harassment"
        case .spam: "Spam"
        case .other: "Something else"
        }
    }
}

enum SocialError: LocalizedError {
    case notConfigured, signInRequired, invalidEmail, invalidCode, invalidName, invalidInvitation
    case rateLimited, unavailable, rejected, invalidResponse, storageFailure
    case codeRejected, appleSignInFailed, appleReauthenticationRequired, invalidPhoto

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Friends are not available in this build yet. Your profile and journal still work on this device."
        case .signInRequired: "Sign in to connect with friends."
        case .invalidEmail: "Enter a valid email address."
        case .invalidCode: "Enter the six-digit code from your email."
        case .codeRejected: "That code has expired or wasn’t accepted. Check your latest email or request a new code."
        case .appleSignInFailed: "Apple sign-in couldn’t be completed. Please try again."
        case .appleReauthenticationRequired: "Confirm with Apple to finish deleting your account and disconnect Sign in with Apple."
        case .invalidPhoto: "Choose a photo we can open. Try a different image if this one doesn’t load."
        case .invalidName: "Choose a name with 1–32 characters, without links or control characters."
        case .invalidInvitation: "This invitation is invalid, expired, or no longer available. Ask your friend for a new link."
        case .rateLimited: "Please wait a moment before trying again."
        case .unavailable: "We couldn’t connect right now. Your existing data is safe; please try again."
        case .rejected: "That request couldn’t be completed. Check your details and try again."
        case .invalidResponse: "The service returned an unexpected response. Please try again."
        case .storageFailure: "Your account couldn’t be saved securely on this device. Please try again."
        }
    }
}

/// Storage paths are opaque identifiers, never arbitrary URLs or filesystem paths.
enum AvatarPhotoReference {
    static let bucket = "profile-photos"
    static let maximumBytes = 300_000
    static func isValidPath(_ path: String) -> Bool {
        path.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$"#, options: .regularExpression) != nil
    }
    static func isValidJPEG(_ data: Data) -> Bool {
        data.count >= 4 && data.count <= maximumBytes && data.prefix(2) == Data([0xff, 0xd8]) && data.suffix(2) == Data([0xff, 0xd9])
    }
}

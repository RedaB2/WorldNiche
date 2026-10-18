import Foundation
import Security

struct SocialSession: Codable, Sendable {
    struct User: Codable, Sendable {
        struct Identity: Codable, Sendable {
            struct Details: Codable, Sendable { let sub: String? }
            let provider: String
            let identityData: Details?
        }
        let id: UUID
        let email: String?
        let identities: [Identity]?
        init(id: UUID, email: String?, identities: [Identity]? = nil) {
            self.id = id; self.email = email; self.identities = identities
        }
        var appleUserID: String? { identities?.first { $0.provider == "apple" }?.identityData?.sub }
        var hasAppleIdentity: Bool { identities?.contains { $0.provider == "apple" } == true }
    }
    let accessToken: String
    let refreshToken: String
    let expiresAt: Double
    let user: User
}

protocol SocialSessionVault: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
    func clear() throws
}

struct KeychainSessionVault: SocialSessionVault {
    private let service = "io.worldniche.app.social"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "session"]
    }
    func load() throws -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SocialError.storageFailure }
        return result as? Data
    }
    func save(_ data: Data) throws {
        let updates = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw SocialError.storageFailure }
        } else if status != errSecSuccess { throw SocialError.storageFailure }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SocialError.storageFailure }
    }
}

/// Authentication and transport stay separate from the UI. Tokens only live in Keychain.
actor SocialAPI {
    private let configuration: SocialConfiguration
    private let transport: URLSession
    private let vault: any SocialSessionVault
    private var session: SocialSession?
    private var refreshTask: Task<SocialSession, Error>?
    private var refreshTaskID: UUID?
    private var generation = UUID()
    private var storageFailed = false

    @MainActor init(configuration: SocialConfiguration, transport: URLSession = SocialAPI.makePrivateTransport(),
         vault: any SocialSessionVault = KeychainSessionVault()) {
        self.configuration = configuration
        self.transport = transport
        self.vault = vault
        do {
            if let data = try vault.load() { session = try JSONDecoder().decode(SocialSession.self, from: data) }
        } catch { storageFailed = true }
    }

    private static func makePrivateTransport() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    func currentUserID() -> UUID? { session?.user.id }
    func currentAppleUserID() -> String? { session?.user.appleUserID }
    func hasAppleIdentity() -> Bool { session?.user.hasAppleIdentity == true }

    func requestCode(email: String, allowNewAccount: Bool = true) async throws {
        guard !storageFailed else { throw SocialError.storageFailure }
        do { _ = try await request(path: "auth/v1/otp", body: ["email": email, "create_user": allowNewAccount], token: nil) }
        catch let error as HTTPFailure { throw Self.authenticationError(error) }
    }

    func verifyCode(email: String, code: String) async throws -> UUID {
        try await signIn(path: "auth/v1/verify", body: ["email": email, "token": code, "type": "email"], invalidCredential: .codeRejected)
    }

    func signInWithApple(identityToken: String, nonce: String) async throws -> UUID {
        guard !identityToken.isEmpty, !nonce.isEmpty else { throw SocialError.appleSignInFailed }
        return try await signIn(path: "auth/v1/token", query: "grant_type=id_token",
                                body: ["provider": "apple", "id_token": identityToken, "nonce": nonce], invalidCredential: .appleSignInFailed)
    }

    private func signIn(path: String, query: String? = nil, body: [String: Any], invalidCredential: SocialError) async throws -> UUID {
        guard !storageFailed else { throw SocialError.storageFailure }
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        refreshTaskID = nil
        let currentGeneration = generation
        let data: Data
        do { data = try await request(path: path, query: query, body: body, token: nil) }
        catch let error as HTTPFailure {
            guard currentGeneration == generation else { throw CancellationError() }
            throw Self.authenticationError(error, invalidCredential: invalidCredential)
        }
        let result = try Self.decodeSession(data)
        guard currentGeneration == generation else { throw CancellationError() }
        try persist(result)
        return result.user.id
    }

    func profile() async throws -> ExplorerProfile? {
        try await rpc("get_my_profile", body: [:])
    }

    func updateProfile(name: String, avatar: String, sharing: Bool) async throws -> ExplorerProfile {
        try await rpc("update_my_profile", body: ["p_display_name": name, "p_avatar": avatar, "p_share_exploration": sharing])
    }

    /// Uploads a new immutable object, then submits it for profile review.
    /// A lost commit response is reconciled before deleting any uploaded object.
    func updateProfilePhoto(_ data: Data?) async throws -> ExplorerProfile {
        guard let userID = session?.user.id else { throw SocialError.signInRequired }
        let requestGeneration = generation
        let previous = try await profile()
        guard generation == requestGeneration, session?.user.id == userID else { throw CancellationError() }
        let path: String?
        if let data {
            guard AvatarPhotoReference.isValidJPEG(data) else { throw SocialError.invalidPhoto }
            let newPath = "\(userID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            _ = try await authenticated(path: "storage/v1/object/\(AvatarPhotoReference.bucket)/\(newPath)", body: [:], rawData: data, contentType: "image/jpeg")
            path = newPath
        } else { path = nil }
        guard generation == requestGeneration, session?.user.id == userID else { throw CancellationError() }
        let updated: ExplorerProfile
        do {
            updated = try await rpc("set_profile_avatar", body: ["p_path": path as Any? ?? NSNull()])
        } catch {
            guard generation == requestGeneration, session?.user.id == userID else { throw CancellationError() }
            if let verified = try? await profile() {
                guard generation == requestGeneration, session?.user.id == userID else { throw CancellationError() }
                if photoSubmissionMatches(verified, path: path) {
                    await removeUnreferencedPhotos(from: previous, after: verified)
                    return verified
                }
                if let path, !verified.referencesPhoto(path) { try? await removePhotoObject(path) }
            }
            throw error
        }
        guard generation == requestGeneration, session?.user.id == userID else { throw CancellationError() }
        guard updated.id == userID, photoSubmissionMatches(updated, path: path) else { throw SocialError.invalidResponse }
        await removeUnreferencedPhotos(from: previous, after: updated)
        return updated
    }

    private func photoSubmissionMatches(_ profile: ExplorerProfile, path: String?) -> Bool {
        if let path { return profile.referencesPhoto(path) }
        return profile.avatarPath == nil && profile.pendingAvatarPath == nil
    }

    private func removeUnreferencedPhotos(from previous: ExplorerProfile?, after updated: ExplorerProfile) async {
        let paths = Set([previous?.avatarPath, previous?.pendingAvatarPath].compactMap { $0 })
        for path in paths where !updated.referencesPhoto(path) { try? await removePhotoObject(path) }
    }

    func avatarData(path: String) async throws -> Data {
        guard AvatarPhotoReference.isValidPath(path) else { throw SocialError.invalidPhoto }
        // A fresh URL also bypasses legacy CDN entries made before cache control was corrected.
        let data = try await authenticated(path: "storage/v1/object/authenticated/\(AvatarPhotoReference.bucket)/\(path)", query: "cacheNonce=\(UUID().uuidString)", body: [:], method: "GET")
        guard AvatarPhotoReference.isValidJPEG(data) else { throw SocialError.invalidPhoto }
        return data
    }

    private func removePhotoObject(_ path: String) async throws {
        guard AvatarPhotoReference.isValidPath(path) else { throw SocialError.invalidPhoto }
        _ = try await authenticated(path: "storage/v1/object/\(AvatarPhotoReference.bucket)", body: ["prefixes": [path]], method: "DELETE")
    }

    struct ExplorationResult: Decodable, Sendable { let countryIds: [String]; let count: Int }
    func syncExplorations(_ ids: [String]) async throws -> [String] {
        let response: ExplorationResult = try await rpc("sync_explorations", body: ["p_country_ids": ids])
        return response.countryIds
    }

    func friends() async throws -> [ExplorerFriend] { try await rpc("list_friends", body: [:]) }

    struct CreatedInvite: Decodable, Sendable { let token: String; let expiresAt: String }
    func createInvite() async throws -> CreatedInvite { try await rpc("create_invite", body: [:]) }

    struct InvitePreview: Decodable, Sendable {
        let status: String
        let displayName: String?
        let avatar: String?
        let expiresAt: String?
        let alreadyFriends: Bool?
    }
    func previewInvite(_ token: String) async throws -> InvitePreview {
        try await rpc("preview_invite", body: ["p_token": token])
    }
    struct AcceptResult: Decodable, Sendable { let status: String; let friendId: UUID? }
    func acceptInvite(_ token: String) async throws -> AcceptResult {
        try await rpc("accept_invite", body: ["p_token": token])
    }

    private struct Acknowledgement: Decodable, Sendable { let ok: Bool }
    func revokeInvites() async throws {
        let result: Acknowledgement = try await rpc("revoke_invites", body: [:])
        guard result.ok else { throw SocialError.rejected }
    }
    func removeFriend(_ id: UUID, block: Bool = false) async throws {
        let result: Acknowledgement = try await rpc(block ? "block_user" : "remove_friend", body: ["p_user_id": id.uuidString])
        guard result.ok else { throw SocialError.rejected }
    }
    func report(_ id: UUID, reason: String, details: String = "") async throws {
        let details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ProfileReportReason(rawValue: reason) != nil, details.count <= 500 else { throw SocialError.rejected }
        let result: Acknowledgement = try await rpc("report_user", body: ["p_user_id": id.uuidString, "p_reason": reason, "p_details": details])
        guard result.ok else { throw SocialError.rejected }
    }

    func exportData() async throws -> Data { try await authenticated(path: "rest/v1/rpc/export_my_data", body: [:]) }

    struct DeletionResult: Decodable, Sendable { let deleted: Bool; let appleRevocation: String? }
    @discardableResult
    func deleteAccount(appleAuthorizationCode: String? = nil, appleNonce: String? = nil, appleManualRevocation: Bool = false) async throws -> DeletionResult {
        guard let session else { throw SocialError.signInRequired }
        let requestGeneration = generation
        // A still-valid JWT can confirm an already-completed deletion after a
        // lost response. Refreshing it first would fail for the removed account.
        let token = session.expiresAt > Date().timeIntervalSince1970
            ? session.accessToken : try await validToken()
        guard generation == requestGeneration, self.session?.user.id == session.user.id else { throw CancellationError() }
        let data: Data
        var body: [String: Any] = [:]
        if let appleAuthorizationCode { body["apple_authorization_code"] = appleAuthorizationCode }
        if let appleNonce { body["apple_nonce"] = appleNonce }
        if appleManualRevocation { body["apple_manual_revocation"] = true }
        do { data = try await request(path: "functions/v1/delete-account", body: body, token: token) }
        catch let error as HTTPFailure {
            guard generation == requestGeneration, self.session?.user.id == session.user.id else { throw CancellationError() }
            switch error.status {
            case 409 where error.code == "apple_reauthentication_required": throw SocialError.appleReauthenticationRequired
            case 401, 403: throw SocialError.signInRequired
            case 429: throw SocialError.rateLimited
            case 500...599: throw SocialError.unavailable
            default: throw SocialError.rejected
            }
        }
        guard generation == requestGeneration, self.session?.user.id == session.user.id else { throw CancellationError() }
        let result = try Self.decoder().decode(DeletionResult.self, from: data)
        guard result.deleted else { throw SocialError.rejected }
        try clearSession()
        return result
    }

    func signOut() async throws {
        if session != nil {
            _ = try await authenticated(path: "auth/v1/logout", query: "scope=local", body: [:])
        }
        try clearSession()
    }

    func forgetSession() throws { try clearSession() }

    /// Apple has definitively revoked this identity. Attempt to end the hosted
    /// session, but remove local access even when the network is unavailable.
    @discardableResult
    func revokeAppleSession(userID: String) async throws -> Bool {
        guard let session, session.user.appleUserID == userID else { return false }
        var storageError: (any Error)?
        do { try clearSession() }
        catch { storageError = error }
        let requestGeneration = generation
        _ = try? await request(path: "auth/v1/logout", query: "scope=local", body: [:], token: session.accessToken)
        guard generation == requestGeneration else { return false }
        if let storageError { throw storageError }
        return true
    }

    private func clearSession() throws {
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        refreshTaskID = nil
        session = nil
        do {
            try vault.clear()
            storageFailed = false
        } catch {
            storageFailed = true
            throw error
        }
    }

    private func persist(_ value: SocialSession) throws {
        try vault.save(JSONEncoder().encode(value))
        session = value
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static func decodeSession(_ data: Data) throws -> SocialSession {
        struct Response: Decodable {
            let accessToken: String
            let refreshToken: String
            let expiresAt: Double?
            let expiresIn: Double?
            let user: SocialSession.User
        }
        let response = try decoder().decode(Response.self, from: data)
        guard !response.accessToken.isEmpty, !response.refreshToken.isEmpty else { throw SocialError.invalidResponse }
        return SocialSession(accessToken: response.accessToken, refreshToken: response.refreshToken,
                             expiresAt: response.expiresAt ?? Date().timeIntervalSince1970 + (response.expiresIn ?? 3600), user: response.user)
    }

    private func validToken(forceRefresh: Bool = false) async throws -> String {
        guard let session else { throw SocialError.signInRequired }
        let currentGeneration = generation
        if !forceRefresh, session.expiresAt > Date().timeIntervalSince1970 + 60 { return session.accessToken }
        if let refreshTask {
            let updated = try await refreshTask.value
            guard currentGeneration == generation, updated.user.id == session.user.id else { throw CancellationError() }
            return updated.accessToken
        }
        let taskID = UUID()
        let task = Task<SocialSession, Error> {
            let data = try await self.request(path: "auth/v1/token", query: "grant_type=refresh_token",
                                              body: ["refresh_token": session.refreshToken], token: nil)
            return try Self.decodeSession(data)
        }
        refreshTask = task
        refreshTaskID = taskID
        defer {
            if refreshTaskID == taskID { refreshTask = nil; refreshTaskID = nil }
        }
        do {
            let updated = try await task.value
            guard currentGeneration == generation, updated.user.id == session.user.id else { throw CancellationError() }
            try persist(updated)
            return updated.accessToken
        } catch let error as HTTPFailure where error.status == 400 || error.status == 401 || error.status == 403 {
            guard currentGeneration == generation else { throw CancellationError() }
            try clearSession()
            throw SocialError.signInRequired
        }
    }

    private func rpc<Response: Decodable & Sendable>(_ name: String, body: [String: Any]) async throws -> Response {
        let data = try await authenticated(path: "rest/v1/rpc/\(name)", body: body)
        do { return try Self.decoder().decode(Response.self, from: data) }
        catch { throw SocialError.invalidResponse }
    }

    private func authenticated(path: String, query: String? = nil, body: [String: Any], method: String = "POST", rawData: Data? = nil, contentType: String = "application/json") async throws -> Data {
        guard let userID = session?.user.id else { throw SocialError.signInRequired }
        let requestGeneration = generation
        func checkIdentity() throws {
            guard generation == requestGeneration, session?.user.id == userID else { throw CancellationError() }
        }
        do {
            let token = try await validToken()
            try checkIdentity()
            let data: Data
            do { data = try await request(path: path, query: query, body: body, token: token, method: method, rawData: rawData, contentType: contentType) }
            catch let error as HTTPFailure where error.status == 401 {
                try checkIdentity()
                let refreshed = try await validToken(forceRefresh: true)
                try checkIdentity()
                data = try await request(path: path, query: query, body: body, token: refreshed, method: method, rawData: rawData, contentType: contentType)
            }
            try checkIdentity()
            return data
        } catch let error as HTTPFailure {
            try checkIdentity()
            switch error.status {
            case 401: throw SocialError.signInRequired
            case 429: throw SocialError.rateLimited
            case 500...599: throw SocialError.unavailable
            default: throw SocialError.rejected
            }
        }
    }

    private struct HTTPFailure: Error { let status: Int; let code: String? }

    private static func authenticationError(_ error: HTTPFailure, invalidCredential: SocialError = .rejected) -> SocialError {
        switch error.status {
        case 429: .rateLimited
        case 400, 401, 403, 422: invalidCredential
        case 500...599: .unavailable
        default: .rejected
        }
    }

    private func request(path: String, query: String? = nil, body: [String: Any], token: String?, method: String = "POST", rawData: Data? = nil, contentType: String = "application/json") async throws -> Data {
        var components = URLComponents(url: configuration.serviceURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.query = query
        guard let url = components.url else { throw SocialError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue(configuration.publicAPIKey, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if rawData != nil {
            request.setValue("false", forHTTPHeaderField: "x-upsert")
            request.setValue("max-age=0, no-store", forHTTPHeaderField: "cache-control")
        }
        if method != "GET" { request.httpBody = try rawData ?? JSONSerialization.data(withJSONObject: body) }
        try Task.checkCancellation()
        do {
            let (data, response) = try await transport.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw SocialError.invalidResponse }
            guard data.count <= 2_000_000 else { throw SocialError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else {
                let error = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                throw HTTPFailure(status: response.statusCode, code: error?["error_code"] as? String ?? error?["error"] as? String)
            }
            return data
        } catch let error as URLError where error.code != .cancelled { throw SocialError.unavailable }
    }
}

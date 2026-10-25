import Foundation

private let userA = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
private let userB = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
private let friendA = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
private let friendB = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
private let accessSecret = "test-only-access-token-never-real"
private let refreshSecret = "test-only-refresh-token-never-real"
private let appleIdentityToken = "fixture.apple.identity-token-never-real"
private let appleNonce = "fixture-unhashed-apple-nonce-32-characters"
private let inviteToken = String(repeating: "abcdef0123456789", count: 4)
private let configuration = SocialConfiguration(
    serviceURL: URL(string: "https://social.example.test")!, publicAPIKey: "test-public-key",
    invitationHost: "friends.example.test", privacyPolicyURL: nil, supportURL: nil
)

/// An injectable vault ensures this suite never touches the user's real Keychain.
private final class MemoryVault: SocialSessionVault, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    var failLoad = false
    var failSave = false
    var failClear = false
    init(_ session: SocialSession? = nil) { data = session.flatMap { try? JSONEncoder().encode($0) } }
    init(data: Data) { self.data = data }
    func load() throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        if failLoad { throw SocialError.storageFailure }
        return data
    }
    func save(_ value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        if failSave { throw SocialError.storageFailure }
        data = value
    }
    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        if failClear { throw SocialError.storageFailure }
        data = nil
    }
}

private func savedSession(user: UUID = userA, expiresIn: TimeInterval = 3600) -> SocialSession {
    SocialSession(accessToken: accessSecret, refreshToken: refreshSecret,
                  expiresAt: Date().timeIntervalSince1970 + expiresIn,
                  user: .init(id: user, email: "test@example.test"))
}

private struct ObservedRequest: Sendable {
    let path: String
    let query: String?
    let method: String?
    let authorization: String?
    let apiKey: String?
    let cacheControl: String?
    let body: Data
    func json() -> [String: Any] { (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:] }
}

/// State changes are explicit and URLProtocol intercepts every URL, including accidental hosts.
private final class SocialFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [ObservedRequest] = []
    private var failures: [String: [Int]] = [:]
    private var failureCodes: [String: String] = [:]
    private var account = userA
    private var hasProfile = true
    private var sharing = false
    private var name = "Mira"
    private var profileAvatar = "globe"
    private var syncedIDs: [String] = ["JP"]
    private var deletionAcknowledged = true
    private var overrides: [String: Data] = [:]
    private var appleAccount = false
    private var moderatingPhotos = false
    private var approvedPhoto: String?
    private var pendingPhoto: String?
    private var losePhotoCommitResponse = false
    private var profileCheckConsent: Bool?

    func reset(user: UUID = userA, profile: Bool = true, sharing: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        requests = []; failures = [:]; failureCodes = [:]; account = user; hasProfile = profile
        self.sharing = sharing; name = user == userA ? "Mira" : "Noah"; profileAvatar = "globe"
        syncedIDs = ["JP"]; deletionAcknowledged = true; overrides = [:]; appleAccount = false
        moderatingPhotos = false; approvedPhoto = nil; pendingPhoto = nil; losePhotoCommitResponse = false
        profileCheckConsent = nil
    }
    func reviewPhotos(approved: String?, pending: String? = nil, loseCommitResponse: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        moderatingPhotos = true; approvedPhoto = approved; pendingPhoto = pending
        losePhotoCommitResponse = loseCommitResponse
    }
    func fail(_ path: String, statuses: [Int], code: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        failures[path] = statuses; failureCodes[path] = code
    }
    func acknowledgeDeletion(_ value: Bool) { lock.lock(); defer { lock.unlock() }; deletionAcknowledged = value }
    func respond(_ path: String, json: String) {
        lock.lock(); defer { lock.unlock() }
        overrides[path] = Data(json.utf8)
    }
    func respond(_ path: String, data: Data) {
        lock.lock(); defer { lock.unlock() }
        overrides[path] = data
    }
    func switchAccount(to user: UUID) {
        lock.lock(); defer { lock.unlock() }
        account = user; name = user == userA ? "Mira" : "Noah"; appleAccount = false
    }
    func observed(_ path: String? = nil) -> [ObservedRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests.filter { path == nil || $0.path == path }
    }
    func clearRequests() { lock.lock(); defer { lock.unlock() }; requests = [] }

    func response(to request: URLRequest) -> (Int, Data) {
        let observed = ObservedRequest(path: request.url!.path, query: request.url!.query,
                                       method: request.httpMethod,
                                       authorization: request.value(forHTTPHeaderField: "Authorization"),
                                       apiKey: request.value(forHTTPHeaderField: "apikey"), cacheControl: request.value(forHTTPHeaderField: "Cache-Control"), body: Self.body(request))
        lock.lock(); defer { lock.unlock() }
        requests.append(observed)
        guard request.url!.host == "social.example.test" else {
            return (599, Data("unexpected host".utf8))
        }
        if var queue = failures[observed.path], !queue.isEmpty {
            let status = queue.removeFirst()
            failures[observed.path] = queue
            return (status, try! JSONSerialization.data(withJSONObject: ["error": failureCodes[observed.path] ?? "fixture failure"]))
        }
        if let data = overrides[observed.path] { return (200, data) }
        let body = observed.json()
        let value: Any
        switch observed.path {
        case "/auth/v1/otp", "/auth/v1/logout": value = [:] as [String: String]
        case "/auth/v1/verify", "/auth/v1/token":
            if observed.query == "grant_type=id_token" { appleAccount = true }
            let access = observed.path == "/auth/v1/token"
                ? (account == userA ? "refreshed-test-access" : "refreshed-account-B")
                : (account == userA ? accessSecret : "access-account-B")
            var authUser: [String: Any] = ["id": account.uuidString, "email": "test@example.test"]
            if appleAccount {
                authUser["identities"] = [["provider": "apple", "identity_data": ["sub": "apple-fixture-user-\(account.uuidString)"]]]
            }
            value = ["access_token": access,
                     "refresh_token": refreshSecret, "expires_in": 3600,
                     "user": authUser]
        case "/rest/v1/rpc/get_my_profile": value = hasProfile ? profileJSON() : NSNull()
        case "/rest/v1/rpc/update_my_profile":
            name = body["p_display_name"] as? String ?? "Missing name"
            sharing = body["p_share_exploration"] as? Bool ?? false
            hasProfile = true
            profileAvatar = body["p_avatar"] as? String ?? "globe"
            value = profileJSON()
        case "/rest/v1/rpc/set_profile_check_consent":
            guard hasProfile else { return (400, Data(#"{"error":"profile required"}"#.utf8)) }
            profileCheckConsent = body["p_enabled"] as? Bool
            value = profileJSON()
        case "/rest/v1/rpc/set_profile_avatar" where moderatingPhotos:
            pendingPhoto = body["p_path"] as? String
            if pendingPhoto == nil { approvedPhoto = nil }
            if losePhotoCommitResponse {
                losePhotoCommitResponse = false
                return (503, Data(#"{"error":"lost response after commit"}"#.utf8))
            }
            value = profileJSON()
        case "/rest/v1/rpc/list_friends":
            value = [["id": friendA.uuidString, "display_name": "Jun", "avatar": "wave",
                      "share_exploration": true, "country_ids": ["FR"], "explored_count": 1],
                     ["id": friendB.uuidString, "display_name": "Sam", "avatar": "sun",
                      "share_exploration": false, "country_ids": ["FR"], "explored_count": 1]]
        case "/rest/v1/rpc/sync_explorations":
            let submitted = body["p_country_ids"] as? [String] ?? []
            value = ["country_ids": Array(Set(submitted + syncedIDs + ["INVALID"])).sorted(), "count": 2]
        case "/rest/v1/rpc/create_invite": value = ["token": inviteToken, "expires_at": "2026-10-25T12:00:00Z"]
        case "/rest/v1/rpc/preview_invite":
            value = ["status": "available", "display_name": "Jun", "avatar": "wave",
                     "expires_at": "2026-10-25T12:00:00Z", "already_friends": false]
        case "/rest/v1/rpc/accept_invite": value = ["status": "accepted", "friend_id": friendA.uuidString]
        case "/rest/v1/rpc/export_my_data": value = ["user_id": account.uuidString, "profile": profileJSON()]
        case "/functions/v1/delete-account": value = ["deleted": deletionAcknowledged]
        case "/rest/v1/rpc/revoke_invites", "/rest/v1/rpc/remove_friend", "/rest/v1/rpc/block_user", "/rest/v1/rpc/report_user":
            value = ["ok": true]
        case let path where moderatingPhotos && path.hasPrefix("/storage/v1/object/profile-photos"):
            value = ["ok": true]
        default: return (404, Data(#"{"error":"unhandled fixture route"}"#.utf8))
        }
        return (200, try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]))
    }

    private func profileJSON() -> [String: Any] {
        var value: [String: Any] = ["id": account.uuidString, "display_name": name, "avatar": profileAvatar, "share_exploration": sharing]
        if let profileCheckConsent {
            value["automatic_profile_checks_enabled"] = profileCheckConsent
            value["profile_check_consent_recorded"] = true
        }
        if moderatingPhotos {
            value["avatar_path"] = approvedPhoto as Any? ?? NSNull()
            value["pending_avatar_path"] = pendingPhoto as Any? ?? NSNull()
            value["photo_moderation_status"] = pendingPhoto == nil ? "approved" : "pending"
        }
        return value
    }
    private static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
private let fixture = SocialFixture()
/// Captures one actual URLProtocol response, releasing it only after a competing
/// identity transition. This makes auth races deterministic rather than timing guesses.
private final class ResponseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var path: String?
    private var held: (SocialProtocol, Int, Data)?
    func arm(_ path: String) { lock.lock(); defer { lock.unlock() }; self.path = path; held = nil }
    func capture(_ request: SocialProtocol, status: Int, data: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard request.request.url?.path == path, held == nil else { return false }
        path = nil
        held = (request, status, data)
        return true
    }
    func isHolding() -> Bool { lock.lock(); defer { lock.unlock() }; return held != nil }
    func release() {
        lock.lock(); let value = held; held = nil; path = nil; lock.unlock()
        if let (request, status, data) = value { request.deliver(status: status, data: data) }
    }
}
private let responseGate = ResponseGate()
private final class SocialProtocol: URLProtocol, @unchecked Sendable {
    private let stopLock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = fixture.response(to: request)
        if status < 0 {
            client?.urlProtocol(self, didFailWithError: URLError(URLError.Code(rawValue: status)))
            return
        }
        if responseGate.capture(self, status: status, data: data) { return }
        deliver(status: status, data: data)
    }
    func deliver(status: Int, data: Data) {
        stopLock.lock(); let cancelled = stopped; stopLock.unlock()
        guard !cancelled else { return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { stopLock.lock(); stopped = true; stopLock.unlock() }
}

@MainActor
private final class CheckSuite {
    var failures: [String] = []
    var assertions = 0
    var domains: [String] = []
    let photoDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("social-photos-\(UUID().uuidString)", isDirectory: true)
    let transport: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SocialProtocol.self]
        return URLSession(configuration: configuration)
    }()

    func check(_ condition: Bool, _ message: String) {
        assertions += 1
        if !condition { failures.append(message); print("FAIL: \(message)") }
    }
    func isolatedDefaults() -> UserDefaults {
        let name = "io.worldniche.tests.social.\(UUID().uuidString)"
        domains.append(name)
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
    func api(vault: MemoryVault) -> SocialAPI {
        SocialAPI(configuration: configuration, transport: transport, vault: vault)
    }
    func cleanup() { for name in domains { UserDefaults.standard.removePersistentDomain(forName: name) }; try? FileManager.default.removeItem(at: photoDirectory) }

    func links() {
        check(InvitationLink.token(from: URL(string: "https://friends.example.test/invite/\(inviteToken)")!, allowedHost: configuration.invitationHost) == inviteToken, "Canonical HTTPS invitation must parse")
        check(InvitationLink.token(from: URL(string: "worldniche://invite/\(inviteToken)")!, allowedHost: nil) == inviteToken, "Canonical app invitation must parse")
        let invalid = [
            "http://friends.example.test/invite/\(inviteToken)",
            "https://evil.test/invite/\(inviteToken)",
            "https://friends.example.test.evil.test/invite/\(inviteToken)",
            "https://user@friends.example.test/invite/\(inviteToken)",
            "https://user:pass@friends.example.test/invite/\(inviteToken)",
            "https://friends.example.test:443/invite/\(inviteToken)",
            "https://friends.example.test/invite/\(inviteToken)?source=test",
            "https://friends.example.test/invite/\(inviteToken)?",
            "https://friends.example.test/invite/\(inviteToken)#fragment",
            "https://friends.example.test/invite/\(inviteToken)#",
            "https://friends.example.test/wrong/\(inviteToken)",
            "https://friends.example.test/invite/\(inviteToken)/extra",
            "https://friends.example.test/invite//\(inviteToken)",
            "https://friends.example.test//invite/\(inviteToken)",
            "https://friends.example.test/invite/\(inviteToken)/",
            "https://friends.example.test/invite/\(inviteToken.uppercased())",
            "https://friends.example.test/invite/\(inviteToken.dropLast())",
            "https://friends.example.test/invite/\(inviteToken)0",
            "https://friends.example.test/invite/%61\(inviteToken.dropFirst())",
            "https://friends.example.test/invite/%2e%2e/\(inviteToken)",
            "worldniche://other/\(inviteToken)",
            "worldniche://invite//\(inviteToken)",
            "worldniche://invite/\(inviteToken)/",
            "worldniche://invite/\(inviteToken)?token=other"
        ]
        for raw in invalid {
            guard let url = URL(string: raw) else { check(false, "Malformed test URL fixture"); continue }
            check(InvitationLink.token(from: url, allowedHost: configuration.invitationHost) == nil,
                  "Invitation parser must reject noncanonical URL: \(raw)")
        }
        check(InvitationLink.token(from: URL(string: "https://friends.example.test/invite/\(inviteToken)")!, allowedHost: nil) == nil, "Unconfigured HTTPS host must not be trusted")
        check(configuration.invitationURL(token: inviteToken)?.absoluteString == "https://friends.example.test/invite/\(inviteToken)", "Generated invitation must use configured HTTPS host")
        check(configuration.invitationURL(token: "bad") == nil, "Cannot generate invitation from malformed token")
    }

    func localData() async {
        let defaults = isolatedDefaults()
        let culture = LiveCultureService(topics: [:], persistsHistory: true, historySuiteName: domains.last!)
        defaults.set(["Azonto"], forKey: "worldniche.culture.history.GH")
        defaults.set("unrelated sentinel", forKey: "unrelated.preference")
        let journal = DiscoveryJournal(defaults: defaults)
        let store = SocialStore(journal: journal, defaults: defaults, photoDirectory: photoDirectory, configuration: nil, culture: culture)
        check(!store.isConfigured && !store.isSignedIn && store.profile == nil, "Local mode starts without fake profile or account")
        await store.saveProfile(name: "  Mira  ", avatar: "leaf", sharing: false)
        check(store.profile?.displayName == "Mira" && store.profile?.avatar == "leaf", "Local profile trims name and retains chosen avatar")
        check(store.profile?.shareExploration == false && store.profile?.id == nil, "Local profile is private and has no fabricated account ID")
        await store.saveProfile(name: String(repeating: "x", count: 33), avatar: "leaf", sharing: false)
        check(store.errorMessage != nil && store.profile?.displayName == "Mira", "Too-long name must not overwrite valid profile")
        for name in ["", "  ", "bad\nname", "https://spam.example"] {
            await store.saveProfile(name: name, avatar: "leaf", sharing: false)
            check(store.errorMessage != nil && store.profile?.displayName == "Mira", "Invalid profile name must preserve prior profile")
        }
        await store.saveProfile(name: "Mira", avatar: "not-a-symbol", sharing: false)
        check(store.errorMessage != nil && store.profile?.avatar == "leaf", "Unknown avatar must be rejected")
        let restored = SocialStore(journal: journal, defaults: defaults, photoDirectory: photoDirectory, configuration: nil)
        check(restored.profile?.displayName == "Mira", "Local profile must survive store reconstruction")
        journal.visit(CountryRepository.country(id: "FR")!)
        journal.toggleSaved(CountryRepository.country(id: "JP")!)
        guard let exported = await store.exportData(), let data = try? Data(contentsOf: exported),
              let document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let local = document["local"] as? [String: Any] else {
            check(false, "Local data export must produce readable JSON"); return
        }
        check(document["account"] == nil && (local["exploredCountryIDs"] as? [String]) == ["FR"], "Local export must accurately contain journal without fake account data")
        check((local["savedCountryIDs"] as? [String]) == ["JP"], "Local export must contain private saved countries")
        await store.clearLocalData()
        check(defaults.object(forKey: "worldniche.culture.history.GH") == nil, "Local wipe must erase persisted cultural reading history")
        check(store.profile == nil && journal.visitedIDs.isEmpty && journal.savedIDs.isEmpty, "Local wipe must clear profile, journal and saved countries")
        check(defaults.string(forKey: "unrelated.preference") == "unrelated sentinel", "Local wipe must preserve unrelated preferences")
        check(!FileManager.default.fileExists(atPath: exported.path), "Local wipe must erase exported private data")

        // An export must not survive a relaunch followed by data erasure.
        await store.saveProfile(name: "Mira", avatar: "globe", sharing: false)
        if let previousExport = await store.exportData() {
            let relaunched = SocialStore(journal: journal, defaults: defaults, photoDirectory: photoDirectory, configuration: nil)
            await relaunched.clearLocalData()
            check(!FileManager.default.fileExists(atPath: previousExport.path), "Data erasure after relaunch must remove exports from the earlier session")
        } else { check(false, "Second local export fixture must be created") }
    }

    func authentication() async {
        fixture.reset()
        let defaults = isolatedDefaults()
        let journal = DiscoveryJournal(defaults: defaults)
        let vault = MemoryVault()
        let service = api(vault: vault)
        let store = SocialStore(journal: journal, defaults: defaults, photoDirectory: photoDirectory, configuration: configuration, api: service)
        await store.requestCode(email: "not an email")
        check(fixture.observed().isEmpty && store.emailForCode == nil, "Invalid email must be rejected before any network request")
        await store.requestCode(email: " TEST@EXAMPLE.TEST ")
        let otp = fixture.observed("/auth/v1/otp")
        check(otp.count == 1 && otp.first?.json()["email"] as? String == "test@example.test", "OTP request normalizes email exactly once")
        check(otp.first?.method == "POST" && otp.first?.apiKey == "test-public-key" && otp.first?.authorization == nil, "OTP uses public API key, never a stale bearer token")
        await store.requestCode(email: "test@example.test")
        check(fixture.observed("/auth/v1/otp").count == 1 && store.errorMessage != nil, "Repeated OTP request is locally rate limited")
        for code in ["12", "1234567", "１２３４５６", "12345a"] {
            await store.verifyCode(code: code)
            check(fixture.observed("/auth/v1/verify").isEmpty, "Only six ASCII digits may reach OTP verification")
        }
        await store.verifyCode(code: "123456")
        check(store.isSignedIn && store.profile?.id == userA, "Successful OTP restores authenticated account profile")
        check(store.emailForCode == nil && !store.isBusy, "Successful sign-in clears pending email and busy state")
        let vaultText = (try? vault.load()).flatMap { $0 }.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        check(vaultText.contains(accessSecret) && vaultText.contains(refreshSecret), "Successful authentication persists tokens in injected secure vault")
        let preferenceText = defaults.dictionaryRepresentation().values.map { value -> String in
            if let data = value as? Data { return String(data: data, encoding: .utf8) ?? "" }
            return String(describing: value)
        }.joined()
        check(!preferenceText.contains(accessSecret) && !preferenceText.contains(refreshSecret), "Session tokens must never enter UserDefaults")
        check(fixture.observed("/rest/v1/rpc/sync_explorations").isEmpty, "Sign-in with sharing off must not upload local journal")
        await store.clearLocalData()
        let clearedIdentity = await service.currentUserID()
        check((try? vault.load()) == nil && clearedIdentity == nil, "Local wipe must clear both secure vault and actor authentication")
        check(fixture.observed("/functions/v1/delete-account").isEmpty, "Local wipe must not claim or perform online account deletion")

        fixture.reset()
        let failingVault = MemoryVault()
        failingVault.failSave = true
        let failedService = api(vault: failingVault)
        do {
            _ = try await failedService.verifyCode(email: "test@example.test", code: "123456")
            check(false, "Vault save failure must reject authentication")
        } catch { check(await failedService.currentUserID() == nil, "Vault save failure must not leave an unpersisted signed-in session") }
    }

    func tokenRefresh() async {
        fixture.reset()
        let vault = MemoryVault(savedSession(expiresIn: -1))
        let service = api(vault: vault)
        do {
            async let profile = service.profile()
            async let friends = service.friends()
            _ = try await (profile, friends)
            check(fixture.observed("/auth/v1/token").count == 1, "Concurrent expired-session calls must share one token refresh")
            let refresh = fixture.observed("/auth/v1/token").first
            check(refresh?.query == "grant_type=refresh_token" && refresh?.json()["refresh_token"] as? String == refreshSecret, "Refresh must use exact auth grant and stored refresh token")
            check(fixture.observed("/rest/v1/rpc/get_my_profile").allSatisfy { $0.authorization == "Bearer refreshed-test-access" }, "RPC after expiry must use new access token")
        } catch { check(false, "Expired session should recover: \(error)") }

        fixture.reset()
        fixture.fail("/rest/v1/rpc/get_my_profile", statuses: [401])
        let rejectedAccess = api(vault: MemoryVault(savedSession()))
        do {
            _ = try await rejectedAccess.profile()
            let calls = fixture.observed("/rest/v1/rpc/get_my_profile")
            check(calls.count == 2 && calls.last?.authorization == "Bearer refreshed-test-access", "One rejected access token must refresh then retry RPC once")
            check(fixture.observed("/auth/v1/token").count == 1, "401 recovery must perform one refresh")
        } catch { check(false, "401 access recovery should succeed: \(error)") }

        fixture.reset()
        fixture.fail("/auth/v1/token", statuses: [401])
        let rejectedVault = MemoryVault(savedSession(expiresIn: -1))
        let rejectedRefresh = api(vault: rejectedVault)
        do { _ = try await rejectedRefresh.profile(); check(false, "Rejected refresh token must not yield a profile") }
        catch {
            check((error as? SocialError)?.localizedDescription == SocialError.signInRequired.localizedDescription, "Invalid refresh token must require sign-in")
            check(await rejectedRefresh.currentUserID() == nil && (try? rejectedVault.load()) == nil, "Invalid refresh must clear secure and in-memory auth")
        }

        fixture.reset()
        fixture.fail("/auth/v1/token", statuses: [URLError.notConnectedToInternet.rawValue])
        let offlineVault = MemoryVault(savedSession(expiresIn: -1))
        let offline = api(vault: offlineVault)
        do { _ = try await offline.profile(); check(false, "Offline expired session must not fabricate a profile") }
        catch {
            check(await offline.currentUserID() == userA && (try? offlineVault.load()) != nil,
                  "Temporary offline refresh must preserve the session for seamless reconnect")
        }
        do {
            _ = try await offline.profile()
            check(await offline.currentUserID() == userA, "Reconnect must recover without another sign-in code")
        } catch { check(false, "Offline session should recover after connectivity returns: \(error)") }
    }

    func appleAuthentication() async {
        fixture.reset()
        let vault = MemoryVault()
        let service = api(vault: vault)
        do {
            let identity = try await service.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce)
            let currentIdentity = await service.currentUserID()
            check(identity == userA && currentIdentity == userA,
                  "Apple identity exchange must establish the authenticated Supabase user")
            let request = fixture.observed("/auth/v1/token").first
            check(request?.method == "POST" && request?.query == "grant_type=id_token",
                  "Native Apple sign-in must use Supabase's id_token grant")
            check(request?.json()["provider"] as? String == "apple"
                  && request?.json()["id_token"] as? String == appleIdentityToken
                  && request?.json()["nonce"] as? String == appleNonce,
                  "Apple exchange must send the identity token and original unhashed nonce")
            check(request?.authorization == nil && request?.apiKey == "test-public-key",
                  "Apple identity exchange must not attach a prior account's bearer token")
            let persisted = (try? vault.load()).flatMap { $0 }.flatMap { try? JSONDecoder().decode(SocialSession.self, from: $0) }
            check(persisted?.user.id == userA && persisted?.refreshToken == refreshSecret,
                  "Apple sign-in must securely persist a refreshable Supabase session")
            check(await service.currentAppleUserID() == "apple-fixture-user-\(userA.uuidString)",
                  "Apple credential-state identity must come from the authenticated server identity")
            check(!String(data: (try? vault.load()) ?? Data(), encoding: .utf8)!.contains(appleIdentityToken),
                  "Apple's short-lived identity token must not be stored as the long-lived session")
        } catch { check(false, "Valid Apple token fixture must sign in: \(error)") }

        fixture.reset()
        let failedVault = MemoryVault()
        failedVault.failSave = true
        let failed = api(vault: failedVault)
        do {
            _ = try await failed.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce)
            check(false, "Apple authentication must fail if secure persistence fails")
        } catch { check(await failed.currentUserID() == nil, "Failed Apple secure save must not create an in-memory-only login") }

        fixture.reset()
        fixture.fail("/auth/v1/token", statuses: [400])
        let rejected = api(vault: MemoryVault())
        do {
            _ = try await rejected.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce)
            check(false, "Rejected Apple identity must not report authentication success")
        } catch { check(await rejected.currentUserID() == nil, "Rejected Apple token must not leave a session") }

        fixture.reset()
        fixture.respond("/auth/v1/token", json: #"{"access_token":"","refresh_token":"","expires_in":3600,"user":{"id":"11111111-1111-4111-8111-111111111111"}}"#)
        let malformed = api(vault: MemoryVault())
        do {
            _ = try await malformed.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce)
            check(false, "Malformed Apple auth session must never be accepted")
        } catch { check(await malformed.currentUserID() == nil, "Malformed Apple response must leave account signed out") }
    }

    func appleAuthenticationRaces() async {
        fixture.reset()
        let vault = MemoryVault()
        let service = api(vault: vault)
        responseGate.arm("/auth/v1/token")
        let olderApple = Task {
            do { _ = try await service.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce); return true }
            catch { return false }
        }
        guard await waitForHeldResponse() else {
            check(false, "Apple race fixture must intercept its response")
            responseGate.release(); olderApple.cancel(); return
        }
        fixture.switchAccount(to: userB)
        do { _ = try await service.verifyCode(email: "other@example.test", code: "123456") }
        catch { check(false, "Newer email sign-in must succeed during pending Apple exchange: \(error)") }
        responseGate.release()
        check(!(await olderApple.value), "Older Apple exchange must be cancelled after newer email sign-in")
        check(await service.currentUserID() == userB,
              "Late Apple token must not overwrite the newer email account")
        let persisted = (try? vault.load()).flatMap { $0 }.flatMap { try? JSONDecoder().decode(SocialSession.self, from: $0) }
        check(persisted?.user.id == userB, "Late Apple response must not replace newer persisted credentials")

        fixture.reset()
        let clearedVault = MemoryVault()
        let clearedService = api(vault: clearedVault)
        responseGate.arm("/auth/v1/token")
        let pendingApple = Task {
            do { _ = try await clearedService.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce); return true }
            catch { return false }
        }
        guard await waitForHeldResponse() else {
            check(false, "Clear-during-Apple fixture must intercept its response")
            responseGate.release(); pendingApple.cancel(); return
        }
        try? await clearedService.forgetSession()
        responseGate.release()
        check(!(await pendingApple.value), "Local sign-out must invalidate any pending Apple exchange")
        check(await clearedService.currentUserID() == nil && (try? clearedVault.load()) == nil,
              "Late Apple authentication must never resurrect cleared credentials")
    }

    func persistentRestoration() async {
        fixture.reset()
        let defaults = isolatedDefaults()
        let vault = MemoryVault(savedSession())
        let restored = api(vault: vault)
        check(await restored.currentUserID() == userA && (try? vault.load()) != nil,
              "Existing secure credentials must restore without any app-container installation marker")
        let relaunched = api(vault: vault)
        check(await relaunched.currentUserID() == userA && (try? vault.load()) != nil,
              "Successive API instances must retain and restore the secure session")
        check(fixture.observed().isEmpty, "Restoring a still-valid local session must not request another email code")
        let journal = DiscoveryJournal(defaults: defaults)
        let store = SocialStore(journal: journal, defaults: defaults, photoDirectory: photoDirectory, configuration: configuration, api: relaunched)
        await store.refresh()
        check(store.isSignedIn && store.profile?.id == userA,
              "An empty preferences container must still restore a valid Keychain-backed account")
        check(fixture.observed("/auth/v1/otp").isEmpty && fixture.observed("/auth/v1/verify").isEmpty,
              "Restoring account data must not require another sign-in code")
        await store.signOut()
        let signedOut = api(vault: vault)
        check(await signedOut.currentUserID() == nil && (try? vault.load()) == nil,
              "Explicit sign-out must clear credentials so a later launch stays signed out")

        let lockedVault = MemoryVault(savedSession())
        lockedVault.failLoad = true
        let blocked = api(vault: lockedVault)
        check(await blocked.currentUserID() == nil, "Unavailable secure storage must never fabricate an authenticated account")
        fixture.clearRequests()
        do {
            try await blocked.requestCode(email: "test@example.test")
            check(false, "Secure-storage read failure must block authentication until storage becomes available")
        } catch {
            check((error as? SocialError)?.localizedDescription == SocialError.storageFailure.localizedDescription,
                  "Failed initialization must explain secure storage failure")
        }
        check(fixture.observed().isEmpty, "Failed secure initialization must not issue auth network requests")
        lockedVault.failLoad = false
        let recovered = api(vault: lockedVault)
        check(await recovered.currentUserID() == userA && (try? lockedVault.load()) != nil,
              "A temporary secure-storage failure must preserve credentials for restoration on a later launch")
    }

    func secureStorageRecovery() async {
        fixture.reset()
        let corruptVault = MemoryVault(data: Data("unreadable session record".utf8))
        let corrupt = api(vault: corruptVault)
        check(await corrupt.currentUserID() == nil, "Corrupted persisted session must not produce an authenticated identity")
        do {
            try await corrupt.requestCode(email: "test@example.test")
            check(false, "Corrupted secure session must initially block authentication")
        } catch {
            check((error as? SocialError)?.localizedDescription == SocialError.storageFailure.localizedDescription,
                  "Corrupt session must expose a recoverable secure-storage error")
        }
        check(fixture.observed().isEmpty, "Corrupt secure storage must be resolved before sending an email code")
        do {
            try await corrupt.forgetSession()
            try await corrupt.requestCode(email: "test@example.test")
            _ = try await corrupt.verifyCode(email: "test@example.test", code: "123456")
            check(await corrupt.currentUserID() == userA,
                  "Successful local cleanup must allow email authentication without recreating the API actor")
        } catch { check(false, "Cleaning a corrupted vault must restore authentication immediately: \(error)") }

        fixture.reset()
        let unavailableVault = MemoryVault(savedSession())
        unavailableVault.failLoad = true
        let unavailable = api(vault: unavailableVault)
        unavailableVault.failLoad = false
        unavailableVault.failClear = true
        do {
            try await unavailable.forgetSession()
            check(false, "Failed secure clear must not be reported as successful cleanup")
        } catch {
            check(await unavailable.currentUserID() == nil && (try? unavailableVault.load()) != nil,
                  "Failed cleanup must not adopt the unresolved stored account")
        }
        do {
            try await unavailable.requestCode(email: "test@example.test")
            check(false, "Failed cleanup must leave authentication blocked")
        } catch {
            check((error as? SocialError)?.localizedDescription == SocialError.storageFailure.localizedDescription,
                  "Failed cleanup must retain the secure-storage error")
        }
        check(fixture.observed().isEmpty, "Failed clear must not allow auth requests to escape")
        unavailableVault.failClear = false
        do {
            try await unavailable.forgetSession()
            _ = try await unavailable.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce)
            check(await unavailable.currentUserID() == userA,
                  "Successful retry after a load/clear failure must allow Apple authentication in the same actor")
        } catch { check(false, "Recovered secure storage must allow immediate Apple sign-in: \(error)") }

        fixture.reset()
        let validVault = MemoryVault(savedSession())
        let valid = api(vault: validVault)
        validVault.failClear = true
        do { try await valid.forgetSession(); check(false, "A healthy session's failed clear must report failure") }
        catch { check(await valid.currentUserID() == nil, "Failed explicit cleanup must still stop using in-memory credentials") }
        do {
            try await valid.requestCode(email: "test@example.test")
            check(false, "Failed clear from a healthy actor must block new authentication until resolved")
        } catch {
            check((error as? SocialError)?.localizedDescription == SocialError.storageFailure.localizedDescription,
                  "A later clear failure must mark previously healthy storage as unresolved")
        }
        check(fixture.observed().isEmpty, "Previously healthy storage must also fail closed after cleanup fails")
    }

    func pendingDeletionPreservesAppleProof() async {
        fixture.reset()
        let defaults = isolatedDefaults()
        let journal = DiscoveryJournal(defaults: defaults)
        let vault = MemoryVault()
        let service = api(vault: vault)
        let store = SocialStore(journal: journal, defaults: defaults, photoDirectory: photoDirectory, configuration: configuration, api: service,
                                appleCredentialIsAuthorized: { _ in false })
        await store.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce, name: nil)
        guard let appleID = store.appleUserID else { check(false, "Apple deletion fixture must have a server-backed Apple identity"); return }
        let proof = try? vault.load()
        fixture.clearRequests()
        fixture.fail("/functions/v1/delete-account", statuses: [URLError.networkConnectionLost.rawValue])
        let interrupted = await store.deleteAccountAndData(appleAuthorizationCode: "fixture-apple-delete-code", appleNonce: appleNonce)
        check(interrupted == .incomplete, "Lost Apple deletion response must not ask for another authorization automatically")
        check(store.deletionPending && store.isSignedIn,
              "Lost Apple deletion response must retain pending state and authentication")
        await store.refresh()
        await store.invalidateAppleSession(userID: appleID)
        check(store.deletionPending && store.isSignedIn && store.appleUserID == appleID,
              "Apple credential revocation while deletion is pending must not invalidate retained confirmation state")
        check(await service.currentUserID() == userA && (try? vault.load()) == proof,
              "Pending deletion must preserve the exact session proof despite an Apple revocation callback")
        let confirmed = await store.deleteAccountAndData()
        check(confirmed == .complete, "Retained proof must report completed deletion when the server confirms absence")
        check(!store.deletionPending && !store.isSignedIn && (try? vault.load()) == nil,
              "Retained Apple deletion proof must permit confirmation retry and then be erased")
        check(fixture.observed("/functions/v1/delete-account").count == 2
              && fixture.observed("/auth/v1/token").isEmpty && fixture.observed("/auth/v1/logout").isEmpty,
              "Apple deletion confirmation must retry the deletion endpoint without replacing its retained proof")
    }

    func appleCredentialRevocation() async {
        for networkAvailable in [true, false] {
            fixture.reset(sharing: true)
            let vault = MemoryVault()
            let service = api(vault: vault)
            do { _ = try await service.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce) }
            catch { check(false, "Revocation fixture must first authenticate: \(error)"); continue }
            fixture.clearRequests()
            if !networkAvailable { fixture.fail("/auth/v1/logout", statuses: [URLError.notConnectedToInternet.rawValue]) }
            let defaults = isolatedDefaults()
            let journal = DiscoveryJournal(defaults: defaults)
            let store = SocialStore(journal: journal, defaults: defaults, photoDirectory: photoDirectory, configuration: configuration, api: service,
                                    appleCredentialIsAuthorized: { _ in false })
            await store.refresh()
            check(!store.isSignedIn && store.appleUserID == nil && (try? vault.load()) == nil,
                  "Definitive Apple revocation must remove local access even when hosted logout is offline")
            let logout = fixture.observed("/auth/v1/logout")
            check(logout.count == 1 && logout.first?.query == "scope=local",
                  "Definitive Apple revocation must attempt to end this hosted session")
            check(fixture.observed("/rest/v1/rpc/get_my_profile").isEmpty
                  && fixture.observed("/rest/v1/rpc/sync_explorations").isEmpty,
                  "A revoked Apple identity must be checked before fetching profile or uploading exploration")
        }

        fixture.reset(sharing: true)
        let vault = MemoryVault()
        let service = api(vault: vault)
        do { _ = try await service.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce) }
        catch { check(false, "Unavailable-state fixture must authenticate: \(error)"); return }
        fixture.clearRequests()
        let defaults = isolatedDefaults()
        let store = SocialStore(journal: DiscoveryJournal(defaults: defaults), defaults: defaults, photoDirectory: photoDirectory, configuration: configuration, api: service, appleCredentialIsAuthorized: { _ in nil })
        await store.refresh()
        let restoredID = await service.currentUserID()
        check(store.isSignedIn && restoredID == userA,
              "An unavailable Apple credential-state check must preserve a valid persisted account")
        check(fixture.observed("/auth/v1/logout").isEmpty && (try? vault.load()) != nil,
              "A network error checking Apple state must not revoke or erase the session")
        check(fixture.observed("/rest/v1/rpc/get_my_profile").count == 1,
              "A temporary Apple status failure must allow the independently valid hosted session to load")

        fixture.reset()
        let raceVault = MemoryVault()
        let raceService = api(vault: raceVault)
        do { _ = try await raceService.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce) }
        catch { check(false, "Revocation race fixture must authenticate: \(error)"); return }
        let appleID = await raceService.currentAppleUserID()!
        responseGate.arm("/auth/v1/logout")
        let olderRevocation = Task { try? await raceService.revokeAppleSession(userID: appleID) }
        guard await waitForHeldResponse() else {
            check(false, "Revocation race must hold its hosted logout response")
            responseGate.release(); olderRevocation.cancel(); return
        }
        check(await raceService.currentUserID() == nil && (try? raceVault.load()) == nil,
              "Definitive revocation must stop local authenticated requests while hosted logout is still pending")
        fixture.switchAccount(to: userB)
        do { _ = try await raceService.verifyCode(email: "other@example.test", code: "123456") }
        catch { check(false, "New account must sign in while older logout is pending: \(error)") }
        responseGate.release()
        check(await olderRevocation.value == false, "Late Apple revocation must not clear a newer account's session")
        check(await raceService.currentUserID() == userB,
              "A hosted logout response for A must preserve B's newer local identity")
        let persisted = (try? raceVault.load()).flatMap { $0 }.flatMap { try? JSONDecoder().decode(SocialSession.self, from: $0) }
        check(persisted?.user.id == userB, "Late Apple revocation must preserve the newer account's secure credentials")
    }

    func appleProfilePrivacy() async {
        fixture.reset(profile: false)
        let defaults = isolatedDefaults()
        let journal = DiscoveryJournal(defaults: defaults)
        let store = SocialStore(journal: journal, defaults: defaults, photoDirectory: photoDirectory, configuration: configuration,
                                api: api(vault: MemoryVault()))
        journal.visit(CountryRepository.country(id: "FR")!)
        await store.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce, name: "Mira Apple")
        check(store.isSignedIn && store.profile?.id == userA && store.profile?.displayName == "Mira Apple",
              "Initial Apple consent name should initialize the new profile without another form")
        check(store.profile?.shareExploration == true && !fixture.observed("/rest/v1/rpc/sync_explorations").isEmpty,
              "New Apple accounts use the disclosed sharing-on default")
        check(!journal.visitedIDs.contains("FR"), "Apple sign-in must not merge a guest journal into the online account")
        await store.signOut()
        check(journal.visitedIDs == ["FR"], "Signing out of Apple account must restore the private guest journal")

        fixture.reset(profile: true, sharing: true)
        let existingDefaults = isolatedDefaults()
        let existingJournal = DiscoveryJournal(defaults: existingDefaults)
        existingJournal.visit(CountryRepository.country(id: "FR")!)
        let existing = SocialStore(journal: existingJournal, defaults: existingDefaults, photoDirectory: photoDirectory, configuration: configuration,
                                   api: api(vault: MemoryVault()))
        await existing.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce, name: "Unwanted replacement")
        check(existing.isSignedIn && existing.profile?.displayName == "Mira",
              "Later Apple sign-in must preserve the existing chosen profile name")
        check(fixture.observed("/rest/v1/rpc/update_my_profile").isEmpty,
              "Apple full name must not overwrite an existing profile")
        check(fixture.observed("/rest/v1/rpc/sync_explorations").allSatisfy {
            !($0.json()["p_country_ids"] as? [String] ?? []).contains("FR")
        }, "Apple sign-in into a sharing account must not silently publish guest activity")

        fixture.reset()
        let deletionDefaults = isolatedDefaults()
        let deletionJournal = DiscoveryJournal(defaults: deletionDefaults)
        let deleting = SocialStore(journal: deletionJournal, defaults: deletionDefaults, photoDirectory: photoDirectory, configuration: configuration,
                                   api: api(vault: MemoryVault(savedSession())))
        await deleting.refresh()
        fixture.fail("/functions/v1/delete-account", statuses: [502])
        await deleting.deleteAccountAndData()
        fixture.clearRequests()
        fixture.switchAccount(to: userB)
        await deleting.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce, name: "Other account")
        check(deleting.deletionPending && deleting.profile?.id == userA,
              "Blocked Apple recovery must preserve the original pending deletion identity")
        check(fixture.observed("/auth/v1/token").isEmpty && deleting.errorMessage != nil,
              "Pending deletion must block Apple token exchange because it could recreate an already-deleted account")
        check(fixture.observed("/functions/v1/delete-account").isEmpty,
              "Apple recovery must never delete a different user's account")
    }

    func appleDeletionContract() async {
        fixture.reset()
        let vault = MemoryVault(savedSession())
        let service = api(vault: vault)
        fixture.fail("/functions/v1/delete-account", statuses: [409], code: "apple_reauthentication_required")
        do {
            try await service.deleteAccount()
            check(false, "Apple deletion challenge must not be treated as completed deletion")
        } catch {
            check((error as? SocialError)?.localizedDescription == SocialError.appleReauthenticationRequired.localizedDescription,
                  "Apple deletion challenge must request fresh native Apple authorization")
            check(await service.currentUserID() == userA && (try? vault.load()) != nil,
                  "Apple reauthentication requirement must preserve the session for deletion retry")
        }
        fixture.clearRequests()
        fixture.respond("/functions/v1/delete-account", json: #"{"deleted":true,"apple_revocation":"revoked"}"#)
        do {
            let result = try await service.deleteAccount(appleAuthorizationCode: "fixture-apple-one-time-code", appleNonce: appleNonce)
            check(result.deleted && result.appleRevocation == "revoked", "Confirmed deletion should preserve the server's Apple revocation result")
            let request = fixture.observed("/functions/v1/delete-account").first
            check(request?.json()["apple_authorization_code"] as? String == "fixture-apple-one-time-code"
                  && request?.json()["apple_nonce"] as? String == appleNonce,
                  "Deletion must send the fresh one-time authorization code and its raw nonce to the backend")
            check(request?.json()["apple_manual_revocation"] == nil,
                  "Native revocation path must not silently opt into manual revocation")
            check(await service.currentUserID() == nil && (try? vault.load()) == nil,
                  "Confirmed Apple deletion must remove all stored session credentials")
        } catch { check(false, "Fresh Apple authorization deletion fixture should succeed: \(error)") }

        fixture.reset()
        let defaults = isolatedDefaults()
        let journal = DiscoveryJournal(defaults: defaults)
        let store = SocialStore(journal: journal, defaults: defaults, photoDirectory: photoDirectory, configuration: configuration,
                                api: api(vault: MemoryVault(savedSession())))
        await store.refresh()
        fixture.respond("/functions/v1/delete-account", json: #"{"deleted":true,"apple_revocation":"manual_required"}"#)
        await store.deleteAccountAndData(appleManualRevocation: true)
        check(!store.isSignedIn && store.profile == nil && !store.deletionPending,
              "Confirmed manual-revocation deletion must still erase the app account and local data")
        check(store.appleRevocationNeedsManualAction, "Manual revocation requirement must remain visible after deletion")
        check(fixture.observed("/functions/v1/delete-account").last?.json()["apple_manual_revocation"] as? Bool == true,
              "Manual revocation fallback must be an explicit deletion request flag")
        let relaunched = SocialStore(journal: journal, defaults: defaults, photoDirectory: photoDirectory, configuration: nil)
        check(relaunched.appleRevocationNeedsManualAction, "Manual Apple revoke instructions must survive a relaunch")
        relaunched.dismissAppleRevocationNotice()
        check(!relaunched.appleRevocationNeedsManualAction && !defaults.bool(forKey: "niche.appleRevocationNeedsManualAction"),
              "Explicitly dismissing manual Apple instructions must clear their persisted notice")

        fixture.reset()
        let retryDefaults = isolatedDefaults()
        let retryJournal = DiscoveryJournal(defaults: retryDefaults)
        let retryStore = SocialStore(journal: retryJournal, defaults: retryDefaults, photoDirectory: photoDirectory, configuration: configuration,
                                     api: api(vault: MemoryVault(savedSession())))
        await retryStore.refresh()
        fixture.fail("/functions/v1/delete-account", statuses: [409], code: "apple_reauthentication_required")
        let challenge = await retryStore.deleteAccountAndData()
        check(challenge == .appleAuthorizationRequired && retryStore.deletionPending,
              "An explicit backend Apple challenge must distinguish authorization from an incomplete deletion")
        fixture.fail("/functions/v1/delete-account", statuses: [503])
        let unavailable = await retryStore.deleteAccountAndData()
        check(unavailable == .incomplete && retryStore.requiresAppleAuthorizationForDeletion,
              "A transient retry failure must not re-open Apple authorization merely because the account uses Apple")
        let completed = await retryStore.deleteAccountAndData(appleAuthorizationCode: "fixture-new-code", appleNonce: appleNonce)
        check(completed == .complete && !retryStore.deletionPending,
              "Confirmed retry with fresh Apple authorization must report completion")
    }

    func reportContract() async {
        fixture.reset()
        let service = api(vault: MemoryVault(savedSession()))
        let acceptedReasons: Set<String> = ["inappropriate_name", "inappropriate_photo", "harassment", "spam", "other"]
        check(Set(ProfileReportReason.allCases.map(\.rawValue)) == acceptedReasons,
              "Report choices must exactly cover the server's constrained reason codes")
        for reason in ProfileReportReason.allCases {
            do { try await service.report(friendA, reason: reason.rawValue) }
            catch { check(false, "Valid report reason must reach the service: \(reason.rawValue)") }
        }
        let reports = fixture.observed("/rest/v1/rpc/report_user")
        check(reports.count == acceptedReasons.count, "Each report choice must produce one report RPC")
        check(Set(reports.compactMap { $0.json()["p_reason"] as? String }) == acceptedReasons,
              "Report payloads must contain server reason codes, never display labels")
        check(reports.allSatisfy { UUID(uuidString: $0.json()["p_user_id"] as? String ?? "") == friendA },
              "Report payloads must identify the selected profile")
    }

    func sharingAndDeletion() async {
        fixture.reset()
        let defaults = isolatedDefaults()
        let culture = LiveCultureService(topics: [:], persistsHistory: true, historySuiteName: domains.last!)
        defaults.set(["Azonto"], forKey: "worldniche.culture.history.GH")
        defaults.set(userA.uuidString, forKey: "niche.localOwnerID")
        let journal = DiscoveryJournal(defaults: defaults)
        journal.visit(CountryRepository.country(id: "FR")!)
        journal.toggleSaved(CountryRepository.country(id: "CA")!)
        let vault = MemoryVault(savedSession())
        let service = api(vault: vault)
        let store = SocialStore(journal: journal, defaults: defaults, photoDirectory: photoDirectory, configuration: configuration, api: service, culture: culture)
        await store.refresh()
        await store.synchronizeExploration()
        check(fixture.observed("/rest/v1/rpc/sync_explorations").isEmpty, "Sharing off must prevent journal uploads during refresh and explicit sync")
        check(store.friendsWhoExplored("FR").map(\.id) == [friendA], "Private friend exploration must not appear in country social context")
        await store.saveProfile(name: "Mira", avatar: "leaf", sharing: true)
        let uploads = fixture.observed("/rest/v1/rpc/sync_explorations")
        check(uploads.count == 1 && uploads[0].json()["p_country_ids"] as? [String] == ["FR"], "Opting in must upload only explored country IDs")
        check(Set(journal.visitedIDs) == ["FR", "JP"], "Sync must merge valid remote countries and reject unknown IDs")
        check(!String(data: uploads.first?.body ?? Data(), encoding: .utf8)!.contains("CA"), "Sync must never upload private saved countries")
        fixture.clearRequests()
        fixture.fail("/functions/v1/delete-account", statuses: [502])
        await store.deleteAccountAndData()
        check(store.deletionPending && defaults.bool(forKey: "niche.deletionPending"), "Failed deletion must persist pending state")
        check(store.profile != nil && !journal.visitedIDs.isEmpty && journal.savedIDs.contains("CA"), "Failed deletion must keep local data for honest retry")
        check(defaults.stringArray(forKey: "worldniche.culture.history.GH") == ["Azonto"], "Unconfirmed deletion must preserve cultural history for retry")
        check((try? vault.load()) != nil && store.errorMessage != nil, "Failed deletion retains session and reports failure")
        fixture.clearRequests()
        await store.synchronizeExploration()
        await store.saveProfile(name: "Blocked change", avatar: "sun", sharing: true)
        _ = await store.createInvitation()
        await store.refresh()
        check(fixture.observed().isEmpty && store.profile?.displayName == "Mira", "Pending deletion pauses uploads, edits, invitations and ordinary refresh")
        let blockedExport = await store.exportData()
        check(blockedExport == nil && fixture.observed().isEmpty,
              "Pending deletion must block export without using or refreshing its preserved session")
        check(store.deletionPending && store.profile != nil && !journal.visitedIDs.isEmpty,
              "Blocked export must preserve pending deletion and local data")
        let relaunched = SocialStore(journal: journal, defaults: defaults, photoDirectory: photoDirectory, configuration: configuration, api: service, culture: culture)
        await relaunched.refresh()
        check(relaunched.deletionPending && fixture.observed().isEmpty, "Deletion safety state must survive store reconstruction without resync")
        await relaunched.deleteAccountAndData()
        check(!relaunched.deletionPending && !relaunched.isSignedIn && relaunched.profile == nil, "Confirmed remote deletion clears local account and pending state")
        check(journal.visitedIDs.isEmpty && journal.savedIDs.isEmpty && (try? vault.load()) == nil, "Confirmed deletion clears journal, saved countries and secure session")
        check(defaults.object(forKey: "worldniche.culture.history.GH") == nil, "Confirmed account deletion must erase local cultural reading history")
        check(fixture.observed("/functions/v1/delete-account").count == 1, "Deletion retry must actually contact delete endpoint")

        fixture.reset()
        let noAckDefaults = isolatedDefaults()
        let noAckJournal = DiscoveryJournal(defaults: noAckDefaults)
        let noAckStore = SocialStore(journal: noAckJournal, defaults: noAckDefaults, photoDirectory: photoDirectory, configuration: configuration, api: api(vault: MemoryVault(savedSession())))
        await noAckStore.refresh()
        fixture.acknowledgeDeletion(false)
        await noAckStore.deleteAccountAndData()
        check(noAckStore.deletionPending && noAckStore.profile != nil, "HTTP success without deletion acknowledgement must not erase local account")
    }

    func deletionAuthExpiry() async {
        fixture.reset()
        let defaults = isolatedDefaults()
        defaults.set(userA.uuidString, forKey: "niche.localOwnerID")
        let journal = DiscoveryJournal(defaults: defaults)
        journal.visit(CountryRepository.country(id: "FR")!)
        let store = SocialStore(journal: journal, defaults: defaults, photoDirectory: photoDirectory, configuration: configuration, api: api(vault: MemoryVault(savedSession())))
        await store.refresh()
        fixture.fail("/functions/v1/delete-account", statuses: [401])
        fixture.fail("/auth/v1/token", statuses: [401])
        await store.deleteAccountAndData()
        check(store.deletionPending && !store.isSignedIn, "Expired authorization during deletion must retain pending state and require reauthentication")
        await store.deleteAccountAndData()
        check(store.deletionPending && store.profile != nil && !journal.visitedIDs.isEmpty,
              "Retry without authentication must not silently turn cloud deletion into local erase")
    }

    func deletionConfirmationRetry() async {
        fixture.reset()
        // The first delete may have reached the server even though its response
        // was lost. A just-deleted account's refresh token no longer works, while
        // its still-valid JWT can prove identity to the idempotent delete endpoint.
        fixture.fail("/functions/v1/delete-account", statuses: [URLError.networkConnectionLost.rawValue])
        fixture.fail("/auth/v1/token", statuses: [401, 401])
        let vault = MemoryVault(savedSession(expiresIn: 30))
        let service = api(vault: vault)
        do {
            try await service.deleteAccount()
            check(false, "Lost deletion response must not be reported as confirmed success")
        } catch {
            check(await service.currentUserID() == userA && (try? vault.load()) != nil,
                  "Lost deletion response must retain the existing identity proof for confirmation retry")
        }
        check(fixture.observed("/auth/v1/token").isEmpty,
              "Deletion must not proactively refresh a still-valid token within the normal 60-second refresh window")
        check(fixture.observed("/functions/v1/delete-account").first?.authorization == "Bearer \(accessSecret)",
              "Deletion must use the exact preserved access token")
        do {
            try await service.deleteAccount()
            check(await service.currentUserID() == nil && (try? vault.load()) == nil,
                  "Confirmed deletion retry must finally clear secure and in-memory session")
        } catch { check(false, "Deletion confirmation retry must succeed using preserved JWT: \(error)") }
        let attempts = fixture.observed("/functions/v1/delete-account")
        check(attempts.count == 2 && attempts.allSatisfy { $0.authorization == "Bearer \(accessSecret)" },
              "Lost-response retry must reuse identity proof for the same account on both delete requests")
        check(fixture.observed("/auth/v1/token").isEmpty,
              "Deletion confirmation retry must never invalidate its proof by attempting token refresh")
    }

    func deletionIdentity() async {
        fixture.reset()
        let defaults = isolatedDefaults()
        let journal = DiscoveryJournal(defaults: defaults)
        let vault = MemoryVault(savedSession())
        let service = api(vault: vault)
        let store = SocialStore(journal: journal, defaults: defaults, photoDirectory: photoDirectory, configuration: configuration, api: service)
        await store.refresh()
        journal.visit(CountryRepository.country(id: "FR")!)
        fixture.fail("/functions/v1/delete-account", statuses: [502])
        await store.deleteAccountAndData()
        check(store.deletionPending, "Wrong-account deletion fixture must first establish failed deletion")
        fixture.clearRequests()
        fixture.switchAccount(to: userB)
        await store.requestCode(email: "other@example.test")
        await store.verifyCode(code: "123456")
        check(store.deletionPending && store.profile?.id == userA && journal.visitedIDs.contains("FR"),
              "Signing into a different account must not replace pending deletion's account or data")
        check(store.errorMessage != nil, "Wrong-account deletion recovery must explain the identity mismatch")
        await store.deleteAccountAndData()
        check(fixture.observed("/functions/v1/delete-account").isEmpty,
              "Deletion started for account A must never issue a delete request for account B")
        check(store.deletionPending, "Wrong-account recovery must retain the original deletion request")
    }

    func invitationLifecycle() async {
        fixture.reset()
        let defaults = isolatedDefaults()
        let store = SocialStore(journal: DiscoveryJournal(defaults: defaults), defaults: defaults, photoDirectory: photoDirectory, configuration: configuration,
                                api: api(vault: MemoryVault(savedSession())))
        let valid = configuration.invitationURL(token: inviteToken)!
        await store.openInvitation(valid)
        check(store.presentsInvitation && store.pendingInvitation == nil && fixture.observed().isEmpty,
              "Cold-launch link waits for authenticated restoration before reading or redeeming invitation")
        await store.refresh()
        check(store.invitationConnected && store.pendingInvitation?.displayName == "Jun", "Cold-launch invitation connects automatically after restoring account")
        check(fixture.observed("/rest/v1/rpc/accept_invite").count == 1, "Link tap automatically redeems one mutual friendship")
        let request = fixture.observed("/rest/v1/rpc/accept_invite").first
        check(request?.method == "POST" && request?.json()["p_token"] as? String == inviteToken && request?.authorization != nil,
              "Redemption requires authenticated POST with the validated invitation token")
        check(defaults.data(forKey: "niche.pendingInvitation.v1") == nil, "Confirmed friendship clears durable pending link")
        await store.openInvitation(valid)
        check(fixture.observed("/rest/v1/rpc/accept_invite").count == 1, "Duplicate delivery of completed link does not redeem twice")
        await store.openInvitation(URL(string: "https://evil.test/invite/\(inviteToken)")!)
        check(store.pendingInvitation == nil && !store.hasPendingInvitation && store.invitationMessage != nil,
              "Invalid new link clears old invitation state and shows an actionable message")
        await store.acceptInvitation()
        check(fixture.observed("/rest/v1/rpc/accept_invite").count == 1, "Invalid link cannot leave a previous token available for retry")
    }

    func invitationAuthenticationPersistence() async {
        for apple in [false, true] {
            fixture.reset(profile: false)
            let defaults = isolatedDefaults()
            let vault = MemoryVault()
            let service = api(vault: vault)
            let beforeRestart = SocialStore(journal: DiscoveryJournal(defaults: defaults), defaults: defaults, photoDirectory: photoDirectory, configuration: configuration, api: service)
            await beforeRestart.openInvitation(configuration.invitationURL(token: inviteToken)!)
            check(defaults.data(forKey: "niche.pendingInvitation.v1") != nil && fixture.observed().isEmpty,
                  "Signed-out invitation persists without exposing a profile or redeeming anonymously")
            let restored = SocialStore(journal: DiscoveryJournal(defaults: defaults), defaults: defaults, photoDirectory: photoDirectory, configuration: configuration, api: service)
            check(restored.hasPendingInvitation && restored.presentsInvitation, "Pending invitation survives process restart before sign-in")
            if apple {
                await restored.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce, name: "Apple Explorer",
                                               shareExplorationForNewAccount: false)
            } else {
                await restored.requestCode(email: "test@example.test")
                fixture.fail("/auth/v1/verify", statuses: [401])
                await restored.verifyCode(code: "123456", shareExplorationForNewAccount: false)
                check(restored.hasPendingInvitation && fixture.observed("/rest/v1/rpc/accept_invite").isEmpty,
                      "Rejected email code keeps invitation available without creating friendship")
                await restored.verifyCode(code: "123456", shareExplorationForNewAccount: false)
            }
            check(restored.invitationConnected && fixture.observed("/rest/v1/rpc/accept_invite").count == 1,
                  "\(apple ? "Apple" : "Email") sign-in automatically resumes invitation once")
            let paths = fixture.observed().map(\.path)
            check((paths.firstIndex(of: "/rest/v1/rpc/update_my_profile") ?? 999) < (paths.firstIndex(of: "/rest/v1/rpc/accept_invite") ?? 0),
                  "New account profile exists before redeeming the friend link")
            check(restored.profile?.shareExploration == false, "Connecting a friend preserves the explicitly off signup choice")
            let afterSuccess = SocialStore(journal: DiscoveryJournal(defaults: defaults), defaults: defaults, photoDirectory: photoDirectory, configuration: configuration, api: service)
            await afterSuccess.refresh()
            check(!afterSuccess.hasPendingInvitation && fixture.observed("/rest/v1/rpc/accept_invite").count == 1,
                  "Cold restart after confirmation cannot replay a completed invitation")
        }
    }

    func invitationFailuresAndReplay() async {
        fixture.reset()
        let defaults = isolatedDefaults()
        let store = SocialStore(journal: DiscoveryJournal(defaults: defaults), defaults: defaults, photoDirectory: photoDirectory, configuration: configuration,
                                api: api(vault: MemoryVault(savedSession())))
        await store.refresh()
        fixture.fail("/rest/v1/rpc/accept_invite", statuses: [URLError.networkConnectionLost.rawValue])
        await store.openInvitation(configuration.invitationURL(token: inviteToken)!)
        check(store.hasPendingInvitation && !store.invitationConnected && store.canRetryInvitation,
              "Lost redemption response retains durable retry instead of claiming success")
        await store.resumeInvitation()
        check(fixture.observed("/rest/v1/rpc/accept_invite").count == 1, "Transient failures do not cause an automatic request loop")
        fixture.respond("/rest/v1/rpc/accept_invite", json: "{\"status\":\"already_friends\",\"friend_id\":\"\(friendA.uuidString)\"}")
        fixture.fail("/rest/v1/rpc/list_friends", statuses: [URLError.notConnectedToInternet.rawValue])
        await store.acceptInvitation()
        check(store.invitationConnected && !store.hasPendingInvitation && store.invitationMessage == "You’re already friends.",
              "Idempotent replay confirms a lost success even if subsequent friend-list refresh fails")
        check(defaults.data(forKey: "niche.pendingInvitation.v1") == nil, "Friend-list failure must not retain a confirmed token")
        for status in ["self", "unavailable"] {
            store.dismissInvitation()
            fixture.clearRequests()
            fixture.respond("/rest/v1/rpc/preview_invite", json: "{\"status\":\"\(status)\"}")
            await store.openInvitation(configuration.invitationURL(token: inviteToken)!)
            check(!store.hasPendingInvitation && store.invitationMessage != nil && fixture.observed("/rest/v1/rpc/accept_invite").isEmpty,
                  "\(status) invitation ends gracefully without redemption or leaking block details")
        }
    }

    func invitationRecoveryAndExpiry() async {
        fixture.reset(profile: false)
        let defaults = isolatedDefaults()
        let service = api(vault: MemoryVault(savedSession()))
        let store = SocialStore(journal: DiscoveryJournal(defaults: defaults), defaults: defaults, photoDirectory: photoDirectory,
                                configuration: configuration, api: service)
        await store.openInvitation(configuration.invitationURL(token: inviteToken)!)
        fixture.fail("/rest/v1/rpc/update_my_profile", statuses: [URLError.notConnectedToInternet.rawValue])
        await store.refresh()
        check(store.hasPendingInvitation && store.invitationMessage != nil && store.profile == nil,
              "Offline profile setup leaves a retryable invitation instead of an endless spinner")
        await store.acceptInvitation()
        check(store.invitationConnected && fixture.observed("/rest/v1/rpc/accept_invite").count == 1,
              "Retry completes interrupted profile setup before automatically connecting")
        struct SavedLink: Encodable { let url: URL; let receivedAt: Date }
        for saved in [SavedLink(url: configuration.invitationURL(token: inviteToken)!, receivedAt: Date().addingTimeInterval(-8 * 86400)),
                      SavedLink(url: URL(string: "https://evil.test/invite/\(inviteToken)")!, receivedAt: Date())] {
            let otherDefaults = isolatedDefaults()
            otherDefaults.set(try! JSONEncoder().encode(saved), forKey: "niche.pendingInvitation.v1")
            let restored = SocialStore(journal: DiscoveryJournal(defaults: otherDefaults), defaults: otherDefaults, photoDirectory: photoDirectory, configuration: configuration, api: service)
            check(!restored.hasPendingInvitation && otherDefaults.data(forKey: "niche.pendingInvitation.v1") == nil,
                  "Restoration discards expired or untrusted persisted invitation URLs")
        }
    }

    func profileModeration() async {
        let approved = "\(userA.uuidString.lowercased())/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg"
        let oldPending = "\(userA.uuidString.lowercased())/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jpg"
        let jpeg = Data([0xff, 0xd8, 0x10, 0x20, 0xff, 0xd9])
        for lostResponse in [false, true] {
            fixture.reset()
            fixture.reviewPhotos(approved: approved, pending: oldPending, loseCommitResponse: lostResponse)
            let service = api(vault: MemoryVault(savedSession()))
            do {
                let updated = try await service.updateProfilePhoto(jpeg)
                check(updated.avatarPath == approved && updated.pendingAvatarPath != nil,
                      "Pending photo retains the prior approved photo, including a lost submission response")
                let uploads = fixture.observed().filter { $0.path.hasSuffix(".jpg") && $0.method == "POST" }
                check(uploads.last?.cacheControl == "max-age=0, no-store", "Uploads use valid HTTP cache directives")
                let deletions = fixture.observed("/storage/v1/object/profile-photos").filter { $0.method == "DELETE" }
                check(deletions.count == 1 && (deletions[0].json()["prefixes"] as? [String]) == [oldPending],
                      "Photo cleanup erases only the superseded pending image")
                check(updated.hasModerationNotice, "Pending content has a visible review notice")
                let cleared = try await service.updateProfilePhoto(nil)
                check(cleared.avatarPath == nil && cleared.pendingAvatarPath == nil,
                      "Choosing a symbol removes both pending and approved photo selections")
            } catch { check(false, "Photo moderation fixture failed: \(error)") }
        }
    }

    func profilePhotosAndPrivacy() async {
        fixture.reset()
        let defaults = isolatedDefaults()
        let service = api(vault: MemoryVault())
        let store = SocialStore(journal: DiscoveryJournal(defaults: defaults), defaults: defaults, photoDirectory: photoDirectory,
                                configuration: configuration, api: service)
        let jpeg = Data([0xff, 0xd8, 0x10, 0x20, 0xff, 0xd9])
        await store.saveProfile(name: "Guest", avatar: "sun", sharing: false, photoData: jpeg)
        let localID = store.profile?.localAvatarID
        check(localID.flatMap { AvatarPhotoFiles.load($0, directory: photoDirectory) } == jpeg,
              "Explicit guest photo save persists the selected bytes in isolated local storage")
        await store.saveProfile(name: "Guest renamed", avatar: "sun", sharing: false)
        check(store.profile?.localAvatarID == localID, "Editing a guest name preserves their selected photo")
        if let export = await store.exportData(), let data = try? Data(contentsOf: export),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            check(object["profile_photo_jpeg_base64"] as? String == jpeg.base64EncodedString(), "Data export includes the selected guest photo")
        } else { check(false, "Photo data export must succeed") }
        await store.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce, name: "Cloud")
        check(store.profile?.localAvatarID == nil && fixture.observed().allSatisfy { !$0.path.hasPrefix("/storage/") },
              "Signing in never silently uploads a guest photo or attaches it to another account")
        await store.signOut()
        check(store.profile?.localAvatarID == localID, "Signing out restores the guest workspace photo")
        await store.saveProfile(name: "Guest", avatar: "sun", sharing: false, removePhoto: true)
        check(store.profile?.localAvatarID == nil && localID.flatMap { AvatarPhotoFiles.load($0, directory: photoDirectory) } == nil,
              "Removing a guest photo deletes its local file")
        await store.saveProfile(name: "Guest", avatar: "sun", sharing: false, photoData: jpeg)
        let erasedID = store.profile?.localAvatarID
        await store.clearLocalData()
        check(erasedID.flatMap { AvatarPhotoFiles.load($0, directory: photoDirectory) } == nil,
              "Clear local data removes photos using only the injected test directory")

        fixture.reset()
        let signedDefaults = isolatedDefaults()
        let signed = SocialStore(journal: DiscoveryJournal(defaults: signedDefaults), defaults: signedDefaults, photoDirectory: photoDirectory,
                                 configuration: configuration, api: api(vault: MemoryVault(savedSession())))
        let path = "\(friendA.uuidString.lowercased())/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg"
        fixture.respond("/rest/v1/rpc/list_friends", json: "[{\"id\":\"\(friendA.uuidString)\",\"display_name\":\"Jun\",\"avatar\":\"wave\",\"avatar_path\":\"\(path)\",\"share_exploration\":false,\"country_ids\":[],\"explored_count\":0}]")
        await signed.refresh()
        fixture.clearRequests()
        let stranger = await signed.avatarData(path: "\(friendB.uuidString.lowercased())/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg")
        check(stranger == nil && fixture.observed().isEmpty, "Unrelated profile photo paths are denied before any network request")
        let route = "/storage/v1/object/authenticated/profile-photos/\(path)"
        fixture.respond(route, data: jpeg)
        fixture.fail(route, statuses: [503])
        let recovered = await signed.avatarData(path: path)
        check(recovered == jpeg && fixture.observed(route).count == 2,
              "A transient photo download failure retries once so an approved friend photo can appear")
        check(Set(fixture.observed(route).compactMap(\.query)).count == 2,
              "Photo retries must use new URLs to recheck current storage access")
        fixture.clearRequests()
        fixture.fail(route, statuses: [URLError.networkConnectionLost.rawValue])
        let connectionRecovered = await signed.avatarData(path: path)
        check(connectionRecovered == jpeg && fixture.observed(route).count == 2,
              "A lost network connection during photo download follows the same bounded recovery")
        fixture.clearRequests()
        fixture.fail(route, statuses: [503, 503, 503])
        let unavailable = await signed.avatarData(path: path)
        check(unavailable == nil && fixture.observed(route).count == 2,
              "Persistent photo outages have a bounded retry instead of an endless request loop")
        fixture.clearRequests()
        fixture.fail(route, statuses: [403])
        let denied = await signed.avatarData(path: path)
        check(denied == nil && fixture.observed(route).count == 1,
              "A forbidden photo never retries as a transient network failure")
        fixture.clearRequests()
        responseGate.arm(route)
        let photo = Task { await signed.avatarData(path: path) }
        guard await waitForHeldResponse() else { check(false, "Photo privacy race must hold download"); responseGate.release(); photo.cancel(); return }
        await signed.blockFriend(id: friendA)
        responseGate.release()
        let downloaded = await photo.value
        let reads = fixture.observed(route)
        check(reads.last?.query?.hasPrefix("cacheNonce=") == true,
              "Each photo read bypasses earlier CDN authorization results")
        check(downloaded == nil && !signed.friends.contains { $0.id == friendA }, "An in-flight photo is discarded if that friend is blocked before download completes")
    }

    func invitationRaces() async {
        fixture.reset()
        let defaults = isolatedDefaults()
        let store = SocialStore(journal: DiscoveryJournal(defaults: defaults), defaults: defaults, photoDirectory: photoDirectory, configuration: configuration,
                                api: api(vault: MemoryVault(savedSession())))
        await store.refresh()
        let valid = configuration.invitationURL(token: inviteToken)!
        responseGate.arm("/rest/v1/rpc/accept_invite")
        let first = Task { await store.openInvitation(valid) }
        guard await waitForHeldResponse() else { check(false, "Invite race must hold redemption response"); responseGate.release(); first.cancel(); return }
        await store.openInvitation(valid)
        await store.signOut()
        check(store.isSignedIn && fixture.observed("/rest/v1/rpc/accept_invite").count == 1,
              "Duplicate launch does not duplicate in-flight redemption and account cannot switch mid-accept")
        responseGate.release()
        await first.value
        check(store.invitationConnected, "One in-flight duplicate redemption completes normally")
        store.dismissInvitation()
        fixture.clearRequests()
        responseGate.arm("/rest/v1/rpc/preview_invite")
        let older = Task { await store.openInvitation(valid) }
        guard await waitForHeldResponse() else { check(false, "Invite replacement must hold preview"); responseGate.release(); older.cancel(); return }
        let newerToken = String(repeating: "9", count: 64)
        await store.openInvitation(configuration.invitationURL(token: newerToken)!)
        responseGate.release()
        await older.value
        check(fixture.observed("/rest/v1/rpc/accept_invite").map { $0.json()["p_token"] as? String } == [newerToken],
              "A newer link supersedes held preview and only its token is accepted")
        store.dismissInvitation()
        fixture.clearRequests()
        responseGate.arm("/rest/v1/rpc/accept_invite")
        let invalidated = Task { await store.openInvitation(valid) }
        guard await waitForHeldResponse() else { check(false, "Invite invalidation must hold accept"); responseGate.release(); invalidated.cancel(); return }
        await store.openInvitation(URL(string: "https://evil.test/invite/\(inviteToken)")!)
        responseGate.release()
        await invalidated.value
        check(!store.invitationConnected && !store.hasPendingInvitation && store.invitationMessage != nil,
              "Late redemption response cannot resurrect a dismissed or replaced invitation screen")
    }

    private func waitForHeldResponse() async -> Bool {
        for _ in 0..<500 {
            if responseGate.isHolding() { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return false
    }

    func authenticationRaces() async {
        fixture.reset()
        let vault = MemoryVault(savedSession(expiresIn: -1))
        let service = api(vault: vault)
        responseGate.arm("/auth/v1/token")
        let olderMutation = Task {
            do { _ = try await service.updateProfile(name: "Old account mutation", avatar: "leaf", sharing: true); return true }
            catch { return false }
        }
        guard await waitForHeldResponse() else {
            check(false, "Auth race fixture must intercept expired session refresh")
            responseGate.release(); olderMutation.cancel(); return
        }
        fixture.switchAccount(to: userB)
        do { _ = try await service.verifyCode(email: "other@example.test", code: "123456") }
        catch { check(false, "New account verification must succeed in race fixture: \(error)") }
        responseGate.release()
        check(!(await olderMutation.value), "Old account mutation must cancel when newer account signs in")
        check(await service.currentUserID() == userB, "Late refresh response for A must never overwrite newer B session")
        let persisted = (try? vault.load()).flatMap { $0 }.flatMap { try? JSONDecoder().decode(SocialSession.self, from: $0) }
        check(persisted?.user.id == userB, "Late refresh must not overwrite new account's secure vault")
        check(fixture.observed("/rest/v1/rpc/update_my_profile").isEmpty,
              "Old mutation awaiting token refresh must not replay using B's authorization")

        fixture.reset()
        fixture.fail("/rest/v1/rpc/update_my_profile", statuses: [401])
        let retryService = api(vault: MemoryVault(savedSession()))
        responseGate.arm("/rest/v1/rpc/update_my_profile")
        let rejectedOldMutation = Task {
            do { _ = try await retryService.updateProfile(name: "A pending write", avatar: "leaf", sharing: false); return true }
            catch { return false }
        }
        guard await waitForHeldResponse() else {
            check(false, "401 race fixture must intercept old mutation response")
            responseGate.release(); rejectedOldMutation.cancel(); return
        }
        fixture.switchAccount(to: userB)
        do { _ = try await retryService.verifyCode(email: "other@example.test", code: "123456") }
        catch { check(false, "Second new account verification must succeed: \(error)") }
        responseGate.release()
        check(!(await rejectedOldMutation.value), "Old account's late 401 must cancel instead of retrying under new account")
        check(await retryService.currentUserID() == userB, "Late old-account 401 must preserve new account session")
        check(fixture.observed("/rest/v1/rpc/update_my_profile").count == 1 && fixture.observed("/auth/v1/token").isEmpty,
              "Late 401 must neither refresh B nor repeat A's mutation")
    }

    func accountIsolation() async {
        fixture.reset(user: userB, sharing: true)
        let defaults = isolatedDefaults()
        let journal = DiscoveryJournal(defaults: defaults)
        journal.visit(CountryRepository.country(id: "FR")!)
        let priorProfile = ExplorerProfile(id: userA, displayName: "Old account", avatar: "leaf", shareExploration: true)
        defaults.set(try! JSONEncoder().encode(priorProfile), forKey: "niche.profile")
        let store = SocialStore(journal: journal, defaults: defaults, photoDirectory: photoDirectory, configuration: configuration, api: api(vault: MemoryVault(savedSession(user: userB))))
        await store.refresh()
        let uploads = fixture.observed("/rest/v1/rpc/sync_explorations")
        check(uploads.allSatisfy { !($0.json()["p_country_ids"] as? [String] ?? []).contains("FR") },
              "New account must never receive the prior account's local exploration history")
        check(store.profile?.id == userB, "Authenticated profile must belong to current account")

        fixture.reset(user: userB, profile: false)
        let emptyRemoteDefaults = isolatedDefaults()
        emptyRemoteDefaults.set(try! JSONEncoder().encode(priorProfile), forKey: "niche.profile")
        let emptyRemoteJournal = DiscoveryJournal(defaults: emptyRemoteDefaults)
        let emptyRemoteStore = SocialStore(journal: emptyRemoteJournal, defaults: emptyRemoteDefaults, photoDirectory: photoDirectory, configuration: configuration, api: api(vault: MemoryVault(savedSession(user: userB))))
        await emptyRemoteStore.refresh()
        check(emptyRemoteStore.profile?.id != userA, "Missing remote profile must not expose previous account's cached profile")

        fixture.reset(user: userB, sharing: true)
        let guestDefaults = isolatedDefaults()
        let guestJournal = DiscoveryJournal(defaults: guestDefaults)
        guestJournal.visit(CountryRepository.country(id: "FR")!)
        guestJournal.toggleSaved(CountryRepository.country(id: "CA")!)
        let guestStore = SocialStore(journal: guestJournal, defaults: guestDefaults, photoDirectory: photoDirectory, configuration: configuration,
                                     api: api(vault: MemoryVault(savedSession(user: userB))))
        await guestStore.refresh()
        check(fixture.observed("/rest/v1/rpc/sync_explorations").allSatisfy {
            !($0.json()["p_country_ids"] as? [String] ?? []).contains("FR")
        }, "Existing sharing account must not silently import the anonymous journal")
        check(!guestJournal.savedIDs.contains("CA"), "Guest saved countries must remain separate from signed-in account")
        await guestStore.signOut()
        check(guestJournal.visitedIDs == ["FR"] && guestJournal.savedIDs == ["CA"],
              "Signing out must restore the private guest journal without merging remote exploration")
        await guestStore.clearLocalData()
        check(!guestDefaults.dictionaryRepresentation().keys.contains(where: { $0.hasPrefix("niche.workspace.") }),
              "Explicit device data erasure must also remove inactive private workspace snapshots")
    }

    func profilePreviewAndChecks() async {
        let approvedPhoto = "\(userA.uuidString.lowercased())/55555555-5555-4555-8555-555555555555.jpg"
        let pendingPhoto = "\(userA.uuidString.lowercased())/66666666-6666-4666-8666-666666666666.jpg"
        var approved = ExplorerProfile(id: userA, displayName: "Mira", avatar: "globe", shareExploration: false,
                                       avatarPath: approvedPhoto, automaticProfileChecksEnabled: true,
                                       profileCheckConsentRecorded: true)
        var pending = approved
        pending.pendingDisplayName = "Mira Rose"; pending.nameModerationStatus = .pending; pending.nameCheckState = .queued
        pending.pendingAvatarPath = pendingPhoto; pending.photoModerationStatus = .pending; pending.photoCheckState = .queued
        check(pending.ownerDisplayName == "Mira Rose" && pending.ownerAvatarPath == pendingPhoto,
              "Owner immediately previews a saved pending name and photo")
        check(pending.displayName == "Mira" && pending.avatarPath == approvedPhoto,
              "Owner preview must never replace the approved friend-facing fields")
        var rejected = pending
        rejected.nameModerationStatus = .rejected; rejected.photoModerationStatus = .rejected
        check(rejected.ownerDisplayName == "Mira" && rejected.ownerAvatarPath == approvedPhoto,
              "Rejected content falls back to the approved owner profile")
        check(rejected.editableDisplayName == "Mira Rose" && rejected.editableAvatarPath == pendingPhoto,
              "Rejected edits remain available to correct in the editor")
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        func respond(_ path: String, _ profile: ExplorerProfile) { fixture.respond(path, data: try! encoder.encode(profile)) }

        fixture.reset()
        var manual = pending; manual.automaticProfileChecksEnabled = false
        manual.nameCheckState = .review; manual.photoCheckState = .review
        respond("/rest/v1/rpc/get_my_profile", manual)
        let defaults = isolatedDefaults()
        let service = api(vault: MemoryVault(savedSession()))
        let store = SocialStore(journal: DiscoveryJournal(defaults: defaults), defaults: defaults,
                                photoDirectory: photoDirectory, configuration: configuration, api: service)
        await store.refresh()
        await store.retryProfileCheck()
        check(fixture.observed("/functions/v1/moderate-profile").isEmpty,
              "Existing pending content without consent must never go to automatic checks")
        check(store.profile?.ownerDisplayName == "Mira Rose", "A manual review still preserves the owner's saved preview")
        respond("/rest/v1/rpc/set_profile_check_consent", pending)
        approved.displayName = "Mira Rose"; approved.avatarPath = pendingPhoto
        respond("/functions/v1/moderate-profile", approved)
        responseGate.arm("/functions/v1/moderate-profile")
        await store.setProfileCheckConsent(enabled: true)
        guard await waitForHeldResponse() else {
            check(false, "Explicit consent must resume the pending profile check")
            responseGate.release(); return
        }
        check(!store.isBusy && store.isCheckingProfile && store.profile?.ownerAvatarPath == pendingPhoto,
              "Automatic checks run separately from save and keep the owner preview visible")
        let request = fixture.observed("/functions/v1/moderate-profile").last
        check(request?.method == "POST" && request?.authorization == "Bearer \(accessSecret)" && request?.json().isEmpty == true,
              "Automatic checks use the authenticated current revision endpoint without resending client content")
        respond("/rest/v1/rpc/set_profile_check_consent", manual)
        await store.setProfileCheckConsent(enabled: false)
        responseGate.release()
        for _ in 0..<10 { await Task.yield() }
        check(store.profile?.automaticProfileChecksEnabled == false && store.profile?.displayName == "Mira",
              "A late check response after consent revocation must not publish or restore the prior consent")
        check(!store.isCheckingProfile && store.profile?.ownerDisplayName == "Mira Rose",
              "Revocation stops the in-flight check without losing the saved owner edit")

        fixture.clearRequests()
        var retry = pending; retry.nameCheckState = .retry; retry.photoCheckState = .retry
        respond("/rest/v1/rpc/set_profile_check_consent", retry)
        await store.setProfileCheckConsent(enabled: true)
        fixture.fail("/functions/v1/moderate-profile", statuses: [503])
        await store.retryProfileCheck()
        check(store.profileCheckFailed && !store.isCheckingProfile && store.profile?.ownerDisplayName == "Mira Rose",
              "A provider outage preserves saved edits and exposes a retry state")
        await store.retryProfileCheck()
        check(!store.profileCheckFailed && store.profile?.displayName == "Mira Rose" && store.profile?.pendingDisplayName == nil,
              "A successful retry atomically applies the approved server profile")

        fixture.clearRequests()
        var flagged = pending; flagged.nameCheckState = .review; flagged.photoCheckState = .review
        respond("/rest/v1/rpc/set_profile_check_consent", flagged)
        await store.setProfileCheckConsent(enabled: true)
        await store.retryProfileCheck()
        check(fixture.observed("/functions/v1/moderate-profile").isEmpty,
              "A flagged review cannot be repeatedly submitted as a transient failure retry")
        respond("/rest/v1/rpc/update_my_profile", manual)
        await store.saveProfile(name: "Mira Rose", avatar: "globe", sharing: false)
        check(store.profile?.ownerDisplayName == "Mira Rose" && store.profileSaveMessage == "Saved to your profile." && !store.isBusy,
              "Saving a pending edit confirms it immediately without waiting for manual review")
        check(fixture.observed("/functions/v1/moderate-profile").isEmpty,
              "Saving a profile without automatic-check consent does not contact the provider endpoint")
    }

    func profileSetupConsentRecovery() async {
        for automaticChecks in [false, true] {
            fixture.reset(profile: false)
            let defaults = isolatedDefaults()
            let store = SocialStore(journal: DiscoveryJournal(defaults: defaults), defaults: defaults,
                                    configuration: configuration, api: api(vault: MemoryVault()))
            fixture.fail("/rest/v1/rpc/update_my_profile", statuses: [503])
            await store.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce, name: "Initial Apple Name")
            check(store.isSignedIn && store.profile == nil && store.errorMessage != nil,
                  "Successful authentication with failed profile setup retains a retryable signed-in session")
            fixture.clearRequests()
            await store.saveProfile(name: "Chosen Retry Name", avatar: "leaf", sharing: false, automaticChecks: automaticChecks)
            let paths = fixture.observed().map(\.path)
            check((paths.firstIndex(of: "/rest/v1/rpc/update_my_profile") ?? 999)
                  < (paths.firstIndex(of: "/rest/v1/rpc/set_profile_check_consent") ?? 0),
                  "First editor retry must create the missing profile before recording consent=\(automaticChecks)")
            check(store.profile?.displayName == "Chosen Retry Name" && store.profile?.avatar == "leaf" && store.profile?.shareExploration == false,
                  "Profile setup retry preserves the editor's name, symbol and sharing choice")
            check(store.profile?.automaticProfileChecksEnabled == automaticChecks && store.profile?.profileCheckConsentRecorded == true,
                  "Both automatic and human review choices are saved after interrupted profile setup")
            check(store.errorMessage == nil && store.profileSaveMessage != nil && !store.isBusy,
                  "Successful editor recovery clears onboarding failure and confirms the save")
            check(defaults.dictionaryRepresentation().keys.allSatisfy {
                !$0.hasPrefix("niche.pendingAppleName.") && !$0.hasPrefix("niche.pendingProfileSharing.")
            }, "Explicit editor save removes old onboarding defaults so they cannot replace the new choices")
        }

        fixture.reset(profile: false)
        let defaults = isolatedDefaults()
        let store = SocialStore(journal: DiscoveryJournal(defaults: defaults), defaults: defaults,
                                configuration: configuration, api: api(vault: MemoryVault()))
        fixture.fail("/rest/v1/rpc/update_my_profile", statuses: [503])
        await store.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce, name: "Initial")
        fixture.fail("/rest/v1/rpc/set_profile_check_consent", statuses: [503])
        await store.saveProfile(name: "Saved Despite Outage", avatar: "sun", sharing: true, automaticChecks: false)
        check(store.profile?.displayName == "Saved Despite Outage" && store.profile?.shareExploration == true
              && store.errorMessage != nil && !store.isBusy,
              "Failed consent after initial profile save retains the saved data and exposes a retryable error")
        await store.saveProfile(name: "Saved Despite Outage", avatar: "sun", sharing: true, automaticChecks: false)
        check(store.errorMessage == nil && store.profile?.profileCheckConsentRecorded == true,
              "Retrying the editor completes consent after a transient consent failure")
        fixture.clearRequests()
        fixture.fail("/rest/v1/rpc/set_profile_check_consent", statuses: [503])
        await store.saveProfile(name: "Unsent Edit", avatar: "moon", sharing: false, automaticChecks: true)
        check(store.errorMessage != nil && fixture.observed("/rest/v1/rpc/update_my_profile").isEmpty,
              "Existing-profile consent failures stop the new edit before it is submitted under the wrong choice")
    }

    func visibleProfileRefresh() async {
        fixture.reset()
        let defaults = isolatedDefaults()
        let store = SocialStore(journal: DiscoveryJournal(defaults: defaults), defaults: defaults,
                                photoDirectory: photoDirectory, configuration: configuration,
                                api: api(vault: MemoryVault(savedSession())))
        await store.refresh()
        fixture.clearRequests()
        await store.refreshVisibleProfiles()
        check(fixture.observed().isEmpty, "Visible refresh is throttled after a full foreground refresh")
        let fresh = #"[{"id":"33333333-3333-4333-8333-333333333333","display_name":"Jun Updated","avatar":"leaf","share_exploration":false,"country_ids":[],"explored_count":0,"avatar_path":"33333333-3333-4333-8333-333333333333/77777777-7777-4777-8777-777777777777.jpg"}]"#
        fixture.respond("/rest/v1/rpc/list_friends", json: fresh)
        await store.refreshVisibleProfiles(force: true)
        check(store.friends.first?.displayName == "Jun Updated" && store.friends.first?.avatarPath != nil,
              "Visible friends refresh replaces approved names and immutable photo references")
        check(store.friends.count == 1 && store.friends.first?.countryIds == [],
              "Refresh removes inaccessible friends and revoked exploration access")
        check(fixture.observed("/rest/v1/rpc/sync_explorations").isEmpty && fixture.observed("/rest/v1/rpc/get_my_profile").isEmpty,
              "Visible friend refresh avoids journal uploads and unnecessary owner profile calls")
        responseGate.arm("/rest/v1/rpc/list_friends")
        let held = Task { await store.refreshVisibleProfiles(force: true) }
        guard await waitForHeldResponse() else { responseGate.release(); held.cancel(); check(false, "Refresh race fixture must hold response"); return }
        await store.signOut()
        responseGate.release(); await held.value
        check(!store.isSignedIn && store.friends.isEmpty,
              "Late friend refresh must not restore private friends after sign-out")
    }

    func independentProfileRefresh() async {
        fixture.reset()
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        let pending = ExplorerProfile(id: userA, displayName: "Mira", avatar: "globe", shareExploration: false,
                                      pendingDisplayName: "Mira Rose", nameModerationStatus: .pending,
                                      nameCheckState: .review, automaticProfileChecksEnabled: false)
        let approved = ExplorerProfile(id: userA, displayName: "Mira Rose", avatar: "globe", shareExploration: false)
        fixture.respond("/rest/v1/rpc/get_my_profile", data: try! encoder.encode(pending))
        let defaults = isolatedDefaults()
        let store = SocialStore(journal: DiscoveryJournal(defaults: defaults), defaults: defaults,
                                configuration: configuration, api: api(vault: MemoryVault(savedSession())))
        await store.refresh()
        fixture.respond("/rest/v1/rpc/get_my_profile", data: try! encoder.encode(approved))
        fixture.fail("/rest/v1/rpc/list_friends", statuses: [503])
        await store.refreshVisibleProfiles(force: true)
        check(store.profile?.displayName == "Mira Rose" && store.profile?.hasPendingContent == false,
              "Friend-list failure must not prevent the owner's approved update from appearing")
        check(store.friends.count == 2 && store.errorMessage == nil,
              "A transient friend-list failure retains the last visible friends without an error card")

        fixture.respond("/rest/v1/rpc/get_my_profile", data: try! encoder.encode(pending))
        await store.refresh()
        fixture.respond("/rest/v1/rpc/get_my_profile", data: try! encoder.encode(approved))
        responseGate.arm("/rest/v1/rpc/list_friends")
        let held = Task { await store.refreshVisibleProfiles(force: true) }
        guard await waitForHeldResponse() else {
            responseGate.release(); held.cancel(); check(false, "Independent refresh fixture must hold friends"); return
        }
        for _ in 0..<100 where store.profile?.hasPendingContent == true { try? await Task.sleep(for: .milliseconds(2)) }
        check(store.profile?.displayName == "Mira Rose" && store.profile?.hasPendingContent == false,
              "A slow friend response must not delay the owner's completed safety check")
        responseGate.release(); await held.value

        fixture.respond("/rest/v1/rpc/get_my_profile", data: try! encoder.encode(pending))
        await store.refresh()
        let fresh = #"[{"id":"33333333-3333-4333-8333-333333333333","display_name":"Jun Fresh","avatar":"leaf","share_exploration":false,"country_ids":[],"explored_count":0}]"#
        fixture.respond("/rest/v1/rpc/list_friends", json: fresh)
        responseGate.arm("/rest/v1/rpc/get_my_profile")
        let ownerHeld = Task { await store.refreshVisibleProfiles(force: true) }
        guard await waitForHeldResponse() else {
            responseGate.release(); ownerHeld.cancel(); check(false, "Independent refresh fixture must hold owner"); return
        }
        for _ in 0..<100 where store.friends.first?.displayName != "Jun Fresh" { try? await Task.sleep(for: .milliseconds(2)) }
        check(store.friends.first?.displayName == "Jun Fresh",
              "A slow owner response must not delay a friend's newly approved name")
        responseGate.release(); await ownerHeld.value

        fixture.fail("/rest/v1/rpc/get_my_profile", statuses: [503])
        fixture.respond("/rest/v1/rpc/list_friends", json: fresh.replacingOccurrences(of: "Jun Fresh", with: "Jun New"))
        await store.refreshVisibleProfiles(force: true)
        check(store.friends.first?.displayName == "Jun New" && store.profile?.ownerDisplayName == "Mira Rose"
              && store.profile?.hasPendingContent == true && store.errorMessage == nil,
              "Owner-refresh failure preserves its preview while a friend's new profile still appears")

        responseGate.arm("/rest/v1/rpc/get_my_profile")
        let staleOwner = Task { await store.refreshVisibleProfiles(force: true) }
        guard await waitForHeldResponse() else {
            responseGate.release(); staleOwner.cancel(); check(false, "Edit race fixture must hold owner refresh"); return
        }
        await store.saveProfile(name: "A Later Edit", avatar: "leaf", sharing: false)
        responseGate.release(); await staleOwner.value
        check(store.profile?.ownerDisplayName == "A Later Edit" && store.profile?.avatar == "leaf",
              "An old owner refresh cannot overwrite an edit saved while it was in flight")

        fixture.clearRequests()
        await store.refreshVisibleProfiles(now: Date().addingTimeInterval(5))
        check(fixture.observed("/rest/v1/rpc/list_friends").count == 1,
              "A visible social screen can refresh friends again after five seconds")
    }

    func appleNameRecoveryAndLinking() async {
        fixture.reset(profile: false)
        let defaults = isolatedDefaults()
        let journal = DiscoveryJournal(defaults: defaults)
        let vault = MemoryVault()
        let service = api(vault: vault)
        let store = SocialStore(journal: journal, defaults: defaults, photoDirectory: photoDirectory,
                                configuration: configuration, api: service)
        await store.saveProfile(name: "Explorer", avatar: "globe", sharing: false)
        fixture.fail("/rest/v1/rpc/update_my_profile", statuses: [503])
        await store.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce, name: "  Apple First Name  ")
        check(fixture.observed("/rest/v1/rpc/update_my_profile").first?.json()["p_display_name"] as? String == "Apple First Name",
              "Apple's first authorization name takes precedence over an Explorer placeholder")
        let relaunched = SocialStore(journal: journal, defaults: defaults, photoDirectory: photoDirectory,
                                     configuration: configuration, api: service)
        await relaunched.refresh()
        check(relaunched.profile?.displayName == "Apple First Name",
              "Apple's one-time name survives a failed profile save and app relaunch")
        check(defaults.dictionaryRepresentation().keys.allSatisfy { !$0.hasPrefix("niche.pendingAppleName.") },
              "Successful server save removes the temporary Apple name copy")

        fixture.reset(profile: false)
        let offlineDefaults = isolatedDefaults()
        let offlineAPI = api(vault: MemoryVault())
        let offlineStore = SocialStore(journal: DiscoveryJournal(defaults: offlineDefaults), defaults: offlineDefaults,
                                       configuration: configuration, api: offlineAPI)
        fixture.fail("/auth/v1/token", statuses: [503])
        await offlineStore.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce, name: "One Time Name",
                                          appleUserID: "apple-fixture-user-\(userA.uuidString)")
        check(!offlineStore.isSignedIn, "Failed initial Apple exchange must not fabricate an account")
        await offlineStore.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce, name: nil,
                                          appleUserID: "apple-fixture-user-\(userA.uuidString)")
        check(offlineStore.profile?.displayName == "One Time Name",
              "A later verified Apple login recovers the name from first authorization after a failed exchange")

        fixture.reset()
        await offlineStore.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce, name: "Different Apple Name")
        check(offlineStore.profile?.displayName == "Mira" && fixture.observed("/rest/v1/rpc/update_my_profile").isEmpty,
              "Apple authorization must never overwrite a meaningful existing profile name")

        fixture.reset()
        let linkVault = MemoryVault(savedSession())
        let linkService = api(vault: linkVault)
        do {
            try await linkService.linkAppleIdentity(identityToken: appleIdentityToken, nonce: appleNonce)
            let link = fixture.observed("/auth/v1/token").last
            check(link?.query == "grant_type=id_token" && link?.authorization == "Bearer \(accessSecret)"
                  && link?.json()["link_identity"] as? Bool == true,
                  "Native Apple linking explicitly authenticates the existing account and sets link_identity")
            let linkedApple = await linkService.hasAppleIdentity()
            check(await linkService.currentUserID() == userA && linkedApple,
                  "Linking preserves account identity and securely records Apple authorization")
        } catch { check(false, "Native Apple linking should succeed for current owner: \(error)") }

        fixture.reset(user: userB)
        let mismatchVault = MemoryVault(savedSession())
        let mismatch = api(vault: mismatchVault)
        do { try await mismatch.linkAppleIdentity(identityToken: appleIdentityToken, nonce: appleNonce); check(false, "Linking cannot switch the account") }
        catch { check(await mismatch.currentUserID() == userA, "A mismatched link response leaves the existing account signed in") }
        fixture.reset()
        let failure = api(vault: MemoryVault(savedSession()))
        fixture.fail("/auth/v1/token", statuses: [422], code: "identity_already_exists")
        do { try await failure.linkAppleIdentity(identityToken: appleIdentityToken, nonce: appleNonce); check(false, "Conflicting identity must reject linking") }
        catch { check(await failure.currentUserID() == userA, "An already-linked Apple identity must not merge or sign out the existing account") }

        fixture.reset()
        let racingLink = api(vault: MemoryVault(savedSession()))
        responseGate.arm("/auth/v1/token")
        let linkTask = Task {
            do { try await racingLink.linkAppleIdentity(identityToken: appleIdentityToken, nonce: appleNonce); return true }
            catch { return false }
        }
        guard await waitForHeldResponse() else { responseGate.release(); linkTask.cancel(); check(false, "Link fixture must hold response"); return }
        try? await racingLink.forgetSession()
        responseGate.release()
        check(!(await linkTask.value), "A native link response after sign-out must be cancelled")
        check(await racingLink.currentUserID() == nil, "Late linking must not restore a cleared secure session")

        fixture.reset()
        let recoveryDefaults = isolatedDefaults()
        let recovery = SocialStore(journal: DiscoveryJournal(defaults: recoveryDefaults), defaults: recoveryDefaults,
                                   configuration: configuration, api: api(vault: MemoryVault()))
        await recovery.requestCode(email: "existing@example.test", existingAccountOnly: true)
        check(fixture.observed("/auth/v1/otp").first?.json()["create_user"] as? Bool == false,
              "Email recovery cannot create new passwordless accounts")
    }

    func newAccountSharingChoices() async {
        for (hasExistingProfile, existingSharing, selectedSharing, expected) in [
            (false, false, true, true), (false, false, false, false),
            (true, false, true, false), (true, true, false, true)
        ] {
            fixture.reset(profile: hasExistingProfile, sharing: existingSharing)
            let defaults = isolatedDefaults()
            let journal = DiscoveryJournal(defaults: defaults)
            journal.visit(CountryRepository.country(id: "MA")!)
            let store = SocialStore(journal: journal, defaults: defaults, configuration: configuration,
                                    api: api(vault: MemoryVault()))
            await store.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce, name: "New Explorer",
                                        shareExplorationForNewAccount: selectedSharing)
            check(store.profile?.shareExploration == expected,
                  "Sharing respects new/explicit/existing choice: existing=\(hasExistingProfile), old=\(existingSharing), selected=\(selectedSharing)")
            let writes = fixture.observed("/rest/v1/rpc/update_my_profile")
            if hasExistingProfile {
                check(writes.isEmpty, "Sign-in never silently rewrites an existing sharing preference")
            } else {
                check(writes.last?.json()["p_share_exploration"] as? Bool == selectedSharing,
                      "New profile creation sends the choice shown before Apple authorization")
            }
            let uploads = fixture.observed("/rest/v1/rpc/sync_explorations")
            check(uploads.allSatisfy { !($0.json()["p_country_ids"] as? [String] ?? []).contains("MA") },
                  "New sharing defaults and later sign-ins must never upload prior guest exploration")
            if !expected { check(uploads.isEmpty, "Sharing off must prevent all exploration uploads") }
        }
        fixture.reset(profile: false)
        let defaults = isolatedDefaults()
        let service = api(vault: MemoryVault())
        let journal = DiscoveryJournal(defaults: defaults)
        let interrupted = SocialStore(journal: journal, defaults: defaults, configuration: configuration, api: service)
        fixture.fail("/rest/v1/rpc/update_my_profile", statuses: [503])
        await interrupted.signInWithApple(identityToken: appleIdentityToken, nonce: appleNonce, name: nil,
                                          shareExplorationForNewAccount: false)
        let restored = SocialStore(journal: journal, defaults: defaults, configuration: configuration, api: service)
        await restored.refresh()
        check(restored.profile?.shareExploration == false && fixture.observed("/rest/v1/rpc/sync_explorations").isEmpty,
              "An interrupted signup restores the explicitly off sharing choice even without an Apple name or invite")
    }

    func staleStoreRefresh() async {
        fixture.reset()
        let defaults = isolatedDefaults()
        let journal = DiscoveryJournal(defaults: defaults)
        let store = SocialStore(journal: journal, defaults: defaults, photoDirectory: photoDirectory, configuration: configuration,
                                api: api(vault: MemoryVault(savedSession())))
        await store.refresh()
        journal.visit(CountryRepository.country(id: "FR")!)
        fixture.fail("/rest/v1/rpc/get_my_profile", statuses: [500])
        responseGate.arm("/rest/v1/rpc/get_my_profile")
        let oldRefresh = Task { await store.refresh() }
        guard await waitForHeldResponse() else {
            check(false, "Store race fixture must hold old refresh response")
            responseGate.release(); oldRefresh.cancel(); return
        }
        fixture.switchAccount(to: userB)
        await store.requestCode(email: "other@example.test")
        await store.verifyCode(code: "123456")
        check(store.isSignedIn && store.profile?.id == userB, "New account must sign in while older profile refresh is pending")
        responseGate.release()
        await oldRefresh.value
        check(store.profile?.id == userB && !journal.visitedIDs.contains("FR"),
              "Late old-account refresh must not replace new profile or restore old journal")
        check(store.isSignedIn && store.errorMessage == nil, "Late old-account failure must not put new account into error state")
    }
}

@main struct SocialChecks {
    @MainActor static func main() async {
        let suite = CheckSuite()
        suite.links()
        await suite.localData()
        await suite.authentication()
        await suite.tokenRefresh()
        await suite.appleAuthentication()
        await suite.appleAuthenticationRaces()
        await suite.persistentRestoration()
        await suite.secureStorageRecovery()
        await suite.pendingDeletionPreservesAppleProof()
        await suite.appleCredentialRevocation()
        await suite.appleProfilePrivacy()
        await suite.appleDeletionContract()
        await suite.reportContract()
        await suite.sharingAndDeletion()
        await suite.deletionAuthExpiry()
        await suite.deletionConfirmationRetry()
        await suite.deletionIdentity()
        await suite.invitationLifecycle()
        await suite.invitationAuthenticationPersistence()
        await suite.invitationFailuresAndReplay()
        await suite.invitationRecoveryAndExpiry()
        await suite.profileModeration()
        await suite.profilePreviewAndChecks()
        await suite.profileSetupConsentRecovery()
        await suite.independentProfileRefresh()
        await suite.visibleProfileRefresh()
        await suite.appleNameRecoveryAndLinking()
        await suite.newAccountSharingChoices()
        await suite.profilePhotosAndPrivacy()
        await suite.invitationRaces()
        await suite.authenticationRaces()
        await suite.accountIsolation()
        await suite.staleStoreRefresh()
        suite.cleanup()
        if suite.failures.isEmpty {
            print("PASS: \(suite.assertions) social assertions; strict invitations, local profile/export/erase, vault-only sessions, email OTP, native Apple exchange, persistent session restoration, refresh recovery, sharing privacy, deletion failures/retry, and account isolation. No live network or Keychain access.")
        } else {
            print("FAIL: \(suite.failures.count) of \(suite.assertions) social assertions failed.")
            exit(1)
        }
    }
}

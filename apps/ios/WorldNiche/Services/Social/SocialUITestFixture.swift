#if DEBUG && targetEnvironment(simulator)
import Foundation
import UIKit

/// Simulator UI tests exercise the real store and views with isolated transport.
/// This file is excluded from device and release builds.
@MainActor
enum SocialUITestFixture {
    static func make() -> (journal: DiscoveryJournal, social: SocialStore)? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-worldniche-social-fixture"), arguments.indices.contains(index + 1),
              ["approval", "retry", "manual", "friend", "photo"].contains(arguments[index + 1]) else { return nil }
        let mode = arguments[index + 1]
        let suite = "io.worldniche.app.simulator-ui-fixture"
        guard let defaults = UserDefaults(suiteName: suite) else { return nil }
        defaults.removePersistentDomain(forName: suite)
        let journal = DiscoveryJournal(defaults: defaults)
        let configuration = SocialConfiguration(serviceURL: URL(string: "https://social-ui.example.test")!,
                                                publicAPIKey: "ui-fixture-public-key", invitationHost: "invite.example.test",
                                                privacyPolicyURL: nil, supportURL: nil)
        let transport = URLSessionConfiguration.ephemeral
        transport.protocolClasses = [SocialUIProtocol.self]
        transport.urlCache = nil
        SocialUIResponses.shared.reset(mode: mode)
        let api = SocialAPI(configuration: configuration, transport: URLSession(configuration: transport), vault: SocialUIVault())
        return (journal, SocialStore(journal: journal, defaults: defaults, configuration: configuration, api: api))
    }
}

private final class SocialUIVault: SocialSessionVault, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    init() {
        data = try? JSONEncoder().encode(SocialSession(accessToken: "ui-test-token-never-real", refreshToken: "ui-test-refresh-never-real",
                                                     expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970,
                                                     user: .init(id: SocialUIResponses.owner, email: "ui@example.test")))
    }
    func load() throws -> Data? { lock.lock(); defer { lock.unlock() }; return data }
    func save(_ data: Data) throws { lock.lock(); defer { lock.unlock() }; self.data = data }
    func clear() throws { lock.lock(); defer { lock.unlock() }; data = nil }
}

private final class SocialUIResponses: @unchecked Sendable {
    static let shared = SocialUIResponses()
    static let owner = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let lock = NSLock()
    private var mode = "approval"
    private var name = "Mira"
    private var pendingName: String?
    private var consent: Bool?
    private var checkCount = 0
    private var friendUpdateAt = Date.distantFuture
    private var retrying = false
    private var photoReadCount = 0
    private var photo = Data()
    private let photoPath = "33333333-3333-4333-8333-333333333333/77777777-7777-4777-8777-777777777777.jpg"

    func reset(mode: String) {
        lock.lock(); defer { lock.unlock() }
        self.mode = mode; name = "Mira"; pendingName = nil; consent = nil
        checkCount = 0; friendUpdateAt = Date().addingTimeInterval(15); retrying = false
        photoReadCount = 0
        photo = UIGraphicsImageRenderer(size: CGSize(width: 44, height: 44)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 44, height: 44))
        }.jpegData(compressionQuality: 0.9) ?? Data()
    }

    func response(_ request: URLRequest) -> (Int, Data, TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        guard request.url?.host == "social-ui.example.test",
              request.value(forHTTPHeaderField: "Authorization") == "Bearer ui-test-token-never-real" else {
            return (401, Data("{}".utf8), 0)
        }
        let body = Self.body(request)
        let value: Any
        var delay: TimeInterval = 0
        switch request.url?.path {
        case "/rest/v1/rpc/get_my_profile": value = profile()
        case "/rest/v1/rpc/list_friends":
            let updated = mode == "friend" && Date() >= friendUpdateAt
            var friend: [String: Any] = ["id": "33333333-3333-4333-8333-333333333333", "display_name": updated ? "Jun Updated" : "Jun",
                                         "avatar": updated ? "leaf" : "wave", "share_exploration": false, "country_ids": [], "explored_count": 0]
            if mode == "photo" { friend["avatar_path"] = photoPath }
            value = [friend]
        case "/storage/v1/object/authenticated/profile-photos/\(photoPath)":
            photoReadCount += 1
            return photoReadCount <= 2 ? (503, Data("{}".utf8), 0) : (200, photo, 0)
        case "/rest/v1/rpc/update_my_profile":
            if let submitted = body["p_display_name"] as? String, submitted != name { pendingName = submitted }
            value = profile()
        case "/rest/v1/rpc/set_profile_check_consent":
            consent = body["p_enabled"] as? Bool
            value = profile()
        case "/functions/v1/moderate-profile":
            guard consent == true else { return (403, Data("{}".utf8), 0) }
            checkCount += 1
            if mode == "retry", checkCount == 1 {
                retrying = true
                return (503, Data("{}".utf8), 1)
            }
            if let pendingName { name = pendingName }
            pendingName = nil; retrying = false
            value = profile()
            delay = 5
        case "/rest/v1/rpc/sync_explorations": value = ["country_ids": [], "count": 0] as [String: Any]
        default: return (404, Data("{}".utf8), 0)
        }
        return (200, (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8), delay)
    }

    private func profile() -> [String: Any] {
        var value: [String: Any] = ["id": Self.owner.uuidString, "display_name": name, "avatar": "globe",
                                    "share_exploration": false, "profile_check_consent_recorded": consent != nil,
                                    "automatic_profile_checks_enabled": consent == true]
        if let pendingName {
            value["pending_display_name"] = pendingName
            value["name_moderation_status"] = "pending"
            value["name_check_state"] = consent != true ? "review" : retrying ? "retry" : "queued"
        }
        return value
    }

    private static func body(_ request: URLRequest) -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 2048)
            while stream.hasBytesAvailable {
                let read = stream.read(&bytes, maxLength: bytes.count)
                guard read > 0 else { break }
                data.append(bytes, count: read)
            }
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

private final class SocialUIProtocol: URLProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data, delay) = SocialUIResponses.shared.response(request)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            lock.lock(); let cancelled = stopped; lock.unlock()
            guard !cancelled, let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                                 headerFields: ["Content-Type": "application/json"]) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { lock.lock(); defer { lock.unlock() }; stopped = true }
}
#endif

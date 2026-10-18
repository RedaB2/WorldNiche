import Foundation

// A deterministic transport harness. No network is used unless --live is passed.
struct CheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure(message) }
}

final class ScriptedTransport: @unchecked Sendable {
    struct Reply: Sendable {
        let status: Int
        let headers: [String: String]
        let data: Data
        let delayNanoseconds: UInt64
        init(status: Int = 200, headers: [String: String] = [:], data: Data, delayNanoseconds: UInt64 = 0) {
            self.status = status
            self.headers = headers
            self.data = data
            self.delayNanoseconds = delayNanoseconds
        }
    }

    private let lock = NSLock()
    private var replies: [Reply] = []
    private var requests: [URLRequest] = []
    private var stoppedCount = 0

    func reset(_ replies: [Reply]) {
        lock.lock(); defer { lock.unlock() }
        self.replies = replies
        requests = []
        stoppedCount = 0
    }

    func next(for request: URLRequest) -> Reply? {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        guard !replies.isEmpty else { return nil }
        return replies.removeFirst()
    }

    func didStop() {
        lock.lock(); defer { lock.unlock() }
        stoppedCount += 1
    }

    func snapshot() -> (requests: [URLRequest], stopped: Int) {
        lock.lock(); defer { lock.unlock() }
        return (requests, stoppedCount)
    }
}

final class MockCultureURLProtocol: URLProtocol, @unchecked Sendable {
    static let transport = ScriptedTransport()
    private let stateLock = NSLock()
    private var delivery: Task<Void, Never>?
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let reply = Self.transport.next(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let task = Task { @Sendable [self, reply] in
            if reply.delayNanoseconds > 0 {
                do { try await Task.sleep(nanoseconds: reply.delayNanoseconds) }
                catch { return }
            }
            guard !Task.isCancelled, !isStopped() else { return }
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.data)
            client?.urlProtocolDidFinishLoading(self)
        }
        stateLock.lock()
        delivery = task
        let alreadyStopped = stopped
        stateLock.unlock()
        if alreadyStopped { task.cancel() }
    }

    override func stopLoading() {
        stateLock.lock()
        stopped = true
        let task = delivery
        stateLock.unlock()
        task?.cancel()
        Self.transport.didStop()
    }

    private func isStopped() -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return stopped
    }
}

@main
struct LiveCultureChecks {
    static let country = Country(id: "GH", name: "Ghana", capital: "Accra", region: "Africa", latitude: 8, longitude: -2)
    static let topics = ["GH": ["Azonto"]]

    static func main() async {
        do {
            if CommandLine.arguments.contains("--probe") {
                try await liveDiscoveryProbe()
                return
            }
            if CommandLine.arguments.contains("--live") {
                try await liveSample()
                return
            }
            try await successfulDecodeAndLimit()
            try await rejectAmbiguousAndUnsafeSources()
            try await rateLimitBackoff()
            try await cacheAndForcedRefresh()
            try await cancellation()
            try await nonRepeatingHistory()
            try await attributedImages()
            try await redirectDeduplication()
            try await CultureDiscoveryChecks.run()
            print("PASS: all deterministic live-culture checks (no network)")
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockCultureURLProtocol.self]
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    static func summary(title: String = "Azonto", excerpt: String = "Azonto is a dance from Ghana.", type: String = "standard", source: String = "https://en.wikipedia.org/wiki/Azonto") throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "title": title,
            "extract": excerpt,
            "type": type,
            "timestamp": "2026-10-17T12:00:00Z",
            "content_urls": ["desktop": ["page": source]]
        ])
    }

    static func successfulDecodeAndLimit() async throws {
        let text = (1...130).map { "word\($0)" }.joined(separator: " ")
        MockCultureURLProtocol.transport.reset([.init(data: try summary(excerpt: text))])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let service = LiveCultureService(session: session, topics: topics)
        let result = await service.fetch(for: country)
        guard let reading = result.reading else { throw CheckFailure("A valid summary did not decode.") }
        try require(result.message == nil, "Success unexpectedly returned an error message.")
        try require(reading.title == "Azonto", "Summary title changed.")
        try require(reading.sourceURL.absoluteString == "https://en.wikipedia.org/wiki/Azonto", "Summary attribution URL changed.")
        try require(reading.revisionDate == "2026-10-17T12:00:00Z", "Revision timestamp was lost.")
        try require(reading.excerpt.split(separator: " ").count == 110, "Long summary was not bounded to 110 words.")
        try require(reading.excerpt.hasSuffix("word110…"), "Truncation did not preserve the correct last word and ellipsis.")
        try require(abs(reading.fetchedAt.timeIntervalSinceNow) < 5, "Fetch time was not recorded.")
        let captured = MockCultureURLProtocol.transport.snapshot().requests
        try require(captured.count == 1, "Success made more than one request.")
        try require(captured[0].url?.path == "/api/rest_v1/page/summary/Azonto", "Request did not use the reviewed topic.")
        try require(captured[0].value(forHTTPHeaderField: "Accept") == "application/json", "Request did not ask for JSON.")
        try require(captured[0].value(forHTTPHeaderField: "User-Agent")?.contains("WorldNiche") == true, "Request has no app identification.")
        print("PASS: summary decoding, attribution, revision date, request identity, and excerpt limit")
    }

    static func rejectAmbiguousAndUnsafeSources() async throws {
        let cases: [(String, Data)] = [
            ("disambiguation", try summary(type: "disambiguation")),
            ("non-HTTPS source", try summary(source: "http://en.wikipedia.org/wiki/Azonto")),
            ("javascript source", try summary(source: "javascript:alert(1)")),
            ("untrusted host", try summary(source: "https://example.com/wiki/Azonto")),
            ("empty extract", try summary(excerpt: "")),
            ("malformed JSON", Data("not JSON".utf8))
        ]
        for (name, data) in cases {
            MockCultureURLProtocol.transport.reset([.init(data: data)])
            let session = makeSession()
            let service = LiveCultureService(session: session, topics: topics)
            let result = await service.fetch(for: country)
            try require(result.reading == nil, "Accepted \(name).")
            try require(result.message?.contains("couldn’t refresh") == true, "\(name) had no useful fallback message.")
            session.invalidateAndCancel()
        }
        print("PASS: disambiguation, unsafe URL schemes/host, empty content, and malformed JSON rejected")
    }

    static func rateLimitBackoff() async throws {
        MockCultureURLProtocol.transport.reset([
            .init(status: 429, headers: ["Retry-After": "0"], data: Data()),
            .init(data: try summary(title: "Should not be requested"))
        ])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let service = LiveCultureService(session: session, topics: ["GH": ["Azonto", "Kpanlogo"]])
        let initial = await service.fetch(for: country)
        try require(initial.reading == nil && initial.message?.contains("limiting requests") == true, "HTTP 429 was not explained.")
        // Even a zero Retry-After must have a minimum backoff; it also applies to other topics and forced refresh.
        let second = await service.fetch(for: country, rotation: 1, forceRefresh: true)
        try require(second.reading == nil && second.message?.contains("limiting requests") == true, "Backoff did not apply across topics.")
        try require(MockCultureURLProtocol.transport.snapshot().requests.count == 1, "Backoff allowed another transport request.")
        print("PASS: HTTP 429 minimum backoff suppresses forced and cross-topic requests")
    }

    static func cacheAndForcedRefresh() async throws {
        MockCultureURLProtocol.transport.reset([
            .init(data: try summary(excerpt: "First revision.")),
            .init(data: try summary(excerpt: "New revision.")),
            .init(status: 503, data: Data())
        ])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let service = LiveCultureService(session: session, topics: topics)
        let original = await service.fetch(for: country)
        let cached = await service.fetch(for: country)
        try require(original.reading?.excerpt == "First revision." && cached.reading?.excerpt == "First revision.", "Fresh cache did not preserve its reading.")
        try require(cached.reading?.fetchedAt == original.reading?.fetchedAt, "A cache hit rewrote the fetch date.")
        try require(MockCultureURLProtocol.transport.snapshot().requests.count == 1, "A fresh cache hit performed a network request.")
        let refreshed = await service.fetch(for: country, forceRefresh: true)
        try require(refreshed.reading?.excerpt == "New revision.", "Forced refresh did not replace cached content.")
        let requests = MockCultureURLProtocol.transport.snapshot().requests
        try require(requests.count == 2 && requests[1].cachePolicy == .reloadIgnoringLocalCacheData, "Forced refresh did not bypass the URL cache.")
        let failedRefresh = await service.fetch(for: country, forceRefresh: true)
        try require(failedRefresh.reading?.excerpt == "New revision." && failedRefresh.message != nil, "A server failure did not preserve the last reading.")
        print("PASS: fresh cache, forced refresh, URL-cache bypass, and stale-content fallback")
    }

    static func nonRepeatingHistory() async throws {
        MockCultureURLProtocol.transport.reset([
            .init(data: try summary(title: "Azonto", excerpt: "First discovery.")),
            .init(data: try summary(title: "Kpanlogo", excerpt: "Second discovery.")),
            .init(data: try summary(title: "Highlife", excerpt: "Third discovery."))
        ])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let suite = "WorldNiche.CultureChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let index = ["GH": ["Azonto", "Kpanlogo", "Highlife"]]
        let service = LiveCultureService(session: session, topics: index, persistsHistory: true, historySuiteName: suite)
        let firstSession = UUID(), nextSession = UUID()
        let first = await service.fetch(for: country, discoverySessionID: firstSession)
        let repeated = await service.fetch(for: country, discoverySessionID: firstSession)
        let second = await service.fetch(for: country, rotation: 1, discoverySessionID: firstSession)
        let reopened = await service.fetch(for: country, discoverySessionID: nextSession)
        try require(reopened.reading?.title == "Kpanlogo", "Reopening the country reset to an old discovery.")
        let third = await service.fetch(for: country, rotation: 1, discoverySessionID: nextSession)
        let exhausted = await service.fetch(for: country, rotation: 2, discoverySessionID: nextSession)
        try require(first.reading?.title == "Azonto" && repeated.reading?.title == "Azonto", "Stable selection did not reuse its reading.")
        try require(second.reading?.title == "Kpanlogo" && third.reading?.title == "Highlife", "Another discovery repeated an already read topic.")
        try require(exhausted.reading?.title == "Highlife" && exhausted.message?.contains("end of") == true, "Exhaustion silently wrapped instead of retaining the last reading honestly.")
        try require(MockCultureURLProtocol.transport.snapshot().requests.count == 3, "A consumed pool generated repeat network requests.")
        let relaunched = LiveCultureService(session: session, topics: index, persistsHistory: true, historySuiteName: suite)
        let afterRestart = await relaunched.fetch(for: country)
        try require(afterRestart.reading == nil && afterRestart.message?.contains("end of") == true, "Persistent history was lost across service instances.")
        print("PASS: stable selection, view-reopen nonrepeat, honest exhaustion, and persistent history")
    }

    static func redirectDeduplication() async throws {
        MockCultureURLProtocol.transport.reset([
            .init(data: try summary(title: "Azonto")), .init(data: try summary(title: "Azonto")),
            .init(data: try summary(title: "Kpanlogo", excerpt: "Kpanlogo is a Ghanaian dance."))
        ])
        let session = makeSession(); defer { session.invalidateAndCancel() }
        let service = LiveCultureService(session: session, topics: ["GH": ["Azonto", "Azonto dance", "Kpanlogo"]])
        _ = await service.fetch(for: country)
        let next = await service.fetch(for: country, rotation: 1)
        try require(next.reading?.title == "Kpanlogo", "A redirect alias resurfaced an already-read article.")
        print("PASS: redirected aliases do not repeat an already-read canonical topic")
    }

    static func attributedImages() async throws {
        var article = try JSONSerialization.jsonObject(with: summary()) as! [String: Any]
        article["originalimage"] = ["source": "https://upload.wikimedia.org/wikipedia/commons/a/ab/Azonto.jpg"]
        let image: [String: Any] = ["query": ["pages": [["imageinfo": [[
            "url": "https://upload.wikimedia.org/wikipedia/commons/a/ab/Azonto.jpg",
            "thumburl": "https://thumb.wikimedia.org/wikipedia/commons/thumb/a/ab/Azonto.jpg/1200px-Azonto.jpg",
            "descriptionurl": "https://commons.wikimedia.org/wiki/File:Azonto.jpg",
            "extmetadata": ["Artist": ["value": "<a>Example photographer</a>"], "LicenseShortName": ["value": "CC BY-SA 4.0"], "LicenseUrl": ["value": "https://creativecommons.org/licenses/by-sa/4.0/"]]
        ]]]]]]
        MockCultureURLProtocol.transport.reset([.init(data: try JSONSerialization.data(withJSONObject: article)), .init(data: try JSONSerialization.data(withJSONObject: image))])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let reading = await LiveCultureService(session: session, topics: topics).fetch(for: country).reading
        try require(reading?.image?.attribution == "Example photographer" && reading?.image?.license == "CC BY-SA 4.0", "Licensed article image lost its attribution.")
        try require(reading?.image?.sourceURL.host == "commons.wikimedia.org", "Image source was not the original file page.")
        article["originalimage"] = ["source": "https://upload.wikimedia.org/wikipedia/en/a/ab/Nonfree.jpg"]
        MockCultureURLProtocol.transport.reset([.init(data: try JSONSerialization.data(withJSONObject: article))])
        let nonfree = await LiveCultureService(session: session, topics: topics).fetch(for: country)
        try require(nonfree.reading?.image == nil && MockCultureURLProtocol.transport.snapshot().requests.count == 1, "A nonfree local-Wikipedia image was accepted.")
        print("PASS: Commons image metadata, author/license attribution, and nonfree-image rejection")
    }

    static func cancellation() async throws {
        MockCultureURLProtocol.transport.reset([
            .init(data: try summary(excerpt: "Cancelled result."), delayNanoseconds: 30_000_000_000),
            .init(data: try summary(excerpt: "After cancellation."))
        ])
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let service = LiveCultureService(session: session, topics: topics)
        let task = Task { await service.fetch(for: country) }
        try await waitUntil("The cancellable request did not start.") {
            MockCultureURLProtocol.transport.snapshot().requests.count == 1
        }
        task.cancel()
        let result = await task.value
        try require(result.reading == nil && result.message == nil, "Cancellation became content or a user-facing error.")
        try await waitUntil("Cancellation did not stop URLSession transport.") {
            MockCultureURLProtocol.transport.snapshot().stopped > 0
        }
        let later = await service.fetch(for: country)
        try require(later.reading?.excerpt == "After cancellation.", "Cancellation populated the cache or poisoned a later fetch.")
        try require(MockCultureURLProtocol.transport.snapshot().requests.count == 2, "Later fetch unexpectedly used the cancelled result.")
        print("PASS: in-flight cancellation stops transport, stays silent, and never fills cache")
    }

    static func waitUntil(_ failure: String, condition: @Sendable () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw CheckFailure(failure)
    }

    static func liveDiscoveryProbe() async throws {
        let ids = CommandLine.arguments.drop(while: { $0 != "--probe" }).dropFirst()
        let service = LiveCultureService(allowsGeneration: false)
        for id in ids {
            guard let country = CountryRepository.country(id: id) else { continue }
            var titles = Set<String>()
            for rotation in 0..<(CommandLine.arguments.contains("--deep") ? 8 : 3) {
                let result = await service.fetch(for: country, rotation: rotation)
                let row: [String: Any] = ["country": country.name, "rotation": rotation,
                    "title": result.reading?.title ?? "", "excerpt": result.reading?.excerpt ?? "",
                    "source": result.reading?.sourceURL.absoluteString ?? "", "image": result.reading?.image?.url.absoluteString ?? "",
                    "message": result.message ?? ""]
                let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
                FileHandle.standardOutput.write(data + Data("\n".utf8))
                if let reading = result.reading, result.message == nil {
                    try require(titles.insert(reading.title).inserted, "Live probe repeated a topic without an exhaustion message.")
                }
                try await Task.sleep(for: .seconds(1))
            }
        }
    }

    static func liveSample() async throws {
        // Exactly one public request, using a topic verified by the editorial-source review.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = LiveCultureService(session: session, topics: ["GH": ["Azonto"]])
        let result = await service.fetch(for: country, forceRefresh: true)
        guard let reading = result.reading else {
            throw CheckFailure("Live URLSession request did not produce a reading: \(result.message ?? "no diagnostic")")
        }
        try require(reading.title == "Azonto", "Live response resolved to an unexpected topic.")
        try require(!reading.excerpt.isEmpty && reading.sourceURL.host == "en.wikipedia.org", "Live response lacked attributed content.")
        print("PASS: native URLSession fetched \(reading.title) from \(reading.sourceURL.absoluteString)")
        print("Revision: \(reading.revisionDate ?? "not supplied"); excerpt: \(reading.excerpt.split(separator: " ").count) words")
    }
}

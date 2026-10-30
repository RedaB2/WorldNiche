import Foundation

private final class MockState: @unchecked Sendable {
    let lock = NSLock()
    private var mode = "success"
    private var count = 0
    private var musicCount = 0
    private var musicURLs: [URL] = []
    private var newsURLs: [URL] = []
    func configure(_ value: String) { lock.lock(); defer { lock.unlock() }; mode = value; count = 0; musicCount = 0; musicURLs = []; newsURLs = [] }
    func record(isMusic: Bool, url: URL) -> (mode: String, musicAttempt: Int) {
        lock.lock(); defer { lock.unlock() }
        count += 1
        if isMusic { musicCount += 1; musicURLs.append(url) } else { newsURLs.append(url) }
        return (mode, musicCount)
    }
    func requestCount() -> Int { lock.lock(); defer { lock.unlock() }; return count }
    func musicRequestCount() -> Int { lock.lock(); defer { lock.unlock() }; return musicCount }
    func requestedNewsURLs() -> [URL] { lock.lock(); defer { lock.unlock() }; return newsURLs }
    func requestedMusicURLs() -> [URL] { lock.lock(); defer { lock.unlock() }; return musicURLs }
}
private func rssDate(daysAgo: Int = 0) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter.string(from: Date().addingTimeInterval(-Double(daysAgo) * 86400))
}
private let currentRSSDate = rssDate()
private let multilingualHeadline = "한국의 음악 · ثقافة المغرب · café · 日本 🎵 & <local>"
private let forbiddenXMLScalars = (Array(0...31).filter { ![9, 10, 13].contains($0) } + [0xFFFE, 0xFFFF])
    .compactMap { Unicode.Scalar($0) }
private let forbiddenXMLText = String(String.UnicodeScalarView(forbiddenXMLScalars))
private let mockState = MockState()
private final class MockProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let isMusic = request.url!.host == "rss.marketingtools.apple.com"
        let (mode, musicAttempt) = mockState.record(isMusic: isMusic, url: request.url!)
        if isMusic && mode == "transientTimeout" && musicAttempt <= 2 {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        if isMusic && ["cancelledRequest", "offline"].contains(mode) {
            client?.urlProtocol(self, didFailWithError: URLError(mode == "offline" ? .notConnectedToInternet : .cancelled))
            return
        }
        let transient502 = isMusic && ((mode == "transient502" && musicAttempt <= 2)
            || (mode == "fallback25" && musicAttempt == 1))
        let failedMusic = isMusic && mode == "musicServerError"
        let failedNews = !isMusic && mode == "newsServerError"
        let status = mode == "unavailable" ? 404 : (mode == "badRequest" ? 400 :
            (mode == "serverError" ? 500 : (transient502 || failedMusic || failedNews ? 502 : 200)))
        let music = #"{"feed":{"results":[{"id":"one","name":"A song","artistName":"An artist","artworkUrl100":"https://example.org/art.png","url":"https://music.apple.com/track"},{"id":"bad","name":"Unsafe link","artistName":"Artist","url":"javascript:bad"}]}}"#
        let rss = #"<?xml version="1.0"?><rss xmlns:dc="http://purl.org/dc/elements/1.1/"><channel><item><title><![CDATA[Fish & Chips]]></title><link>https://globalvoices.org/story</link><dc:creator>Sample Author</dc:creator><pubDate>Sat, 17 Oct 2026 09:12:00 GMT</pubDate></item><item><title>Duplicate</title><link>https://globalvoices.org/story</link><dc:creator>Sample Author</dc:creator></item><item><title>Untrusted URL</title><link>javascript:alert(1)</link></item></channel></rss>"#.replacingOccurrences(of: "Sat, 17 Oct 2026 09:12:00 GMT", with: currentRSSDate)
        let chart: String
        if mode == "fallback25" {
            let songs = (1...25).map { ["id": String($0), "name": "Song \($0)",
                                      "artistName": "Artist", "url": "https://music.apple.com/track/\($0)"] }
            chart = String(data: try! JSONSerialization.data(withJSONObject: ["feed": ["results": songs]]), encoding: .utf8)!
        } else { chart = music }
        var news = rss
        if mode == "badControl" { news = rss.replacingOccurrences(of: "</item>", with: "<description><![CDATA[Body \u{0008} text]]></description></item>") }
        if ["allControls", "unicodeTitle", "controlsInTitle"].contains(mode) {
            let title = multilingualHeadline + (mode == "controlsInTitle" ? forbiddenXMLText : "")
            news = rss.replacingOccurrences(of: "Fish & Chips", with: title)
            news = news.replacingOccurrences(of: "</item>", with: "<description><![CDATA[Body \(forbiddenXMLText) text]]></description></item>")
        }
        if mode == "truncatedRSS" { news = String(rss.dropLast("</channel></rss>".count)) }
        if mode == "unescapedEntity" { news = rss.replacingOccurrences(of: "<![CDATA[Fish & Chips]]>", with: "Fish & Chips") }
        if mode == "badNumericEntity" { news = rss.replacingOccurrences(of: "<![CDATA[Fish & Chips]]>", with: "Fish &#x8; Chips") }
        if mode == "missingAuthor" { news = rss.replacingOccurrences(of: "<dc:creator>Sample Author</dc:creator>", with: "") }
        if mode == "foreignPublisher" { news = rss.replacingOccurrences(of: "https://globalvoices.org/story", with: "https://example.org/story") }
        if mode == "oldNews" { news = rss.replacingOccurrences(of: currentRSSDate, with: rssDate(daysAgo: 400)) }
        if mode == "futureNews" { news = rss.replacingOccurrences(of: currentRSSDate, with: rssDate(daysAgo: -5)) }
        let payload = mode == "malformed" ? "<html>Not a feed</html>" : (isMusic ? chart : news)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: mode == "invalidUTF8" ? Data(payload.utf8) + Data([0xFF]) : Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
// Hold the first response until a newer request or invalidation has completed.
// This makes the stale-write race deterministic without depending on wall-clock delays.
private final class RaceState: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var first: RaceProtocol?
    func reset() { lock.lock(); defer { lock.unlock() }; count = 0; first = nil }
    func begin(_ request: RaceProtocol) -> Int {
        lock.lock(); defer { lock.unlock() }
        count += 1
        if count == 1 { first = request }
        return count
    }
    func requestCount() -> Int { lock.lock(); defer { lock.unlock() }; return count }
    func releaseFirst() {
        lock.lock()
        let request = first
        first = nil
        lock.unlock()
        request?.deliver(version: 1)
    }
}
private let raceState = RaceState()
private final class RaceProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let version = raceState.begin(self)
        if version > 1 { deliver(version: version) }
    }
    func deliver(version: Int) {
        let identity = "version-\(version)"
        let music = "{\"feed\":{\"results\":[{\"id\":\"\(identity)\",\"name\":\"Song\",\"artistName\":\"Artist\",\"url\":\"https://music.apple.com/track/\(version)\"}]}}"
        let news = "<rss xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><channel><item><title>\(identity)</title><link>https://globalvoices.org/\(identity)</link><dc:creator>Test Author</dc:creator><pubDate>\(currentRSSDate)</pubDate></item></channel></rss>"
        let body = request.url!.host == "rss.marketingtools.apple.com" ? music : news
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct Checks {
    static func main() async {
        precondition(CountryRepository.countries.count == 195)
        precondition(Set(CountryRepository.countries.map(\.id)).count == 195)
        precondition(CountryRepository.country(id: "fr")?.flag == "🇫🇷")
        precondition(CountryRepository.country(id: "PS") != nil)
        precondition(CountryRepository.country(id: "VA") != nil)
        precondition(CountryRepository.countries.allSatisfy { (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) })
        precondition(!CountryRepository.country(id: "FR")!.insights.isEmpty)
        precondition(CountryRepository.countries.allSatisfy { !$0.insights.isEmpty }, "Every country needs a sourced discovery card")
        let topicURL = Bundle.main.url(forResource: "culture-topics", withExtension: "json")!
        let topics = try! JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: topicURL))
        precondition(Set(topics.keys) == Set(CountryRepository.countries.map(\.id)))
        precondition(topics.values.allSatisfy { !$0.isEmpty && $0.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty } })
        precondition(CountryRepository.countries.flatMap(\.insights).allSatisfy { $0.sourceURL.scheme == "https" })
        struct Directory: Decodable { let storefronts: [String] }
        let directoryURL = Bundle.main.url(forResource: "apple-music-storefronts", withExtension: "json")!
        let directory = try! JSONDecoder().decode(Directory.self, from: Data(contentsOf: directoryURL))
        let storefronts = Set(directory.storefronts)
        precondition(storefronts.count == 172 && storefronts.contains("US") && storefronts.contains("FR"))
        precondition(CountryRepository.countries.filter { storefronts.contains($0.id) }.count == 162)
        for _ in 0..<100 { precondition(CountryRepository.random(excluding: "fr").id != "FR") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProtocol.self]
        let session = URLSession(configuration: configuration)
        let country = CountryRepository.country(id: "FR")!
        let service = DiscoveryFeedService(session: session)
        mockState.configure("success")
        let feed = await service.fetch(for: country)
        precondition(feed.tracks.count == 1)
        precondition(feed.stories.count == 1)
        precondition(feed.stories[0].title == "Fish & Chips")
        precondition(feed.stories[0].publishedAt != nil)
        precondition(feed.stories[0].author == "Sample Author")
        precondition(feed.stories[0].source == "Global Voices")
        precondition(feed.musicUnavailable == nil && feed.newsUnavailable == nil)
        _ = await service.fetch(for: country)
        precondition(mockState.requestCount() == 2, "Cache should reuse the two successful requests")
        await service.invalidate(countryID: "fr")
        _ = await service.fetch(for: country)
        precondition(mockState.requestCount() == 4)
        mockState.configure("success")
        let unlisted = await DiscoveryFeedService(session: session).fetch(for: CountryRepository.country(id: "AF")!)
        precondition(unlisted.tracks.isEmpty && unlisted.stories.count == 1)
        precondition(unlisted.musicUnavailable?.contains("directory") == true)
        precondition(mockState.requestCount() == 1, "Unlisted storefronts must still load news, without a doomed chart request")
        mockState.configure("serverError")
        let serverError = await DiscoveryFeedService(session: session).fetch(for: country)
        precondition(serverError.musicUnavailable?.contains("responding") == true,
                     "A server error must not be reported as an unsupported storefront")
        mockState.configure("unavailable")
        let failing = DiscoveryFeedService(session: session)
        let failed = await failing.fetch(for: country)
        precondition(failed.tracks.isEmpty && failed.stories.isEmpty)
        precondition(failed.musicUnavailable != nil && failed.newsUnavailable != nil)
        _ = await failing.fetch(for: country)
        precondition(mockState.requestCount() == 3, "Failed news should retry while a permanent missing chart stays cached")
        mockState.configure("malformed")
        let malformed = await DiscoveryFeedService(session: session).fetch(for: country)
        precondition(malformed.tracks.isEmpty && malformed.stories.isEmpty)
        precondition(malformed.musicUnavailable != nil && malformed.newsUnavailable != nil)
        mockState.configure("success")
        let cancelledService = DiscoveryFeedService(session: session)
        let task = Task { () -> CountryFeed in
            withUnsafeCurrentTask { $0?.cancel() }
            return await cancelledService.fetch(for: country)
        }
        let cancelled = await task.value
        precondition(cancelled.tracks.isEmpty && cancelled.stories.isEmpty)
        precondition(mockState.requestCount() == 0)
        mockState.configure("badControl")
        let repaired = await DiscoveryFeedService(session: session).fetchNews(for: country)
        precondition(repaired.items.count == 1, "Invalid body controls must not hide valid headlines")
        for mode in ["missingAuthor", "foreignPublisher", "oldNews", "futureNews"] {
            mockState.configure(mode)
            let filtered = await DiscoveryFeedService(session: session).fetchNews(for: country)
            precondition(filtered.items.isEmpty && filtered.unavailable != nil, "Reject \(mode)")
        }
        for code in ["AD", "FM"] {
            mockState.configure("success")
            let absent = await DiscoveryFeedService(session: session).fetchNews(for: CountryRepository.country(id: code)!)
            precondition(absent.items.isEmpty && absent.unavailable?.contains("does not list") == true)
            precondition(mockState.requestCount() == 0, "Do not substitute a different country's reporting")
        }
        await checkGlobalParserRepair(session: session)
        print("PASS: licensed publisher, bylines, control-character repair, stale/future filtering and unsupported countries.")
        await checkMusicRecovery(country: country, session: session)
        await checkIndependentFeeds(country: country, session: session)
        await checkConcurrentCacheWrites(country: country)
        print("PASS: catalog coverage/coordinates/flags, storefront coverage and skipped requests, random exclusion, JSON/RSS parsing, CDATA, duplicate and invalid-URL filtering, dates, cache/invalidation, HTTP errors, malformed feeds, cancellation.")
        if CommandLine.arguments.contains("--live") {
            let live = await DiscoveryFeedService().fetch(for: country)
            precondition(!live.tracks.isEmpty, live.musicUnavailable ?? "No tracks")
            precondition(!live.stories.isEmpty, live.newsUnavailable ?? "No stories")
            print("PASS: live France Apple Music \(live.tracks.count) tracks and Global Voices \(live.stories.count) stories.")
            print("Track: \(live.tracks[0].title) by \(live.tracks[0].artist)")
            let korea = await DiscoveryFeedService().fetchNews(for: CountryRepository.country(id: "KR")!)
            precondition(!korea.items.isEmpty, korea.unavailable ?? "Korea feed must load")
            print("PASS: live South Korea \(korea.items.count) stories despite upstream invalid body control.")
            print("Story source: \(live.stories[0].source); date parsed: \(live.stories[0].publishedAt != nil)")
        }
        if CommandLine.arguments.contains("--live-coverage") { await checkLiveCountryCoverage() }
    }
    private static func checkGlobalParserRepair(session: URLSession) async {
        struct NewsDirectory: Decodable { let feeds: [String: URL] }
        let path = Bundle.main.url(forResource: "global-voices-feeds", withExtension: "json")!
        let feeds = try! JSONDecoder().decode(NewsDirectory.self, from: Data(contentsOf: path)).feeds
        precondition(feeds.count == 193)
        for (code, expectedURL) in feeds.sorted(by: { $0.key < $1.key }) {
            mockState.configure("allControls")
            let result = await DiscoveryFeedService(session: session).fetchNews(for: CountryRepository.country(id: code)!)
            precondition(result.items.count == 1 && result.unavailable == nil, "Repair must work for \(code)")
            precondition(result.items[0].title == multilingualHeadline, "Valid Unicode changed for \(code)")
            precondition(mockState.requestedNewsURLs() == [expectedURL], "Wrong country feed for \(code)")
        }
        let country = CountryRepository.country(id: "MA")!
        mockState.configure("controlsInTitle")
        let repaired = await DiscoveryFeedService(session: session).fetchNews(for: country)
        precondition(repaired.items.first?.title == multilingualHeadline + String(repeating: "\u{FFFD}", count: forbiddenXMLScalars.count))
        for mode in ["truncatedRSS", "unescapedEntity", "badNumericEntity", "invalidUTF8"] {
            mockState.configure(mode)
            let service = DiscoveryFeedService(session: session)
            let broken = await service.fetchNews(for: country)
            precondition(broken.items.isEmpty && broken.unavailable != nil, "Reject \(mode), including partial items")
            mockState.configure("success")
            let recovered = await service.fetchNews(for: country)
            precondition(recovered.items.count == 1 && mockState.requestCount() == 1, "Do not cache malformed \(mode)")
        }
        print("PASS: all 193 country routes repair all 31 forbidden XML scalars, preserve multilingual Unicode, reject broken XML/UTF-8 and recover without a poisoned cache.")
    }
    private static func checkLiveCountryCoverage() async {
        let service = DiscoveryFeedService()
        for code in ["MA", "FR", "US", "JP", "GE", "CG", "CD", "DM", "BR", "IN", "SN", "NZ", "VA", "KE", "KR", "GB"] {
            let started = Date()
            let result = await service.fetchNews(for: CountryRepository.country(id: code)!)
            precondition(!result.items.isEmpty || result.unavailable?.contains("no recent stories") == true,
                         "Live feed failed for \(code): \(result.unavailable ?? "unknown")")
            precondition(result.items.allSatisfy {
                $0.author?.isEmpty == false && $0.publishedAt != nil && $0.url.host == "globalvoices.org"
            })
            print("PASS: live \(code), \(result.items.count) attributed stories, \(String(format: "%.2f", Date().timeIntervalSince(started))) seconds")
        }
    }
    private static func checkMusicRecovery(country: Country, session: URLSession) async {
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message); print("FAIL: \(message)") }
        }
        for mode in ["transient502", "transientTimeout"] {
            mockState.configure(mode)
            let service = DiscoveryFeedService(session: session)
            let recovered = await service.fetch(for: country)
            check(recovered.tracks.count == 1 && recovered.musicUnavailable == nil,
                  "\(mode) must recover inside the first fetch without manual refresh")
            check(mockState.musicRequestCount() == 3, "\(mode) must make exactly three bounded attempts")
            let urls = mockState.requestedMusicURLs()
            check(urls.map(\.path) == ["/api/v2/fr/music/most-played/10/songs.json",
                                      "/api/v2/fr/music/most-played/25/songs.json",
                                      "/api/v2/fr/music/most-played/25/songs.json"],
                  "All transient retries must preserve the country and chart category")
            check(urls.allSatisfy { $0.host == "rss.marketingtools.apple.com" },
                  "Retries must remain on the Apple chart provider")
            _ = await service.fetch(for: country)
            check(mockState.musicRequestCount() == 3, "Recovered charts must use the success cache")
        }
        mockState.configure("fallback25")
        let nicaragua = CountryRepository.country(id: "NI")!
        let fallback = await DiscoveryFeedService(session: session).fetchMusic(for: nicaragua)
        check(fallback.items.map(\.id) == (1...10).map(String.init),
              "A recovered 25-song chart must display only the first 10 tracks in rank order")
        check(mockState.requestCount() == 2 && mockState.musicRequestCount() == 2,
              "Fallback music requests must not load news")
        check(mockState.requestedMusicURLs().map(\.path) == ["/api/v2/ni/music/most-played/10/songs.json",
                                                             "/api/v2/ni/music/most-played/25/songs.json"],
              "A fallback must never substitute another country's chart")

        mockState.configure("musicServerError")
        let partialService = DiscoveryFeedService(session: session)
        let partial = await partialService.fetch(for: country)
        check(partial.tracks.isEmpty && partial.stories.count == 1, "Failed music must preserve successful news")
        check(mockState.musicRequestCount() == 3, "Persistent 502 must stop after three attempts")
        mockState.configure("success")
        let reopened = await partialService.fetch(for: country)
        check(reopened.tracks.count == 1 && mockState.musicRequestCount() == 1,
              "Successful news must not cache failed music for 15 minutes")

        for mode in ["unavailable", "badRequest", "malformed", "cancelledRequest", "offline"] {
            mockState.configure(mode)
            let failed = await DiscoveryFeedService(session: session).fetch(for: country)
            check(failed.tracks.isEmpty, "\(mode) must remain unavailable")
            check(mockState.musicRequestCount() == 1, "\(mode) must not be retried")
        }

        // Cancel after the first transient failure, during automatic backoff.
        mockState.configure("musicServerError")
        let cancelService = DiscoveryFeedService(session: session)
        let pending = Task { await cancelService.fetch(for: country) }
        for _ in 0..<100 where mockState.musicRequestCount() == 0 {
            try? await Task.sleep(for: .milliseconds(1))
        }
        pending.cancel()
        let cancelled = await pending.value
        check(cancelled.tracks.isEmpty && mockState.musicRequestCount() == 1,
              "Cancellation during retry backoff must stop further chart requests")
        mockState.configure("success")
        let afterCancellation = await cancelService.fetch(for: country)
        check(afterCancellation.tracks.count == 1 && mockState.musicRequestCount() == 1,
              "Cancellation must not cache the partial result")
        if !failures.isEmpty { print("FAIL: \(failures.count) music recovery regressions"); exit(1) }
        print("PASS: first-fetch HTTP502/timeout recovery, retry cap, partial cache recovery, permanent error exclusions, and cancellation during backoff.")
    }

    private static func checkIndependentFeeds(country: Country, session: URLSession) async {
        mockState.configure("success")
        let service = DiscoveryFeedService(session: session)
        let music = await service.fetchMusic(for: country)
        precondition(music.items.count == 1 && music.unavailable == nil)
        precondition(mockState.requestCount() == 1 && mockState.musicRequestCount() == 1,
                     "Loading music must not request news")
        let news = await service.fetchNews(for: country)
        precondition(news.items.count == 1 && news.unavailable == nil)
        let combined = await service.fetch(for: country)
        precondition(combined.musicFetchedAt == music.fetchedAt && combined.newsFetchedAt == news.fetchedAt,
                     "Cached companion context must preserve each category's source retrieval time")
        precondition(mockState.requestCount() == 2 && mockState.musicRequestCount() == 1)
        let updatedMusic = await service.fetchMusic(for: country, forceRefresh: true)
        precondition(updatedMusic.items.count == 1)
        precondition(mockState.requestCount() == 3 && mockState.musicRequestCount() == 2,
                     "Refreshing music must not request news")
        let cachedNews = await service.fetchNews(for: country)
        let mixedAgeContext = await service.fetch(for: country)
        precondition(mixedAgeContext.musicFetchedAt == updatedMusic.fetchedAt && mixedAgeContext.newsFetchedAt == news.fetchedAt,
                     "Refreshing music must not make cached headlines appear freshly retrieved to the companion")
        precondition(cachedNews.fetchedAt == news.fetchedAt && mockState.requestCount() == 3,
                     "Refreshing music must preserve the news cache and retrieval time")
        _ = await service.fetchNews(for: country, forceRefresh: true)
        precondition(mockState.requestCount() == 4 && mockState.musicRequestCount() == 2,
                     "Refreshing news must not request music")
        let cachedMusic = await service.fetchMusic(for: country)
        precondition(cachedMusic.fetchedAt == updatedMusic.fetchedAt && mockState.requestCount() == 4,
                     "Refreshing news must preserve the music cache and retrieval time")

        mockState.configure("musicServerError")
        let isolated = DiscoveryFeedService(session: session)
        let partial = await isolated.fetch(for: country)
        precondition(partial.tracks.isEmpty && partial.stories.count == 1)
        mockState.configure("success")
        let recovered = await isolated.fetch(for: country)
        precondition(recovered.tracks.count == 1 && recovered.stories.count == 1)
        precondition(mockState.requestCount() == 1 && mockState.musicRequestCount() == 1,
                     "Recovering failed music must reuse successful news without another news request")
        mockState.configure("newsServerError")
        let isolatedNews = DiscoveryFeedService(session: session)
        let newsFailure = await isolatedNews.fetch(for: country)
        precondition(newsFailure.tracks.count == 1 && newsFailure.stories.isEmpty)
        mockState.configure("success")
        let recoveredNews = await isolatedNews.fetch(for: country)
        precondition(recoveredNews.tracks.count == 1 && recoveredNews.stories.count == 1)
        precondition(mockState.requestCount() == 1 && mockState.musicRequestCount() == 0,
                     "Recovering failed news must reuse successful music without another chart request")
        print("PASS: independent music/news loading, force refresh, retrieval dates, caches, and partial failure recovery.")
    }

    private static func checkConcurrentCacheWrites(country: Country) async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RaceProtocol.self]
        let session = URLSession(configuration: configuration)
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message); print("FAIL: \(message)") }
        }
        func waitForFirstRequest() async {
            for _ in 0..<1_000 where raceState.requestCount() == 0 {
                try? await Task.sleep(for: .milliseconds(1))
            }
            precondition(raceState.requestCount() == 1, "The older request must be held before starting the newer request")
        }
        @Sendable func load(_ service: DiscoveryFeedService, music: Bool, force: Bool = false) async -> String? {
            if music { return await service.fetchMusic(for: country, forceRefresh: force).items.first?.id }
            return await service.fetchNews(for: country, forceRefresh: force).items.first?.title
        }
        for music in [true, false] {
            let category = music ? "music" : "news"
            raceState.reset()
            let service = DiscoveryFeedService(session: session)
            let older = Task { await load(service, music: music) }
            await waitForFirstRequest()
            let newer = await load(service, music: music, force: true)
            check(newer == "version-2", "The newer \(category) refresh must complete first")
            raceState.releaseFirst()
            _ = await older.value
            let cached = await load(service, music: music)
            check(cached == "version-2" && raceState.requestCount() == 2,
                  "An older \(category) response must not overwrite the newer cache")

            raceState.reset()
            let invalidated = DiscoveryFeedService(session: session)
            let pending = Task { await load(invalidated, music: music) }
            await waitForFirstRequest()
            await invalidated.invalidate(countryID: country.id.lowercased())
            raceState.releaseFirst()
            _ = await pending.value
            let fresh = await load(invalidated, music: music)
            check(fresh == "version-2" && raceState.requestCount() == 2,
                  "Invalidation during a \(category) request must prevent that response from repopulating cache")
        }
        if !failures.isEmpty { print("FAIL: \(failures.count) stale cache regressions"); exit(1) }
        print("PASS: out-of-order music/news refresh completion and invalidation during in-flight requests.")
    }

}

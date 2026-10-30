import Foundation

/// Public, key-free feeds. A storefront chart is not a national listening survey;
/// Global Voices supplies attributed reporting, not a ranking of local stories.
actor DiscoveryFeedService {
    private let session: URLSession
    private let cacheLifetime: TimeInterval = 15 * 60
    private var musicCache: [String: FeedSnapshot<MusicTrack>] = [:]
    private var newsCache: [String: FeedSnapshot<NewsStory>] = [:]
    private var musicRequests: [String: UUID] = [:]
    private var newsRequests: [String: UUID] = [:]

    private static let newsFeeds: [String: URL] = {
        struct Directory: Decodable { let feeds: [String: URL] }
        guard let url = Bundle.main.url(forResource: "global-voices-feeds", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let directory = try? JSONDecoder().decode(Directory.self, from: data) else { return [:] }
        return directory.feeds.filter { $0.value.scheme == "https" && $0.value.host == "globalvoices.org" }
    }()

    // Apple's public chart builder lists 172 storefronts (162 of our 195 countries).
    // A missing resource falls back to a request rather than inventing unavailability.
    private static let listedStorefronts: Set<String>? = {
        struct Directory: Decodable { let storefronts: [String] }
        guard let url = Bundle.main.url(forResource: "apple-music-storefronts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let directory = try? JSONDecoder().decode(Directory.self, from: data),
              !directory.storefronts.isEmpty else { return nil }
        return Set(directory.storefronts)
    }()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchMusic(for country: Country, forceRefresh: Bool = false) async -> FeedSnapshot<MusicTrack> {
        if forceRefresh { musicCache.removeValue(forKey: country.id) }
        if let cached = musicCache[country.id], Date().timeIntervalSince(cached.fetchedAt) < cacheLifetime {
            return cached
        }
        let requestID = UUID()
        musicRequests[country.id] = requestID
        let result = await Self.loadMusic(for: country, session: session)
        let snapshot = FeedSnapshot(items: result.items, fetchedAt: Date(), unavailable: result.message)
        // Actor methods can overlap across awaits. Only the latest request may cache.
        if !Task.isCancelled && result.canCache && musicRequests[country.id] == requestID {
            musicCache[country.id] = snapshot
        }
        return snapshot
    }

    func fetchNews(for country: Country, forceRefresh: Bool = false) async -> FeedSnapshot<NewsStory> {
        if forceRefresh { newsCache.removeValue(forKey: country.id) }
        if let cached = newsCache[country.id], Date().timeIntervalSince(cached.fetchedAt) < cacheLifetime {
            return cached
        }
        let requestID = UUID()
        newsRequests[country.id] = requestID
        let result = await Self.loadNews(for: country, session: session)
        let snapshot = FeedSnapshot(items: result.items, fetchedAt: Date(), unavailable: result.message)
        if !Task.isCancelled && result.canCache && newsRequests[country.id] == requestID {
            newsCache[country.id] = snapshot
        }
        return snapshot
    }

    /// Compatibility for callers that need a combined context, such as the companion.
    /// Each category is cached separately; a successful headline never caches a failed chart.
    func fetch(for country: Country) async -> CountryFeed {
        async let music = fetchMusic(for: country)
        async let news = fetchNews(for: country)
        let (musicResult, newsResult) = await (music, news)
        return CountryFeed(
            tracks: musicResult.items,
            stories: newsResult.items,
            musicFetchedAt: musicResult.fetchedAt,
            newsFetchedAt: newsResult.fetchedAt,
            musicUnavailable: musicResult.unavailable,
            newsUnavailable: newsResult.unavailable
        )
    }

    func invalidate(countryID: String) {
        musicCache.removeValue(forKey: countryID.uppercased())
        newsCache.removeValue(forKey: countryID.uppercased())
        // Responses already in flight must not undo explicit invalidation.
        musicRequests[countryID.uppercased()] = UUID()
        newsRequests[countryID.uppercased()] = UUID()
    }

    private struct FeedResult<Item: Sendable>: Sendable {
        let items: [Item]
        let message: String?
        var canCache = true
    }

    private enum FeedError: Error {
        case http(Int)
        case invalidResponse
        case invalidPayload
        case tooLarge
    }

    private static func data(from url: URL, session: URLSession,
                             timeout: TimeInterval = 18, bypassCache: Bool = false) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        if bypassCache { request.cachePolicy = .reloadIgnoringLocalCacheData }
        request.setValue("WorldNiche/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw FeedError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw FeedError.http(http.statusCode) }
        guard data.count <= 3_000_000 else { throw FeedError.tooLarge }
        return data
    }

    /// The public chart endpoint intermittently times out or returns 5xx before
    /// succeeding. Retry twice inside the same load instead of requiring refresh taps.
    private static func musicData(from url: URL, retryURL: URL, session: URLSession) async throws -> Data {
        var retries = 0
        while true {
            do {
                // The equivalent 25-song feed can remain healthy when the 10-song
                // endpoint stalls. Both URLs always use the requested storefront.
                let attemptURL = retries == 0 ? url : retryURL
                return try await data(from: attemptURL, session: session, timeout: 6, bypassCache: true)
            } catch {
                try Task.checkCancellation()
                guard retries < 2, isTransientMusicError(error) else { throw error }
                retries += 1
                try await Task.sleep(for: .milliseconds(retries == 1 ? 250 : 500))
            }
        }
    }

    private static func isTransientMusicError(_ error: any Error) -> Bool {
        switch error {
        case FeedError.http(let status):
            return status == 408 || (500...599).contains(status)
        case let error as URLError:
            return [.timedOut, .networkConnectionLost, .cannotConnectToHost,
                    .cannotFindHost, .dnsLookupFailed].contains(error.code)
        default:
            return false
        }
    }

    private static func loadMusic(for country: Country, session: URLSession) async -> FeedResult<MusicTrack> {
        if let listedStorefronts, !listedStorefronts.contains(country.id.uppercased()) {
            return FeedResult(items: [], message: "Apple’s public chart directory does not list a storefront for this location.")
        }
        // These are storefront rankings, not a survey of everyone in the country.
        let storefront = country.id.lowercased()
        guard let url = URL(string: "https://rss.marketingtools.apple.com/api/v2/\(storefront)/music/most-played/10/songs.json?format=json"),
              let retryURL = URL(string: "https://rss.marketingtools.apple.com/api/v2/\(storefront)/music/most-played/25/songs.json") else {
            return FeedResult(items: [], message: "A chart is not available for this location.")
        }
        do {
            let payload = try JSONDecoder().decode(AppleChart.self, from: await musicData(from: url, retryURL: retryURL, session: session))
            let tracks = payload.feed.results.compactMap { result -> MusicTrack? in
                guard let link = URL(string: result.url), link.scheme == "https" else { return nil }
                return MusicTrack(id: result.id, title: result.name, artist: result.artistName,
                                  artworkURL: result.artworkUrl100.flatMap(URL.init(string:)), url: link)
            }
            return FeedResult(items: Array(tracks.prefix(10)), message: tracks.isEmpty ? "Apple Music has no chart to share for this location." : nil)
        } catch {
            let message: String
            var canCache = false
            switch error {
            case FeedError.http(400), FeedError.http(404):
                message = "Apple Music does not provide a public chart for this location."
                canCache = true
            case is CancellationError:
                message = "Chart loading was cancelled."
            case let error as URLError where error.code == .cancelled:
                message = "Chart loading was cancelled."
            case let error as URLError where error.code == .notConnectedToInternet:
                message = "You appear to be offline. Reconnect to load the Apple Music chart."
            default:
                message = "Apple Music isn’t responding right now. Please try again shortly."
            }
            return FeedResult(items: [], message: message, canCache: canCache)
        }
    }

    private static func loadNews(for country: Country, session: URLSession) async -> FeedResult<NewsStory> {
        guard let url = newsFeeds[country.id.uppercased()] else {
            return FeedResult(items: [], message: "Global Voices does not list a country feed for this place yet.")
        }
        do {
            let xml = try await data(from: url, session: session)
            let reader = NewsRSSReader()
            let stories = try reader.read(xml)
            return FeedResult(items: Array(stories.prefix(8)), message: stories.isEmpty ? "Global Voices has no recent stories to share for this place." : nil)
        } catch {
            let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
            return FeedResult(items: [], message: cancelled ? "News loading was cancelled." : "The news feed could not load. Try again when you’re connected.", canCache: false)
        }
    }

    private struct AppleChart: Decodable {
        let feed: Feed
        struct Feed: Decodable { let results: [Track] }
        struct Track: Decodable {
            let id: String
            let name: String
            let artistName: String
            let artworkUrl100: String?
            let url: String
        }
    }
}

/// A per-request parser; no shared mutable parsing or date-formatting state.
private final class NewsRSSReader: NSObject, XMLParserDelegate {
    private var stories: [NewsStory] = []
    private var item: [String: String] = [:]
    private var element = ""
    private var inItem = false
    private var documentIsRSS = false

    func read(_ data: Data) throws -> [NewsStory] {
        // A publisher's article body can contain legacy control characters.
        // Replace only scalars forbidden by XML 1.0, then still require valid XML.
        guard let xml = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        let scalars = xml.unicodeScalars.map { scalar -> Unicode.Scalar in
            let value = scalar.value
            return value == 9 || value == 10 || value == 13 || (32...0xD7FF).contains(value)
                || (0xE000...0xFFFD).contains(value) || (0x10000...0x10FFFF).contains(value) ? scalar : "\u{FFFD}"
        }
        let parser = XMLParser(data: Data(String(String.UnicodeScalarView(scalars)).utf8))
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), documentIsRSS else {
            throw parser.parserError ?? CocoaError(.fileReadCorruptFile)
        }
        return stories
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        element = elementName
        if elementName == "rss" { documentIsRSS = true }
        if elementName == "item" { inItem = true; item = [:] }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inItem, ["title", "link", "dc:creator", "pubDate"].contains(element) { item[element, default: ""] += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if inItem, ["title", "link", "dc:creator", "pubDate"].contains(element), let text = String(data: CDATABlock, encoding: .utf8) {
            item[element, default: ""] += text
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        defer { element = "" }
        guard elementName == "item" else { return }
        inItem = false
        let title = item["title", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        let link = item["link", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        let author = item["dc:creator", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !author.isEmpty, let url = URL(string: link),
              url.scheme == "https", url.host == "globalvoices.org", url.user == nil else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = item["pubDate"].flatMap({ formatter.date(from: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }),
              date > Date().addingTimeInterval(-365 * 86400), date <= Date().addingTimeInterval(86400) else { return }
        guard !stories.contains(where: { $0.url == url }) else { return }
        stories.append(NewsStory(id: link, title: title, source: "Global Voices", url: url, publishedAt: date, author: author))
    }
}

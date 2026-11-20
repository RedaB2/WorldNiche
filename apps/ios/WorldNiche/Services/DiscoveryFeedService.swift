import Foundation

/// Public, country-scoped music charts.
actor DiscoveryFeedService {
    private let session: URLSession
    private let cacheLifetime: TimeInterval = 15 * 60
    private var musicCache: [String: FeedSnapshot<MusicTrack>] = [:]
    private var musicRequests: [String: UUID] = [:]

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

    func invalidate(countryID: String) {
        musicCache.removeValue(forKey: countryID.uppercased())
        // Responses already in flight must not undo explicit invalidation.
        musicRequests[countryID.uppercased()] = UUID()
    }

    private struct FeedResult: Sendable {
        let items: [MusicTrack]
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
                             bypassCache: Bool = false) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
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
                return try await data(from: attemptURL, session: session, bypassCache: true)
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

    private static func loadMusic(for country: Country, session: URLSession) async -> FeedResult {
        if let listedStorefronts, !listedStorefronts.contains(country.id.uppercased()) {
            return await loadRadioChart(for: country, session: session)
        }
        let storefront = country.id.lowercased()
        guard let url = URL(string: "https://rss.marketingtools.apple.com/api/v2/\(storefront)/music/most-played/10/songs.json?format=json"),
              let retryURL = URL(string: "https://rss.marketingtools.apple.com/api/v2/\(storefront)/music/most-played/25/songs.json") else {
            return FeedResult(items: [], message: "A chart is not available for this location.")
        }
        do {
            let payload = try JSONDecoder().decode(AppleChart.self, from: await musicData(from: url, retryURL: retryURL, session: session))
            guard payload.feed.country.uppercased() == country.id else { throw FeedError.invalidPayload }
            if payload.feed.results.isEmpty { return await loadRadioChart(for: country, session: session) }
            var tracks: [MusicTrack] = []
            for result in payload.feed.results.prefix(5) {
                guard let link = URL(string: result.url), link.scheme == "https", link.host == "music.apple.com",
                      !result.id.isEmpty, !result.name.isEmpty, !result.artistName.isEmpty,
                      !tracks.contains(where: { $0.id == result.id }) else { throw FeedError.invalidPayload }
                tracks.append(MusicTrack(id: result.id, title: result.name, artist: result.artistName,
                                         artworkURL: result.artworkUrl100.flatMap(URL.init(string:)), url: link))
            }
            return FeedResult(items: tracks, message: nil)
        } catch {
            let message: String
            switch error {
            case FeedError.http(400), FeedError.http(404):
                return await loadRadioChart(for: country, session: session)
            case is CancellationError:
                message = "Chart loading was cancelled."
            case let error as URLError where error.code == .cancelled:
                message = "Chart loading was cancelled."
            case let error as URLError where error.code == .notConnectedToInternet:
                message = "You appear to be offline. Reconnect to load the Apple Music chart."
            default:
                message = "Apple Music isn’t responding right now. Please try again shortly."
            }
            return FeedResult(items: [], message: message, canCache: false)
        }
    }

    private static func loadRadioChart(for country: Country, session: URLSession) async -> FeedResult {
        var components = URLComponents(string: "https://api.tuneping.com/v1/charts/tracks")!
        components.queryItems = [URLQueryItem(name: "days", value: "7"),
                                 URLQueryItem(name: "country", value: country.id),
                                 URLQueryItem(name: "limit", value: "5")]
        do {
            let bytes = try await data(from: components.url!, session: session)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let chart = try decoder.decode(RadioChart.self, from: bytes)
            guard chart.country == country.id, chart.days == 7 else { throw FeedError.invalidPayload }
            var tracks: [MusicTrack] = []
            for (index, row) in chart.data.prefix(5).enumerated() {
                let track = row.track
                guard row.rank == index + 1, row.plays >= row.stations, row.stations > 0,
                      row.countries.count == 1, row.countries.first?.country == country.id,
                      !track.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !track.artistCredit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !tracks.contains(where: { $0.id == track.mbid.uuidString }) else { throw FeedError.invalidPayload }
                let url = URL(string: "https://musicbrainz.org/recording/")!.appendingPathComponent(track.mbid.uuidString.lowercased())
                let sample = "\(row.plays) \(row.plays == 1 ? "play" : "plays") · \(row.stations) \(row.stations == 1 ? "station" : "stations")"
                tracks.append(MusicTrack(id: track.mbid.uuidString, title: track.title, artist: track.artistCredit,
                                         artworkURL: nil, url: url, provider: .tuneping, radioSample: sample))
            }
            return FeedResult(items: tracks, message: tracks.isEmpty ? "No local music chart is available this week." : nil)
        } catch {
            let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
            let message = cancelled ? "Chart loading was cancelled." : "The local radio chart could not load. Please try again shortly."
            return FeedResult(items: [], message: message, canCache: false)
        }
    }

    private struct RadioChart: Decodable {
        let country: String
        let days: Int
        let data: [Row]
        struct Row: Decodable {
            let rank: Int
            let plays: Int
            let stations: Int
            let countries: [Market]
            let track: Track
        }
        struct Market: Decodable { let country: String }
        struct Track: Decodable {
            let mbid: UUID
            let title: String
            let artistCredit: String
        }
    }

    private struct AppleChart: Decodable {
        let feed: Feed
        struct Feed: Decodable {
            let country: String
            let results: [Track]
        }
        struct Track: Decodable {
            let id: String
            let name: String
            let artistName: String
            let artworkUrl100: String?
            let url: String
        }
    }
}

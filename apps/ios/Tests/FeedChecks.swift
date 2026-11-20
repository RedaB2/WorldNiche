import Foundation

private final class MockState: @unchecked Sendable {
    enum Mode {
        case success, apple502Twice, appleTimeoutTwice, appleDown, appleMissing, appleEmpty
        case invalidAppleTrack, offline, malformed, wrongStorefront, wrongRadioMarket, wrongRowMarket, missingRank, radioEmpty
    }

    private let lock = NSLock()
    private var mode: Mode = .success
    private var urls: [URL] = []

    func configure(_ newMode: Mode) {
        lock.withLock {
            mode = newMode
            urls.removeAll()
        }
    }

    var requests: [URL] { lock.withLock { urls } }

    func record(_ url: URL) -> (mode: Mode, count: Int) {
        lock.withLock {
            urls.append(url)
            return (mode, urls.count)
        }
    }
}
private let mock = MockState()

private final class MockProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let (mode, count) = mock.record(url)
        let apple = url.host == "rss.marketingtools.apple.com"
        if mode == .offline || (apple && mode == .appleTimeoutTwice && count <= 2) {
            client?.urlProtocol(self, didFailWithError: URLError(mode == .offline ? .notConnectedToInternet : .timedOut))
            return
        }

        let status: Int
        let body: Data
        switch url.host {
        case "rss.marketingtools.apple.com":
            if mode == .appleMissing {
                status = 404
            } else {
                status = mode == .appleDown || (mode == .apple502Twice && count <= 2) ? 502 : 200
            }
            let country = mode == .wrongStorefront ? "us" : url.pathComponents[3]
            let tracks = mode == .appleEmpty ? [] : (1...10).map {
                ["id": String($0), "name": "Song \($0)", "artistName": "Artist",
                 "url": mode == .invalidAppleTrack && $0 == 2 ? "javascript:void(0)" : "https://music.apple.com/track/\($0)"]
            }
            body = try! JSONSerialization.data(withJSONObject: ["feed": ["country": country, "results": tracks]])
        case "api.tuneping.com":
            status = 200
            precondition(url.path == "/v1/charts/tracks")
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            precondition(query.contains(URLQueryItem(name: "days", value: "7")))
            precondition(query.contains(URLQueryItem(name: "limit", value: "5")))
            let country = query.first { $0.name == "country" }!.value!
            let rows: [[String: Any]] = mode == .radioEmpty ? [] : (1...3).map { rank in
                ["rank": mode == .missingRank ? rank + 1 : rank, "plays": rank + 1, "stations": rank,
                 "countries": [["country": mode == .wrongRowMarket ? "XX" : country]],
                 "track": ["mbid": "00000000-0000-0000-0000-00000000000\(rank)",
                           "title": "Radio Song \(rank)", "artist_credit": "Radio Artist"]]
            }
            body = try! JSONSerialization.data(withJSONObject: [
                "country": mode == .wrongRadioMarket ? "XX" : country, "days": 7, "data": rows
            ])
        default:
            preconditionFailure("Unexpected chart host \(url)")
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: mode == .malformed ? Data("{".utf8) : body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// Hold an old request so a later refresh or invalidation deterministically wins the race.
private final class RaceState: @unchecked Sendable {
    private let lock = NSLock()
    private var first: RaceProtocol?
    private var requestCount = 0

    var count: Int { lock.withLock { requestCount } }

    func begin(_ request: RaceProtocol) -> Int {
        lock.withLock {
            requestCount += 1
            if requestCount == 1 { first = request }
            return requestCount
        }
    }

    func releaseFirst() {
        let request = lock.withLock { first }
        request?.deliver(version: 1)
    }

    func reset() {
        lock.withLock { requestCount = 0; first = nil }
    }
}
private let race = RaceState()
private final class RaceProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let version = race.begin(self)
        if version > 1 { deliver(version: version) }
    }
    func deliver(version: Int) {
        let music = #"{"feed":{"country":"fr","results":[{"id":"\#(version)","name":"Song","artistName":"Artist","url":"https://music.apple.com/track"}]}}"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(music.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct Checks {
    static func main() async {
        let countries = CountryRepository.countries
        precondition(countries.count == 195 && Set(countries.map(\.id)).count == 195)
        precondition(CountryRepository.country(id: "fr")?.flag == "🇫🇷")
        precondition(CountryRepository.country(id: "PS") != nil && CountryRepository.country(id: "VA") != nil)
        precondition(countries.allSatisfy { (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) })
        for _ in 0..<100 { precondition(CountryRepository.random(excluding: "fr").id != "FR") }
        struct Directory: Decodable { let storefronts: [String] }
        let url = Bundle.main.url(forResource: "apple-music-storefronts", withExtension: "json")!
        let storefronts = Set(try! JSONDecoder().decode(Directory.self, from: Data(contentsOf: url)).storefronts)
        precondition(storefronts.count == 172 && countries.filter { storefronts.contains($0.id) }.count == 162)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProtocol.self]
        let session = URLSession(configuration: configuration)
        let france = CountryRepository.country(id: "FR")!
        let cuba = CountryRepository.country(id: "CU")!
        await checkApple(france, session)
        await checkRadio(cuba, france, session)
        await checkCacheRace(france)
        if CommandLine.arguments.contains("--live-coverage") {
            let service = DiscoveryFeedService()
            var full = 0, partial = 0, empty = 0
            for country in countries where !storefronts.contains(country.id) {
                let chart = await service.fetchMusic(for: country)
                precondition(chart.items.allSatisfy { $0.provider == .tuneping })
                switch chart.items.count {
                case 5: full += 1
                case 1...4: partial += 1
                case 0:
                    precondition(chart.unavailable == "No local music chart is available this week.",
                                 "\(country.name): \(chart.unavailable ?? "Missing status")")
                    empty += 1
                default: preconditionFailure("Unexpected chart length")
                }
                try? await Task.sleep(for: .milliseconds(600))
            }
            print("PASS: unlisted storefronts: \(full) full, \(partial) partial, \(empty) empty radio charts.")
        }
        if CommandLine.arguments.contains("--live") {
            let live = DiscoveryFeedService()
            for (country, provider) in [(france, MusicChartProvider.appleMusic), (cuba, .tuneping)] {
                let chart = await live.fetchMusic(for: country)
                precondition((1...5).contains(chart.items.count) && chart.items.first?.provider == provider,
                             chart.unavailable ?? "Wrong live chart for \(country.name)")
                print("PASS: live \(provider.rawValue), \(country.name), \(chart.items.count) ranked tracks.")
            }
        }
    }

    private static func checkApple(_ country: Country, _ session: URLSession) async {
        for mode: MockState.Mode in [.success, .apple502Twice, .appleTimeoutTwice] {
            mock.configure(mode)
            let service = DiscoveryFeedService(session: session)
            let result = await service.fetchMusic(for: country)
            precondition(result.items.map(\.id) == (1...5).map(String.init))
            precondition(result.items.allSatisfy { $0.provider == .appleMusic && $0.radioSample == nil })
            let paths = mock.requests.map(\.path)
            let firstURL = "/api/v2/fr/music/most-played/10/songs.json"
            let retryURL = "/api/v2/fr/music/most-played/25/songs.json"
            precondition(paths == (mode == .success ? [firstURL] : [firstURL, retryURL, retryURL]))
            precondition(mock.requests.allSatisfy { $0.host == "rss.marketingtools.apple.com" })
            let cached = await service.fetchMusic(for: country)
            precondition(mock.requests.count == paths.count && cached.fetchedAt == result.fetchedAt)
        }
        for mode: MockState.Mode in [.appleDown, .wrongStorefront, .invalidAppleTrack, .malformed, .offline] {
            mock.configure(mode)
            let failed = await DiscoveryFeedService(session: session).fetchMusic(for: country)
            precondition(failed.items.isEmpty && failed.unavailable != nil)
            precondition(mock.requests.count == (mode == .appleDown ? 3 : 1))
            precondition(mock.requests.allSatisfy { $0.host == "rss.marketingtools.apple.com" })
        }
        mock.configure(.appleDown)
        let service = DiscoveryFeedService(session: session)
        let task = Task { await service.fetchMusic(for: country) }
        for _ in 0..<1000 where mock.requests.isEmpty { try? await Task.sleep(for: .milliseconds(1)) }
        task.cancel()
        let cancelled = await task.value
        precondition(cancelled.items.isEmpty && mock.requests.count == 1)
        mock.configure(.success)
        let recovered = await service.fetchMusic(for: country)
        precondition(recovered.items.count == 5 && mock.requests.count == 1)
        print("PASS: Apple top five, storefront identity, bounded chart retries, cancellation and success cache.")
    }

    private static func checkRadio(_ unlisted: Country, _ listed: Country, _ session: URLSession) async {
        for mode: MockState.Mode in [.success, .appleMissing, .appleEmpty] {
            mock.configure(mode)
            let country = mode == .success ? unlisted : listed
            let service = DiscoveryFeedService(session: session)
            let chart = await service.fetchMusic(for: country)
            precondition(chart.unavailable == nil && chart.items.map(\.title) == (1...3).map { "Radio Song \($0)" })
            precondition(chart.items.allSatisfy { $0.provider == .tuneping && $0.url.host == "musicbrainz.org" })
            precondition(chart.items.first?.url.lastPathComponent == "00000000-0000-0000-0000-000000000001")
            precondition(chart.items.first?.radioSample == "2 plays · 1 station")
            let expectedCount = mode == .success ? 1 : 2
            precondition(mock.requests.count == expectedCount && mock.requests.last?.host == "api.tuneping.com")
            precondition(mock.requests.last?.query?.contains("country=\(country.id)") == true)
            _ = await service.fetchMusic(for: country)
            precondition(mock.requests.count == expectedCount)
        }
        for mode: MockState.Mode in [.wrongRadioMarket, .wrongRowMarket, .missingRank, .malformed, .offline] {
            mock.configure(mode)
            let service = DiscoveryFeedService(session: session)
            let failed = await service.fetchMusic(for: unlisted)
            precondition(failed.items.isEmpty && failed.unavailable != nil && mock.requests.count == 1)
            mock.configure(.success)
            let recovered = await service.fetchMusic(for: unlisted)
            precondition(recovered.items.count == 3 && mock.requests.count == 1)
        }
        mock.configure(.radioEmpty)
        let service = DiscoveryFeedService(session: session)
        let empty = await service.fetchMusic(for: unlisted)
        precondition(empty.items.isEmpty && empty.unavailable?.contains("No local music chart") == true)
        _ = await service.fetchMusic(for: unlisted)
        precondition(mock.requests.count == 1)
        mock.configure(.success)
        let refreshed = await service.fetchMusic(for: unlisted, forceRefresh: true)
        precondition(refreshed.items.count == 3 && mock.requests.count == 1)
        print("PASS: radio routing, attribution, partial and empty charts, invalid geography, rank gaps and retry.")
    }

    private static func checkCacheRace(_ country: Country) async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RaceProtocol.self]
        let session = URLSession(configuration: configuration)
        for invalidate in [false, true] {
            race.reset()
            let service = DiscoveryFeedService(session: session)
            let older = Task { await service.fetchMusic(for: country) }
            for _ in 0..<1000 where race.count == 0 { try? await Task.sleep(for: .milliseconds(1)) }
            precondition(race.count == 1)
            if invalidate { await service.invalidate(countryID: "fr") }
            else {
                let newer = await service.fetchMusic(for: country, forceRefresh: true)
                precondition(newer.items.first?.id == "2")
            }
            race.releaseFirst()
            _ = await older.value
            let fresh = await service.fetchMusic(for: country)
            precondition(fresh.items.first?.id == "2" && race.count == 2)
        }
        print("PASS: overlapping refresh and invalidation cannot restore stale charts.")
    }
}

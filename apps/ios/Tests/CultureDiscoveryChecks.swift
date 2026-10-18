import Foundation

private final class DiscoveryClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_700_000_000)
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(seconds) }
}

enum CultureDiscoveryChecks {
    static let france = Country(id: "FR", name: "France", capital: "Paris", region: "Europe", latitude: 46, longitude: 2)
    static let japan = Country(id: "JP", name: "Japan", capital: "Tokyo", region: "Asia", latitude: 36, longitude: 138)
    static func payload(_ rows: [(String, String, Int)], offset: Int? = nil) throws -> Data {
        var value: [String: Any] = ["query": ["pages": rows.map { ["title": $0.0, "description": $0.1, "ns": $0.2] as [String: Any] }]]
        if let offset { value["continue"] = ["gsroffset": offset, "continue": "-||"] }
        return try JSONSerialization.data(withJSONObject: value)
    }
    static let valid = [("Faire la bise", "A greeting custom in France.", 0), ("Réveillon", "A traditional French celebratory meal.", 0)]
    static func run() async throws {
        try await filteringAndExpiry()
        try await moroccoCountrySpecificPriority()
        try await topUpAndBackoff()
        try await paginationAndExclusions()
        try await coalescingAndCancellation()
        try await soleCallerCancellation()
    }
    static func filteringAndExpiry() async throws {
        let noise = [
            ("France", "French music and food", 0), ("Culture of France", "French tradition", 0),
            ("French cuisine", "French food", 0), ("Japanese ceremony", "Japanese ritual", 0),
            ("Custom (disambiguation)", "French custom", 0), ("Category:French music", "French music", 14),
            ("Random village", "A village in France.", 0), ("Singer", "A French singer of traditional music.", 0),
            ("Symphony No. 6", "A French symphony inspired by folk music.", 0),
            ("Old musician", "A French musician born 1738, known for traditional music.", 0),
            ("Folk record", "A French album of traditional music.", 0),
            ("Custom Robo", "A Japanese video game about custom robots.", 0),
            ("Custom of Paris", "A French regional system of civil law.", 0)
        ]
        MockCultureURLProtocol.transport.reset([
            .init(data: try payload(valid + noise + [valid[0]])),
            .init(data: try payload([("Fête des voisins", "A local French community festival.", 0), ("Fête de la Rosière", "A regional French festival.", 0)]))
        ])
        let session = LiveCultureChecks.makeSession(); defer { session.invalidateAndCancel() }
        let clock = DiscoveryClock()
        let service = CultureTopicDiscovery(session: session, now: { clock.read() })
        let first = await service.topics(for: france, minimumCount: 2)
        try require(Set(first) == Set(valid.map(\.0)), "Discovery admitted broad, irrelevant, duplicate, biography, or individual-work articles: \(first)")
        let repeated = await service.topics(for: france, minimumCount: 2)
        try require(repeated == first && MockCultureURLProtocol.transport.snapshot().requests.count == 1, "Unconsumed pool did not reuse its results.")
        let request = MockCultureURLProtocol.transport.snapshot().requests[0]
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        try require(query.first(where: { $0.name == "gsrsearch" })?.value?.contains("articlecountry:fra") == true, "Search was not geographically scoped.")
        try require(query.first(where: { $0.name == "gsrsearch" })?.value?.contains("-articletopic:biography") == true, "Search did not exclude biographies.")
        try require(query.first(where: { $0.name == "gsrlimit" })?.value == "20" && request.timeoutInterval == 10, "Search was not bounded.")
        clock.advance(86_401)
        let renewed = await service.topics(for: france, minimumCount: 2)
        try require(renewed.count == 2 && !renewed.contains(valid[0].0) && MockCultureURLProtocol.transport.snapshot().requests.count == 2, "Expired search pool did not renew.")
        try require(!CultureTopicDiscovery.isCulturalSummary("Raita is an Indian dish made from yogurt. " + String(repeating: "The traditional food is served with meals. ", count: 4), country: Country(id: "FJ", name: "Fiji", capital: "Suva", region: "Oceania", latitude: -18, longitude: 178)), "Unrelated country evidence was accepted.")
        let globalCustom = "An annual custom in many countries consists of practical jokes and pranks. " + String(repeating: "The tradition is observed around the world. ", count: 3)
        try require(!CultureTopicDiscovery.isCulturalSummary(globalCustom, country: japan), "A generic worldwide custom was presented as a country-specific discovery.")
        let regionalDance = "Kagura is a Shinto ritual ceremonial dance. " + String(repeating: "Performers use masks and musical instruments during the ceremony. ", count: 3)
        try require(CultureTopicDiscovery.isCulturalSummary(regionalDance, country: japan, hasCountryContext: true), "Verified country context from the article description was lost.")
        print("PASS: niche practice filtering, geographic scope, source-country validation, deduplication, bounded requests and expiry")
    }
    static func topUpAndBackoff() async throws {
        MockCultureURLProtocol.transport.reset([.init(data: try payload([valid[0]])), .init(data: try payload(valid))])
        let session = LiveCultureChecks.makeSession(); defer { session.invalidateAndCancel() }
        let completed = await CultureTopicDiscovery(session: session).topics(for: france, minimumCount: 2)
        try require(Set(completed) == Set(valid.map(\.0)), "Top-up did not preserve and deduplicate first results.")
        try require(MockCultureURLProtocol.transport.snapshot().requests.count == 2, "Sparse discovery did not top up.")
        MockCultureURLProtocol.transport.reset([
            .init(data: try payload([valid[0]])), .init(status: 429, headers: ["Retry-After": "0"], data: Data()),
            .init(data: try payload([("Kanjo Nawa", "A Japanese village custom.", 0), ("Yuzanbako", "A Japanese traditional lunch custom.", 0)]))
        ])
        let clock = DiscoveryClock()
        let limited = CultureTopicDiscovery(session: session, now: { clock.read() })
        let retained = await limited.topics(for: france, minimumCount: 2)
        try require(retained == [valid[0].0], "A failed top-up discarded the first successful page.")
        let blocked = await limited.topics(for: japan, minimumCount: 2)
        try require(blocked.isEmpty && MockCultureURLProtocol.transport.snapshot().requests.count == 2, "Backoff did not suppress cross-country requests.")
        clock.advance(61)
        let recovered = await limited.topics(for: japan, minimumCount: 2)
        try require(recovered.count == 2 && MockCultureURLProtocol.transport.snapshot().requests.count == 3, "Discovery did not recover after backoff.")
        print("PASS: incremental top-up, partial-result preservation, HTTP429 backoff and recovery")
    }

    static func moroccoCountrySpecificPriority() async throws {
        let morocco = Country(id: "MA", name: "Morocco", capital: "Rabat", region: "Africa", latitude: 32, longitude: -5)
        // Descriptions observed in the live Morocco probe. Generic regional hits
        // used to precede the explicitly Moroccan practice, and Tafilalt slipped through.
        MockCultureURLProtocol.transport.reset([
            .init(data: try payload([
                ("Mawsim", "Annual regional festival in Maghreb countries", 0),
                ("Smen", "Salted, fermented butter used in Middle Eastern and North African cuisine", 0),
                ("Tafilalt", "Traditional Region in Drâa-Tafilalet, Morocco", 0)
            ])),
            .init(data: try payload([
                ("Snake charming", "Practice of appearing to hypnotise a snake", 0),
                ("Gnawa music", "Moroccan music genre and type of dance", 0)
            ])),
            .init(data: try payload([
                ("Fez Festival of World Sacred Music", "Annual music festival held in Fez, Morocco", 0),
                ("Mawazine", "Annual Moroccan music festival", 0)
            ])),
            .init(data: try LiveCultureChecks.summary(title: "Gnawa music", excerpt: "Gnawa music is a Moroccan music genre and type of dance. The tradition includes ritual poetry and music, and combines music and acrobatic dancing in its performances.", source: "https://en.wikipedia.org/wiki/Gnawa_music"))
        ])
        let session = LiveCultureChecks.makeSession(); defer { session.invalidateAndCancel() }
        let result = await LiveCultureService(session: session, allowsGeneration: false).fetch(for: morocco)
        try require(result.reading?.title == "Gnawa music" && result.message == nil, "A fresh Morocco discovery did not prioritize the explicitly local practice.")
        let summaryRequests = MockCultureURLProtocol.transport.snapshot().requests.filter { $0.url?.path.contains("/page/summary/") == true }
        try require(summaryRequests.count == 1 && summaryRequests.first?.url?.lastPathComponent == "Gnawa_music", "Broad regional hits consumed the initial summary attempts.")
        let geographicSummary = "Tafilalt or Tafilet, historically Sijilmasa, is a traditional region of Morocco, centered on its largest oasis. it largely corresponds to Errachidia Province."
        try require(!CultureTopicDiscovery.isCulturalSummary(geographicSummary, country: morocco, hasCountryContext: true), "A traditional region was accepted as a cultural practice.")
        print("PASS: Morocco prioritizes explicitly local culture and rejects generic geographic regions")
    }
    static func paginationAndExclusions() async throws {
        // Walk all facets, then revisit the first at its continuation offset.
        var replies = [ScriptedTransport.Reply(data: try payload(valid, offset: 24))]
        for i in 1..<8 { replies.append(.init(data: try payload([("Custom \(i)", "A French local custom.", 0)], offset: 24))) }
        replies.append(.init(data: try payload([valid[0], ("Unseen custom", "A French local ritual.", 0)], offset: 48)))
        MockCultureURLProtocol.transport.reset(replies)
        let session = LiveCultureChecks.makeSession(); defer { session.invalidateAndCancel() }
        let service = CultureTopicDiscovery(session: session)
        var seen = Set<String>()
        for _ in 0..<9 {
            let titles = await service.topics(for: france, excluding: seen, minimumCount: 1)
            try require(!titles.isEmpty && seen.isDisjoint(with: Set(titles)), "Consumed topics were returned instead of topping up.")
            seen.formUnion(titles)
        }
        let requests = MockCultureURLProtocol.transport.snapshot().requests
        let query = URLComponents(url: requests.last!.url!, resolvingAgainstBaseURL: false)!.queryItems!
        try require(query.first(where: { $0.name == "gsroffset" })?.value == "24", "Saved MediaWiki pagination cursor was not followed.")
        try require(seen.contains("Unseen custom") && requests.count == 9, "Discovery stopped at its original pool.")
        print("PASS: unseen exclusions, pool replenishment across facets and continuation pagination")
    }
    static func coalescingAndCancellation() async throws {
        MockCultureURLProtocol.transport.reset([.init(data: try payload(valid), delayNanoseconds: 100_000_000)])
        let session = LiveCultureChecks.makeSession(); defer { session.invalidateAndCancel() }
        let service = CultureTopicDiscovery(session: session)
        let first = Task { await service.topics(for: france, minimumCount: 2) }
        try await LiveCultureChecks.waitUntil("Discovery did not start.") { MockCultureURLProtocol.transport.snapshot().requests.count == 1 }
        let second = Task { await service.topics(for: france, minimumCount: 2) }
        // Creating a Task does not guarantee it has joined the shared request.
        for _ in 0..<200 {
            if await service.pendingSubscriberCount(for: france.id) == 2 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let subscribers = await service.pendingSubscriberCount(for: france.id)
        try require(subscribers == 2, "The second caller did not join the shared request.")
        first.cancel()
        let abandoned = await first.value; let kept = await second.value
        try require(abandoned.isEmpty && Set(kept) == Set(valid.map(\.0)), "One caller's cancellation affected another caller.")
        try require(MockCultureURLProtocol.transport.snapshot().requests.count == 1, "Concurrent discovery was not coalesced.")
        print("PASS: concurrent discovery coalescing and independent caller cancellation")
    }
    static func soleCallerCancellation() async throws {
        MockCultureURLProtocol.transport.reset([.init(data: try payload(valid), delayNanoseconds: 30_000_000_000), .init(data: try payload(valid))])
        let session = LiveCultureChecks.makeSession(); defer { session.invalidateAndCancel() }
        let service = CultureTopicDiscovery(session: session)
        let abandoned = Task { await service.topics(for: france, minimumCount: 2) }
        try await LiveCultureChecks.waitUntil("Sole caller did not start.") { MockCultureURLProtocol.transport.snapshot().requests.count == 1 }
        abandoned.cancel()
        let result = await abandoned.value
        try require(result.isEmpty, "Cancelled caller received discovered topics.")
        try await LiveCultureChecks.waitUntil("All callers cancelled but transport kept running.") { MockCultureURLProtocol.transport.snapshot().stopped > 0 }
        let next = await service.topics(for: france, minimumCount: 2)
        try require(next.count == 2 && MockCultureURLProtocol.transport.snapshot().requests.count == 2, "Cancelled discovery poisoned the next pool.")
        print("PASS: cancelling the final subscriber stops discovery transport without poisoning cache")
    }

}

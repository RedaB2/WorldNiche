import Foundation

private actor PublicationServer {
    private var data: Data?
    private(set) var calls = 0

    init(_ data: Data) { self.data = data }
    func serve(_ data: Data?) { self.data = data }

    func fetch(_ url: URL) async throws -> Data {
        precondition(url.absoluteString == "https://example.test/v1/historical-facts.json")
        calls += 1
        try await Task.sleep(for: .milliseconds(10))
        guard let data else { throw URLError(.notConnectedToInternet) }
        return data
    }
}

@MainActor
enum FactPublicationChecks {
    static func run(bundled: FactCatalogSnapshot) async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let file = temporary.appendingPathComponent("cache.json")
        let endpoint = URL(string: "https://example.test/v1/historical-facts.json")!
        let ids = Set(bundled.countries.keys)
        let encoder = JSONEncoder()
        var next = bundled.countries
        let original = next["MA"]![0]
        let sourceURL = original.sourceURL
        let correction = HistoricalFact(id: original.id, title: "Corrected title", body: "Corrected historical wording.",
                                        sourceName: "Test publication", sourceURL: sourceURL)
        func addition(_ index: Int) -> HistoricalFact {
            HistoricalFact(id: "ma-addition-\(index)", title: "Addition \(index)", body: "Historical detail \(index).",
                           sourceName: "Test publication", sourceURL: sourceURL)
        }
        next["MA"]![0] = correction
        next["MA"]!.append(addition(3))
        next["PE"] = []
        func payload(_ countries: [String: [HistoricalFact]], revision: Int, schema: Int = 1) throws -> Data {
            try encoder.encode(FactCatalogSnapshot(schemaVersion: schema, revision: revision, countries: countries))
        }
        let changed = try payload(next, revision: bundled.revision + 1)
        let server = PublicationServer(changed)
        var clock = Date()
        func client(_ seed: FactCatalogSnapshot? = bundled, cache: URL? = file) -> HistoricalFactCatalog {
            HistoricalFactCatalog(bundled: seed, countryIDs: ids, file: cache, endpoint: endpoint,
                                  now: { clock }, fetch: { try await server.fetch($0) })
        }

        let first = client()
        precondition(first["MA"].first == original)
        async let one: Void = first.refresh()
        async let two: Void = first.refresh()
        _ = await (one, two)
        let concurrentCalls = await server.calls
        precondition(concurrentCalls == 1)
        precondition(first.revision == bundled.revision + 1 && first["MA"].first == correction &&
                     first["MA"].last == addition(3) && first["PE"].isEmpty)
        let acceptedBytes = try Data(contentsOf: file)
        precondition(acceptedBytes == changed)
        await first.refresh()
        let callsAfterAutomatic = await server.calls
        precondition(callsAfterAutomatic == concurrentCalls)
        let restored = client()
        precondition(restored.countries == next)
        await restored.refresh()
        let callsAfterRestart = await server.calls
        precondition(callsAfterRestart == concurrentCalls)

        var five = next
        five["MA"]! += [addition(4), addition(5)]
        let fiveData = try payload(five, revision: bundled.revision + 2)
        await server.serve(fiveData)
        await restored.refresh(force: true)
        precondition(restored["MA"].count == 5)
        await server.serve(nil)
        clock = clock.addingTimeInterval(86_401)
        await restored.refresh()
        let callsAfterDay = await server.calls
        precondition(callsAfterDay == concurrentCalls + 2)
        precondition(client().countries == five)

        var invalid = [Data("malformed".utf8), Data(repeating: 0, count: FactCatalogSnapshot.byteLimit + 1)]
        let json = String(decoding: changed, as: UTF8.self)
        let fields = String(json.dropFirst())
        invalid.append(Data(("{\"unrecognized\":1," + fields).utf8))
        invalid.append(Data((#"{"revi\u0073ion":3,"# + fields).utf8))
        invalid.append(Data(json.replacingOccurrences(of: "\"id\":", with: "\"unknown\":true,\"id\":").utf8))
        func invalidChange(_ change: (inout [String: [HistoricalFact]]) -> Void) throws {
            var draft = five
            change(&draft)
            invalid.append(try payload(draft, revision: bundled.revision + 3))
        }
        try invalidChange { $0["MA"]!.append(addition(6)) }
        try invalidChange { $0["FR"] = nil }
        try invalidChange { $0["XX"] = [] }
        try invalidChange { $0["FR"]!.append(correction) }
        let duplicateBody = HistoricalFact(id: "pe-duplicate", title: "A title", body: correction.body,
                                          sourceName: "A publisher", sourceURL: sourceURL)
        try invalidChange { $0["PE"] = [duplicateBody] }
        for (name, url) in [(" ", sourceURL), ("Publisher", URL(string: "http://example.org/item")!),
                            ("Publisher", URL(string: "https://example.org/")!),
                            ("Publisher", URL(string: "https://user@example.org/item")!)] {
            let bad = HistoricalFact(id: "pe-source", title: "Title", body: "Another detail.",
                                    sourceName: name, sourceURL: url)
            try invalidChange { $0["PE"] = [bad] }
        }
        invalid += [try payload(next, revision: 0), try payload(next, revision: 9, schema: 2)]
        for data in invalid {
            let decoded = try? FactCatalogSnapshot.validated(data, countryIDs: ids)
            precondition(decoded == nil, "Accepted malformed publication")
        }
        // Older revisions, rewritten content under an existing revision, and invalid data cannot replace disk or UI.
        for bytes in [changed, try payload(next, revision: restored.revision), invalid[0]] {
            await server.serve(bytes)
            await restored.refresh(force: true)
            precondition(restored.countries == five && client().countries == five)
            let disk = try Data(contentsOf: file)
            precondition(disk == fiveData)
        }
        let futureSeed = FactCatalogSnapshot(schemaVersion: 1, revision: restored.revision + 1, countries: next)
        precondition(client(futureSeed).countries == next)
        try invalid[0].write(to: file)
        precondition(client().countries == bundled.countries)
        let badFile = file.appendingPathComponent("unwritable.json")
        let readOnly = client(cache: badFile)
        await server.serve(changed)
        await readOnly.refresh(force: true)
        precondition(readOnly.countries == bundled.countries, "A failed atomic commit cannot replace the active catalog")
    }
}

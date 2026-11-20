import Foundation

struct HistoricalFact: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let body: String
    let sourceName: String
    let sourceURL: URL
}

extension HistoricalFact {
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        title = try fields.decode(String.self, forKey: .title)
        body = try fields.decode(String.self, forKey: .body)
        sourceName = try fields.decode(String.self, forKey: .sourceName)
        let link = try fields.decode(String.self, forKey: .sourceURL)
        guard link.utf8.count <= 2048, !link.contains("\\"),
              link.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              let url = URL(string: link), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              !url.path.isEmpty, url.path != "/" else { throw CocoaError(.fileReadCorruptFile) }
        sourceURL = url
    }
}

/// A complete editorial publication. An empty country pool explicitly withdraws its facts.
struct FactCatalogSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let revision: Int
    let countries: [String: [HistoricalFact]]

    static let byteLimit = 1_048_576

    static func validated(_ data: Data, countryIDs: Set<String>) throws -> Self {
        guard data.count <= byteLimit else { throw CocoaError(.fileReadTooLarge) }
        let snapshot = try JSONDecoder().decode(Self.self, from: data)
        guard snapshot.schemaVersion == 1, (1...9_007_199_254_740_991).contains(snapshot.revision),
              Set(snapshot.countries.keys) == countryIDs else { throw CocoaError(.fileReadCorruptFile) }

        try validateKeys(data, countryIDs: countryIDs)
        var ids = Set<String>()
        var bodies = Set<String>()
        let idCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        for (code, facts) in snapshot.countries {
            guard facts.count <= CountryRepository.factLimit else { throw CocoaError(.fileReadCorruptFile) }
            let prefix = code.lowercased() + "-"
            for fact in facts {
                guard fact.id.hasPrefix(prefix), fact.id.count > prefix.count,
                      fact.id.utf8.count <= 100, fact.id.unicodeScalars.allSatisfy(idCharacters.contains),
                      ids.insert(fact.id).inserted, bodies.insert(fact.body).inserted,
                      validText(fact.title, limit: 200), validText(fact.body, limit: 1500),
                      validText(fact.sourceName, limit: 240)
                else { throw CocoaError(.fileReadCorruptFile) }
            }
        }
        return snapshot
    }

    // Codable tolerates duplicate and unknown keys. Reject ambiguous publications before caching them.
    private static let objectTokens = try! NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)"(\s*:)?|[{}]"#)

    private static func validateKeys(_ data: Data, countryIDs: Set<String>) throws {
        guard let string = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        let text = string as NSString
        let allowed: [Set<String>] = [
            ["schemaVersion", "revision", "countries"], countryIDs, ["id", "title", "body", "sourceName", "sourceURL"]
        ]
        var objects: [Set<String>] = []
        for token in objectTokens.matches(in: string, range: NSRange(location: 0, length: text.length)) {
            if token.range(at: 1).location == NSNotFound {
                if text.character(at: token.range.location) == 123 { objects.append([]) }
                else { _ = objects.popLast() }
                continue
            }
            guard token.range(at: 2).location != NSNotFound else { continue }
            let raw = text.substring(with: token.range(at: 1))
            let key = raw.contains("\\") ? try JSONDecoder().decode(String.self, from: Data("\"\(raw)\"".utf8)) : raw
            let depth = objects.count - 1
            guard allowed.indices.contains(depth), allowed[depth].contains(key),
                  objects[depth].insert(key).inserted else { throw CocoaError(.fileReadCorruptFile) }
        }
    }

    private static func validText(_ text: String, limit: Int) -> Bool {
        !text.isEmpty && text.utf8.count <= limit &&
        text == text.trimmingCharacters(in: .whitespacesAndNewlines) &&
        text.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil
    }
}

struct CountryOverview: Codable, Hashable, Sendable {
    let text: String
    let sourceName: String
    let sourceURL: URL
}

struct Country: Codable, Identifiable, Hashable, Sendable {
    /// ISO 3166-1 alpha-2, uppercase. The catalog covers UN members and observers.
    let id: String
    let name: String
    let capital: String
    let region: String
    let latitude: Double
    let longitude: Double
    let introduction: CountryOverview?

    let population2025: Int?
    let unPopulationLocation: Int?

    var overview: String { introduction?.text ?? "A historical overview is unavailable." }
    var overviewSourceName: String { introduction?.sourceName ?? "Country history" }
    var overviewSourceURL: URL { introduction?.sourceURL ?? URL(string: "https://www.un.org/en/about-us/member-states")! }

    var populationLabel: String? {
        guard let population2025, population2025 > 0, unPopulationLocation != nil else { return nil }
        let count = population2025.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
        return "Population: \(count) · 2025 UN projection"
    }

    var populationSourceURL: URL {
        guard let unPopulationLocation else { return URL(string: "https://population.un.org/wpp/")! }
        // UNdata uses time key 76 for 2025 and variant 2 for its medium projection.
        return URL(string: "https://data.un.org/Data.aspx?d=PopDiv&f=variableID%3A12%3BcrID%3A\(unPopulationLocation)%3BvarID%3A2%3BtimeID%3A76")!
    }
    var historicalFacts: [HistoricalFact] { CountryRepository.historicalFacts[id, default: []] }

    var flag: String {
        String(String.UnicodeScalarView(id.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value)
        }))
    }
}

/// Geographic data is adapted from mledoze/countries, licensed ODbL 1.0.
/// Coordinates are approximate country centers, not borders or capital coordinates.
enum CountryRepository {
    static let countries: [Country] = {
        let result: [Country] = readResource("countries")
        precondition(result.count == 195, "The bundled country catalog must contain 195 entries.")
        precondition(Set(result.map(\.id)).count == result.count, "Country IDs must be unique.")
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    static let factLimit = 5

    static let bundledFacts: FactCatalogSnapshot? = {
        guard let url = Bundle.main.url(forResource: "historical-facts", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? FactCatalogSnapshot.validated(data, countryIDs: Set(countries.map(\.id)))
    }()

    static var historicalFacts: [String: [HistoricalFact]] { bundledFacts?.countries ?? [:] }

    static func country(id: String) -> Country? {
        countries.first { $0.id == id.uppercased() }
    }

    static func random(excluding id: String? = nil) -> Country {
        let eligible = countries.filter { $0.id != id?.uppercased() }
        // The shipped catalog has 195 entries, so excluding one can never empty it.
        return eligible.randomElement() ?? countries[0]
    }

    private static func readResource<T: Decodable>(_ name: String) -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            preconditionFailure("Missing bundled resource: \(name).json")
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            preconditionFailure("Invalid bundled resource \(name).json: \(error)")
        }
    }
}

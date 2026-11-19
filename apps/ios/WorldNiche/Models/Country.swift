import Foundation

struct HistoricalFact: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let body: String
    let sourceName: String
    let sourceURL: URL
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

    var overview: String { introduction?.text ?? "\(name) is in \(region)." }
    var overviewSourceName: String { introduction?.sourceName ?? "Country geography" }
    var overviewSourceURL: URL { introduction?.sourceURL ?? URL(string: "https://github.com/mledoze/countries")! }
    var historicalFact: HistoricalFact? { CountryRepository.historicalFacts[id] }

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

    static let historicalFacts: [String: HistoricalFact] = {
        guard let url = Bundle.main.url(forResource: "historical-facts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let facts = try? JSONDecoder().decode([String: HistoricalFact].self, from: data) else { return [:] }
        return facts.filter { code, fact in
            fact.id.hasPrefix(code.lowercased() + "-") && !fact.title.isEmpty &&
            !fact.body.isEmpty && !fact.sourceName.isEmpty &&
            fact.sourceURL.scheme == "https" && fact.sourceURL.host != nil
        }
    }()

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

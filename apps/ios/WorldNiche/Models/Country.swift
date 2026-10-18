import Foundation

struct CultureInsight: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let body: String
    let conversationStarter: String
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

    var flag: String {
        String(String.UnicodeScalarView(id.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value)
        }))
    }

    /// Editorial coverage is deliberately separate from geographic coverage.
    var insights: [CultureInsight] { CountryRepository.insightsByCountry[id, default: []] }
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

    static let insightsByCountry: [String: [CultureInsight]] = readResource("insights")

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

import Foundation

@main
struct CountryReadingChecks {
    @MainActor
    static func main() async throws {
        let countries = CountryRepository.countries
        guard let catalog = CountryRepository.bundledFacts else {
            preconditionFailure("The packaged fact catalog failed validation")
        }
        let published = catalog.countries.values.flatMap { $0 }
        precondition(catalog.countries.values.allSatisfy { $0.count == 2 } && published.count == 390,
                     "The launch catalog contains two researched stories for each of 195 countries")

        let populationIDs = countries.compactMap(\.unPopulationLocation)
        precondition(Set(populationIDs).count == countries.count)
        for country in countries {
            guard let intro = country.introduction else { preconditionFailure("Missing history for \(country.id)") }
            let sentences = intro.text.components(separatedBy: ". ").count
            precondition((1...2).contains(sentences) && intro.text.hasSuffix("."), "\(country.id) history length")
            precondition(!intro.text.isEmpty && !intro.sourceName.isEmpty && intro.sourceURL.scheme == "https" &&
                         intro.sourceURL.host != nil && !intro.sourceURL.path.isEmpty && intro.sourceURL.path != "/")
            precondition((country.population2025 ?? 0) > 0 && country.populationLabel?.contains("2025 UN projection") == true)
            let source = country.populationSourceURL
            precondition(source.host == "data.un.org" && source.absoluteString.contains("crID%3A\(country.unPopulationLocation!)%3B") &&
                         source.absoluteString.contains("timeID%3A76"), "Wrong population source for \(country.id)")
        }
        precondition(CountryRepository.country(id: "MA")?.population2025 == 38_430_770)
        precondition(CountryRepository.country(id: "JP")?.population2025 == 123_103_479)
        precondition(CountryRepository.country(id: "VA")?.population2025 == 501)
        try await FactPublicationChecks.run(bundled: catalog)
        print("Verified \(countries.count) sourced histories and population projections, \(published.count) sourced facts, and remote/offline catalog updates.")
    }
}

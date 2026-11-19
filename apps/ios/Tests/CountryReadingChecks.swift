import Foundation

@main
struct CountryReadingChecks {
    static func main() {
        let countries = CountryRepository.countries
        let facts = CountryRepository.historicalFacts
        precondition(Set(countries.map(\.id)) == Set(facts.keys), "Each destination needs a historical fact")
        precondition(Set(facts.values.map(\.id)).count == countries.count, "Repeated historical fact ID")
        precondition(Set(facts.values.map(\.body)).count == countries.count, "Repeated historical fact text")

        for country in countries {
            guard let intro = country.introduction, let fact = country.historicalFact else {
                preconditionFailure("Missing packaged reading for \(country.id)")
            }
            let sentences = intro.text.components(separatedBy: ". ").count
            precondition((1...2).contains(sentences) && intro.text.hasSuffix("."), "\(country.id) overview length")
            precondition(!intro.text.isEmpty && !fact.title.isEmpty && !fact.body.isEmpty)
            for (publisher, url) in [(intro.sourceName, intro.sourceURL), (fact.sourceName, fact.sourceURL)] {
                precondition(!publisher.isEmpty && url.scheme == "https" && url.host != nil &&
                             !url.path.isEmpty && url.path != "/", "\(country.id) needs an item-level source")
            }
        }
        print("Verified \(countries.count) country overviews and historical facts with source links.")
    }
}

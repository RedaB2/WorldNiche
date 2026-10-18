import Foundation
import Observation

@MainActor @Observable
final class DiscoveryJournal {
    private(set) var savedIDs: Set<String>
    private(set) var visitedIDs: [String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        savedIDs = Set(defaults.stringArray(forKey: "niche.saved") ?? [])
        visitedIDs = defaults.stringArray(forKey: "niche.visited") ?? []
    }

    func toggleSaved(_ country: Country) {
        if savedIDs.contains(country.id) { savedIDs.remove(country.id) }
        else { savedIDs.insert(country.id) }
        defaults.set(Array(savedIDs).sorted(), forKey: "niche.saved")
    }

    func clear() {
        savedIDs = []
        visitedIDs = []
        defaults.removeObject(forKey: "niche.saved")
        defaults.removeObject(forKey: "niche.visited")
    }

    func mergeExplored(_ ids: [String]) {
        let valid = ids.filter { CountryRepository.country(id: $0) != nil && !visitedIDs.contains($0) }
        guard !valid.isEmpty else { return }
        visitedIDs.append(contentsOf: Set(valid).sorted())
        defaults.set(visitedIDs, forKey: "niche.visited")
    }

    func visit(_ country: Country) {
        visitedIDs.removeAll { $0 == country.id }
        visitedIDs.insert(country.id, at: 0)
        defaults.set(visitedIDs, forKey: "niche.visited")
    }
}

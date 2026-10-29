import Foundation
import Observation

struct JournalEntry: Codable, Identifiable, Equatable, Sendable {
    var countryId: String
    var saved = false
    var note = ""
    var firstExploredAt: TimeInterval?
    var lastExploredAt: TimeInterval?
    var savedUpdatedAt: TimeInterval?
    var noteUpdatedAt: TimeInterval?
    var updatedAt: TimeInterval?
    var id: String { countryId }
}

struct JournalChange: Codable, Equatable, Sendable {
    let countryId: String
    let field: String
    let sequence: Int64
    var saved: Bool?
    var note: String?
    var firstExploredAt: TimeInterval?
    var lastExploredAt: TimeInterval?
    var key: String { "\(countryId).\(field)" }
}

struct JournalSnapshot: Codable, Sendable {
    var deviceId = UUID()
    var sequence: Int64 = 0
    var entries: [String: JournalEntry] = [:]
    var pending: [String: JournalChange] = [:]
}

struct JournalSyncResult: Decodable, Sendable { let entries: [JournalEntry] }

@MainActor @Observable
final class DiscoveryJournal {
    static let noteLimit = 4000
    private(set) var snapshot: JournalSnapshot
    private(set) var revision = UUID()
    private let defaults: UserDefaults
    private static let key = "niche.journal.v2"

    var savedIDs: Set<String> { Set(snapshot.entries.values.filter(\.saved).map(\.countryId)) }
    var visitedIDs: [String] {
        snapshot.entries.values.filter { $0.lastExploredAt != nil }
            .sorted { ($0.lastExploredAt ?? 0) == ($1.lastExploredAt ?? 0) ? $0.countryId < $1.countryId : ($0.lastExploredAt ?? 0) > ($1.lastExploredAt ?? 0) }
            .map(\.countryId)
    }
    var pendingChanges: [JournalChange] { snapshot.pending.values.sorted { $0.sequence < $1.sequence } }
    var hasPendingChanges: Bool { !snapshot.pending.isEmpty }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snapshot = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(JournalSnapshot.self, from: $0) } ?? JournalSnapshot()
        if defaults.data(forKey: Self.key) == nil {
            restoreLegacy(saved: defaults.stringArray(forKey: "niche.saved") ?? [], explored: defaults.stringArray(forKey: "niche.visited") ?? [])
        }
    }

    func entry(for id: String) -> JournalEntry? { snapshot.entries[id] }
    func note(for id: String) -> String { snapshot.entries[id]?.note ?? "" }

    func toggleSaved(_ country: Country) {
        var entry = snapshot.entries[country.id] ?? JournalEntry(countryId: country.id)
        entry.saved.toggle()
        entry.savedUpdatedAt = Date().timeIntervalSince1970
        snapshot.entries[country.id] = entry
        queue(JournalChange(countryId: country.id, field: "saved", sequence: nextSequence(), saved: entry.saved))
    }

    func saveNote(_ text: String, for country: Country) {
        let text = String(String.UnicodeScalarView(text.unicodeScalars.prefix(Self.noteLimit)))
        guard note(for: country.id) != text else { return }
        var entry = snapshot.entries[country.id] ?? JournalEntry(countryId: country.id)
        entry.note = text
        entry.noteUpdatedAt = Date().timeIntervalSince1970
        snapshot.entries[country.id] = entry
        queue(JournalChange(countryId: country.id, field: "note", sequence: nextSequence(), note: text))
    }

    func visit(_ country: Country, now: Date = Date()) {
        var entry = snapshot.entries[country.id] ?? JournalEntry(countryId: country.id)
        // Reopening a sheet or refreshing feeds is not another exploration.
        if let last = entry.lastExploredAt, now.timeIntervalSince1970 - last < 60 { return }
        entry.firstExploredAt = entry.firstExploredAt ?? now.timeIntervalSince1970
        entry.lastExploredAt = now.timeIntervalSince1970
        snapshot.entries[country.id] = entry
        queue(JournalChange(countryId: country.id, field: "explored", sequence: nextSequence(),
                            firstExploredAt: entry.firstExploredAt, lastExploredAt: entry.lastExploredAt))
    }

    func mergeExplored(_ ids: [String]) {
        for id in ids where snapshot.entries[id]?.lastExploredAt == nil {
            if let country = CountryRepository.country(id: id) { visit(country) }
        }
    }

    func apply(_ remote: [JournalEntry], acknowledging sent: [JournalChange]) {
        for change in sent where snapshot.pending[change.key]?.sequence == change.sequence {
            snapshot.pending.removeValue(forKey: change.key)
        }
        for var entry in remote where CountryRepository.country(id: entry.countryId) != nil {
            if let local = snapshot.entries[entry.countryId] {
                if snapshot.pending["\(entry.countryId).saved"] != nil { entry.saved = local.saved; entry.savedUpdatedAt = local.savedUpdatedAt }
                if snapshot.pending["\(entry.countryId).note"] != nil { entry.note = local.note; entry.noteUpdatedAt = local.noteUpdatedAt }
                if snapshot.pending["\(entry.countryId).explored"] != nil {
                    entry.firstExploredAt = [entry.firstExploredAt, local.firstExploredAt].compactMap { $0 }.min()
                    entry.lastExploredAt = [entry.lastExploredAt, local.lastExploredAt].compactMap { $0 }.max()
                }
            }
            snapshot.entries[entry.countryId] = entry
        }
        persist()
    }

    func restore(_ value: JournalSnapshot) {
        snapshot = value
        revision = UUID()
        persist()
    }

    func restoreLegacy(saved: [String], explored: [String]) {
        for id in saved where !savedIDs.contains(id) {
            if let country = CountryRepository.country(id: id) { toggleSaved(country) }
        }
        for (offset, id) in explored.enumerated() {
            if let country = CountryRepository.country(id: id) { visit(country, now: Date().addingTimeInterval(-Double(offset))) }
        }
    }

    func clear() {
        snapshot = JournalSnapshot()
        revision = UUID()
        defaults.removeObject(forKey: "niche.saved")
        defaults.removeObject(forKey: "niche.visited")
        persist()
    }

    private func nextSequence() -> Int64 { snapshot.sequence += 1; return snapshot.sequence }
    private func queue(_ change: JournalChange) {
        snapshot.pending[change.key] = change
        revision = UUID()
        persist()
    }
    private func persist() { defaults.set(try? JSONEncoder().encode(snapshot), forKey: Self.key) }
}

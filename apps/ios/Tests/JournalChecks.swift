import Foundation

@main struct JournalChecks {
    @MainActor static func main() {
        let suite = "worldniche-journal-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var checks = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        let morocco = CountryRepository.country(id: "MA")!
        let france = CountryRepository.country(id: "FR")!
        defaults.set(["MA"], forKey: "niche.saved")
        defaults.set(["FR", "MA", "INVALID"], forKey: "niche.visited")
        let journal = DiscoveryJournal(defaults: defaults)
        check(journal.savedIDs == ["MA"], "Legacy saves migrate")
        check(journal.visitedIDs == ["FR", "MA"], "Legacy recent order and country validation survive")
        check(journal.pendingChanges.count == 3, "Migrated fields await cloud sync")
        let copy = DiscoveryJournal(defaults: defaults)
        check(copy.snapshot.deviceId == journal.snapshot.deviceId, "Retry device identity persists")
        check(copy.pendingChanges == journal.pendingChanges, "Offline changes survive relaunch")
        journal.clear()
        journal.toggleSaved(morocco)
        check(journal.visitedIDs.isEmpty, "Saving does not invent an exploration")
        journal.saveNote("Remember the music at the cafe", for: morocco)
        check(journal.note(for: "MA").contains("cafe"), "Note saves immediately")
        let old = journal.pendingChanges
        journal.saveNote("A newer note", for: morocco)
        journal.apply([JournalEntry(countryId: "MA", saved: true, note: "Remember the music at the cafe")], acknowledging: old)
        check(journal.note(for: "MA") == "A newer note", "An older response cannot replace an edit made during sync")
        check(journal.pendingChanges.count == 1 && journal.pendingChanges.first?.field == "note", "Only acknowledged field revisions are cleared")
        let latest = journal.pendingChanges
        journal.apply([JournalEntry(countryId: "MA", saved: true, note: "A newer note")], acknowledging: latest)
        check(!journal.hasPendingChanges, "Successful sync clears the queue")
        journal.apply([JournalEntry(countryId: "MA", saved: false, note: "From another device")], acknowledging: [])
        check(journal.savedIDs.isEmpty && journal.note(for: "MA") == "From another device", "Other-device unsaves and note edits restore")
        journal.saveNote("", for: morocco)
        check(journal.pendingChanges.first?.note == "", "Erasing a note syncs an explicit empty string")
        journal.saveNote(String(repeating: "a", count: 4100), for: morocco)
        check(journal.note(for: "MA").count == 4000, "Notes have a client bound")
        journal.saveNote(String(repeating: "👩🏽‍💻", count: 4000), for: morocco)
        check(journal.note(for: "MA").unicodeScalars.count == 4000, "Unicode notes obey the same bound as PostgreSQL")
        journal.saveNote(String(repeating: "a", count: 4000), for: morocco)
        let first = Date(timeIntervalSince1970: 1_790_000_000)
        journal.visit(france, now: first)
        let seq = journal.snapshot.sequence
        journal.visit(france, now: first.addingTimeInterval(1))
        check(journal.snapshot.sequence == seq, "Repeated view rendering does not create writes")
        journal.visit(france, now: first.addingTimeInterval(120))
        check(journal.entry(for: "FR")?.firstExploredAt == first.timeIntervalSince1970, "First exploration stays unchanged")
        check(journal.entry(for: "FR")?.lastExploredAt == first.timeIntervalSince1970 + 120, "Recent exploration advances")
        let preserved = journal.snapshot
        journal.clear()
        check(journal.snapshot.entries.isEmpty && journal.pendingChanges.isEmpty, "Clear removes notes and pending writes")
        journal.restore(preserved)
        check(journal.note(for: "MA").count == 4000 && journal.visitedIDs == ["FR"], "Account workspace restores notes and history")
        check(DiscoveryJournal(defaults: defaults).snapshot.entries == journal.snapshot.entries, "Restored workspace survives restart")
        journal.apply([JournalEntry(countryId: "NOT_A_COUNTRY", saved: true, note: "bad")], acknowledging: [])
        check(!journal.savedIDs.contains("NOT_A_COUNTRY"), "Unknown remote countries are ignored")
        print("\(checks) journal checks passed")
    }
}

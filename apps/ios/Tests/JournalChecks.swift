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
        journal.clear()
        check(!journal.completeExploration(morocco), "Opening a country cannot complete exploration")
        var reading = CountryReadingProgress()
        reading.record(CountryReadingProgress.scrollFraction(offset: 76, contentHeight: 1500, viewportHeight: 500, topInset: 24))
        journal.saveReadingProgress(reading, for: morocco)
        check(reading.fraction == 0.1 && !reading.isReady, "Scroll percentage accounts for the viewport and top inset")
        check(journal.visitedIDs.isEmpty && !journal.hasPendingChanges, "Reading does not publish exploration or queue cloud writes")
        check(DiscoveryJournal(defaults: defaults).readingProgress(for: "MA") == reading, "Partial reading survives a relaunch")
        let partial = reading
        reading.record(0.04)
        check(reading == partial, "Scrolling backward never reduces progress")
        reading.record(0.1)
        check(reading == partial, "Revisiting the same position does not inflate progress")
        reading.record(0.173456)
        check(reading.fraction == 0.173456, "Progress advances continuously without section or band steps")
        journal.saveReadingProgress(reading, for: morocco)
        journal.saveReadingProgress(partial, for: morocco)
        check(journal.readingProgress(for: "MA") == reading, "A stale save cannot reduce persisted progress")
        reading.record(.nan)
        reading.record(.infinity)
        check(reading.fraction == 0.173456, "Invalid geometry cannot corrupt progress")
        check(CountryReadingProgress.scrollFraction(offset: -24, contentHeight: 1500, viewportHeight: 500, topInset: 24) == 0,
              "The initial card position starts at zero")
        check(CountryReadingProgress.scrollFraction(offset: 0, contentHeight: 400, viewportHeight: 500, topInset: 0) == 0,
              "A layout without scroll travel does not complete automatically")
        reading.record(CountryReadingProgress.scrollFraction(offset: 975.5, contentHeight: 1500, viewportHeight: 500, topInset: 24))
        check(reading.isReady && reading.fraction == 1, "Reaching the bottom unlocks confirmation with fractional layout tolerance")
        reading.record(1.2)
        check(reading.fraction == 1, "Bottom overscroll cannot exceed 100 percent")
        journal.saveReadingProgress(reading, for: morocco)
        check(journal.visitedIDs.isEmpty, "Even full reading requires intentional confirmation")
        journal.apply([JournalEntry(countryId: "MA", note: "Synced note")], acknowledging: [])
        check(journal.readingProgress(for: "MA") == reading, "Cloud journal responses preserve local reading progress")
        check(journal.completeExploration(morocco), "Confirmation marks the country explored")
        let completedEntry = journal.entry(for: "MA")
        let completionSequence = journal.snapshot.sequence
        check(!journal.completeExploration(morocco), "Repeated completion is idempotent")
        check(journal.snapshot.sequence == completionSequence && journal.entry(for: "MA") == completedEntry,
              "Reopening a completed country does not advance its dates or queue another write")
        let readingWorkspace = journal.snapshot
        journal.clear()
        check(journal.readingProgress(for: "MA").fraction == 0, "Clearing an account clears reading progress")
        journal.restore(readingWorkspace)
        check(journal.readingProgress(for: "MA").isReady, "Restoring an account restores its reading progress")
        let oldJSON = #"{"deviceId":"11111111-1111-4111-8111-111111111111","sequence":0,"entries":{},"pending":{}}"#.data(using: .utf8)!
        let oldSnapshot = try! JSONDecoder().decode(JournalSnapshot.self, from: oldJSON)
        check(oldSnapshot.readingProgress == nil && oldSnapshot.factRotations == nil && oldSnapshot.entries.isEmpty,
              "Older journals decode without progress or rotation state")
        journal.clear()
        let facts = morocco.historicalFacts
        check((2...CountryRepository.factLimit).contains(facts.count), "Morocco has enough reviewed facts to rotate")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23, minute: 59))!
        let morning = evening.addingTimeInterval(120)
        for country in CountryRepository.countries {
            let ids = country.historicalFacts.map(\.id)
            var rotation = FactRotation()
            for index in ids.indices {
                rotation.select(from: ids, advance: index > 0, now: evening, calendar: calendar)
                precondition(rotation.seenIDs == Array(ids.prefix(index + 1)), country.id)
            }
            rotation.select(from: ids, advance: true, now: evening, calendar: calendar)
            precondition(rotation.seenIDs == [ids[0]], country.id)
        }
        journal.selectFact(for: morocco, from: facts, now: evening, calendar: calendar)
        let initial = journal.snapshot.factRotations
        journal.selectFact(for: morocco, from: facts, now: evening.addingTimeInterval(30), calendar: calendar)
        check(journal.snapshot.factRotations == initial && journal.displayedFact(for: morocco, from: facts) == facts[0],
              "Reopening the same day retains the selected fact")
        journal.selectFact(for: morocco, from: facts, now: morning, calendar: calendar)
        check(journal.displayedFact(for: morocco, from: facts) == facts[1], "The first opening on a new local date picks the next fact")
        let restoredJournal = DiscoveryJournal(defaults: defaults)
        check(restoredJournal.displayedFact(for: morocco, from: facts) == facts[1], "The current fact survives relaunch")
        var seen = Set([facts[0].id, facts[1].id])
        for _ in 2..<facts.count {
            journal.selectFact(for: morocco, from: facts, advance: true, now: morning, calendar: calendar)
            check(seen.insert(journal.displayedFact(for: morocco, from: facts)!.id).inserted, "Only unseen entries appear before exhaustion")
        }
        journal.selectFact(for: morocco, from: facts, advance: true, now: morning, calendar: calendar)
        check(journal.displayedFact(for: morocco, from: facts) == facts[0], "A manual request after exhaustion starts a fresh cycle")
        journal.selectFact(for: france, from: france.historicalFacts, now: morning, calendar: calendar)
        check(journal.displayedFact(for: morocco, from: facts) == facts[0], "Each country retains its own cycle")
        check(journal.visitedIDs.isEmpty && journal.savedIDs.isEmpty && journal.pendingChanges.isEmpty,
              "Rotating facts never queues an exploration, bookmark or social write")
        let factsWorkspace = journal.snapshot
        journal.clear()
        check(journal.snapshot.factRotations == nil, "Clearing the workspace erases seen facts")
        journal.restore(factsWorkspace)
        check(journal.snapshot.factRotations == factsWorkspace.factRotations, "Account workspace restore recovers the private selection")
        let replacement = HistoricalFact(id: "ma-reviewed-update", title: "Replacement", body: "Updated evidence.",
                                         sourceName: "Publisher", sourceURL: URL(string: "https://example.org/replacement")!)
        journal.selectFact(for: morocco, from: [replacement], now: morning, calendar: calendar)
        check(journal.displayedFact(for: morocco, from: [replacement]) == replacement &&
              journal.snapshot.factRotations?[morocco.id]?.seenIDs == [replacement.id],
              "A changed publication removes withdrawn IDs and selects a member of the new pool")
        journal.selectFact(for: morocco, from: [], now: morning, calendar: calendar)
        check(journal.displayedFact(for: morocco, from: []) == nil,
              "A complete withdrawal cannot fall back to any bundled fact")
        var change = FactRotation()
        change.select(from: ["a", "b", "c"], advance: false, now: evening, calendar: calendar)
        change.select(from: ["a", "b", "c"], advance: true, now: evening, calendar: calendar)
        change.select(from: ["a", "c", "d"], advance: false, now: evening, calendar: calendar)
        check(change.seenIDs == ["a", "c"], "Removing the displayed fact advances to an unseen eligible replacement")
        change.select(from: ["a", "c", "d"], advance: true, now: evening, calendar: calendar)
        check(change.seenIDs == ["a", "c", "d"], "Newly reviewed facts join the current cycle")
        change.select(from: ["a"], advance: true, now: morning, calendar: calendar)
        check(change.seenIDs == ["a"], "A single fact never accumulates duplicate history")
        change.select(from: [], advance: true, now: morning, calendar: calendar)
        check(change.seenIDs.isEmpty && change.selectedDay == nil, "An empty collection clears its obsolete selection")
        var full = FactRotation()
        let five = ["a", "b", "c", "d", "e"]
        for _ in 0..<2 {
            for (index, id) in five.enumerated() {
                full.select(from: five, advance: true, now: morning, calendar: calendar)
                check(full.seenIDs.last == id && full.seenIDs == Array(five.prefix(index + 1)),
                      "Two full five-fact cycles visit all five approved IDs in order without repeats")
            }
        }
        full.select(from: [], advance: false, now: morning, calendar: calendar)
        full.select(from: ["new"], advance: false, now: morning, calendar: calendar)
        check(full.seenIDs == ["new"], "Republishing after a complete withdrawal begins with only approved IDs")
        print("\(checks) journal checks passed")
    }
}

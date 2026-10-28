import Foundation

@main
struct IntroChecks {
    static func main() {
        let suite = "worldniche-intro-checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let progress = IntroProgress(defaults: defaults)
        var checks = 0
        func expect(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }
        expect(!progress.isCompleted, "Fresh installations have not completed the intro")
        expect(progress.shouldPresent(hasProfile: false, hasJournal: false, hasInvitation: false), "A fresh guest sees the intro")
        expect(!progress.shouldPresent(hasProfile: true, hasJournal: false, hasInvitation: false), "Existing profiles bypass the intro")
        expect(!progress.shouldPresent(hasProfile: false, hasJournal: true, hasInvitation: false), "Existing exploration bypasses the intro")
        expect(!progress.shouldPresent(hasProfile: false, hasJournal: false, hasInvitation: true), "Invitations take priority over the intro")
        expect(!progress.isCompleted, "Checking eligibility does not persist a user choice")
        defaults.set(false, forKey: "existing-sharing-choice")
        defaults.set(["MA"], forKey: "niche.visited")
        progress.complete()
        expect(progress.isCompleted, "Skipping or finishing remembers completion")
        let restored = IntroProgress(defaults: defaults)
        expect(!restored.shouldPresent(hasProfile: false, hasJournal: false, hasInvitation: false), "Completion survives relaunch without requiring a profile")
        expect(defaults.stringArray(forKey: "niche.visited") == ["MA"], "Intro completion preserves exploration")
        expect(defaults.object(forKey: "existing-sharing-choice") as? Bool == false, "Intro completion preserves a privacy choice")
        restored.prepareFirstAppearance()
        expect(restored.isCompleted, "Normal appearance does not reset completion")
        defaults.removeObject(forKey: "niche.visited")
        expect(!restored.shouldPresent(hasProfile: false, hasJournal: false, hasInvitation: false), "Clearing exploration does not repeat onboarding")
        print("\(checks) intro checks passed")
    }
}

import Foundation

struct IntroProgress {
    static let completionKey = "niche.introCompleted.v1"
    private let defaults: UserDefaults
    var skipsPresentation = false
    var ignoresExistingActivity = false
    private var resetsCompletionOnFirstAppearance = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isCompleted: Bool { defaults.bool(forKey: Self.completionKey) }

    func shouldPresent(hasProfile: Bool, hasJournal: Bool, hasInvitation: Bool) -> Bool {
        guard !skipsPresentation, !isCompleted, !hasInvitation else { return false }
        return ignoresExistingActivity || (!hasProfile && !hasJournal)
    }

    func complete() {
        defaults.set(true, forKey: Self.completionKey)
    }

    func prepareFirstAppearance() {
        if resetsCompletionOnFirstAppearance { defaults.removeObject(forKey: Self.completionKey) }
    }

    static func appProgress(arguments: [String] = ProcessInfo.processInfo.arguments) -> IntroProgress {
        var progress = IntroProgress()
        #if DEBUG && targetEnvironment(simulator)
        if let index = arguments.firstIndex(of: "-worldniche-intro-fixture"), arguments.indices.contains(index + 1),
           ["fresh", "resume"].contains(arguments[index + 1]),
           let defaults = UserDefaults(suiteName: "io.worldniche.app.intro-ui-fixture") {
            let mode = arguments[index + 1]
            progress = IntroProgress(defaults: defaults)
            progress.ignoresExistingActivity = true
            progress.resetsCompletionOnFirstAppearance = mode != "resume"
        }
        progress.skipsPresentation = arguments.contains("-worldniche-skip-intro")
        #endif
        return progress
    }
}

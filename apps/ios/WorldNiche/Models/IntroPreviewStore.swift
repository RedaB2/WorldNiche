import Foundation
import Observation

enum IntroPreviewCategory: String, CaseIterable, Sendable {
    case overview, history, music
}

struct IntroAccordionState: Equatable, Sendable {
    private(set) var expanded: IntroPreviewCategory?

    mutating func toggle(_ category: IntroPreviewCategory) {
        expanded = expanded == category ? nil : category
    }
}

@MainActor
@Observable
final class IntroPreviewStore {
    private(set) var accordion = IntroAccordionState()
    private(set) var tracks: [MusicTrack] = []
    private(set) var musicLoading = false
    private(set) var musicUnavailable = false
    private(set) var musicFetchedAt: Date?

    private let feedService: DiscoveryFeedService
    private var musicTask: Task<Void, Never>?
    private var musicRequest = UUID()
    private var fixtureMode: String?
    private var musicAttempts = 0

    init(feedService: DiscoveryFeedService = DiscoveryFeedService(),
         arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.feedService = feedService
        #if DEBUG && targetEnvironment(simulator)
        if let index = arguments.firstIndex(of: "-worldniche-intro-previews-fixture"),
           arguments.indices.contains(index + 1), ["ready", "music-retry"].contains(arguments[index + 1]) {
            fixtureMode = arguments[index + 1]
        }
        #endif
    }

    var expanded: IntroPreviewCategory? { accordion.expanded }

    func toggle(_ category: IntroPreviewCategory) {
        accordion.toggle(category)
        if accordion.expanded == .music { loadMusic() }
    }

    func retryMusic() { loadMusic(forceRefresh: true) }

    func cancelLoading() {
        musicRequest = UUID()
        musicTask?.cancel()
        musicTask = nil
        musicLoading = false
    }

    private func loadMusic(forceRefresh: Bool = false) {
        guard !musicLoading else { return }
        guard forceRefresh || musicFetchedAt == nil || isExpired(musicFetchedAt) else { return }
        musicLoading = true
        musicUnavailable = false
        musicAttempts += 1
        let request = UUID()
        musicRequest = request
        musicTask = Task { [weak self] in
            guard let self else { return }
            let result = await musicSnapshot(forceRefresh: forceRefresh)
            guard !Task.isCancelled, musicRequest == request else { return }
            tracks = Array(result.items.prefix(5))
            musicFetchedAt = result.fetchedAt
            musicUnavailable = tracks.isEmpty
            musicLoading = false
            musicTask = nil
        }
    }

    private func isExpired(_ date: Date?) -> Bool {
        guard let date else { return true }
        return Date().timeIntervalSince(date) >= 15 * 60
    }

    private func musicSnapshot(forceRefresh: Bool) async -> FeedSnapshot<MusicTrack> {
        #if DEBUG && targetEnvironment(simulator)
        if let fixtureMode {
            return Self.musicFixture(fails: fixtureMode == "music-retry" && musicAttempts == 1)
        }
        #endif
        guard let country = CountryRepository.country(id: "US") else {
            return FeedSnapshot(items: [], fetchedAt: Date(), unavailable: "Unavailable")
        }
        return await feedService.fetchMusic(for: country, forceRefresh: forceRefresh)
    }

    #if DEBUG && targetEnvironment(simulator)
    private static func musicFixture(fails: Bool) -> FeedSnapshot<MusicTrack> {
        let titles = ["A Little Sunshine", "The Long Way Home", "Night Windows", "Good Company", "Open Roads"]
        let items = fails ? [] : titles.enumerated().map { index, title in
            MusicTrack(id: "intro-track-\(index)", title: title, artist: "Preview Artist \(index + 1)",
                       artworkURL: nil, url: URL(string: "https://music.apple.com/us/browse")!)
        }
        return FeedSnapshot(items: items, fetchedAt: Date(), unavailable: fails ? "Unavailable" : nil)
    }
    #endif
}

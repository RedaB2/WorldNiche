#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Synthetic, offline content for exploration UI checks and review recordings.
@MainActor
enum CountryReadingFixture {
    static var mode: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-worldniche-reading-fixture"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    static func music() -> FeedSnapshot<MusicTrack> {
        let tracks = mode == "unavailable" ? [] : ["Morning Light", "The Long Way Home", "Night Windows", "Good Company", "Open Roads"].enumerated().map {
            MusicTrack(id: "reading-track-\($0.offset)", title: $0.element, artist: "Preview Artist \($0.offset + 1)",
                artworkURL: nil, url: URL(string: "https://music.apple.com/browse")!)
        }
        return FeedSnapshot(items: tracks, fetchedAt: Date(), unavailable: tracks.isEmpty ? "The local chart is taking a break. Try again later." : nil)
    }

    static func news() -> FeedSnapshot<NewsStory> {
        let stories = mode == "unavailable" ? [] : [
            "A neighborhood festival brings generations together",
            "The community keeping an everyday tradition alive",
            "A new generation finds its voice through music",
            "The small spaces where a city comes together"
        ].enumerated().map {
            NewsStory(id: "reading-news-\($0.offset)", title: $0.element, source: "Preview stories",
                url: URL(string: "https://globalvoices.org")!, publishedAt: Date(), author: "Preview contributor")
        }
        return FeedSnapshot(items: stories, fetchedAt: Date(), unavailable: stories.isEmpty ? "Headlines are unavailable right now. Try again later." : nil)
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Synthetic music responses for exploration UI checks.
@MainActor
enum CountryReadingFixture {
    static var mode: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-worldniche-reading-fixture"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    static func music() -> FeedSnapshot<MusicTrack> {
        let radio = mode == "radio"
        let tracks = mode == "unavailable" ? [] : ["Morning Light", "The Long Way Home", "Night Windows", "Good Company", "Open Roads"].enumerated().map {
            MusicTrack(id: "reading-track-\($0.offset)", title: $0.element, artist: "Preview Artist \($0.offset + 1)",
                artworkURL: nil, url: URL(string: "https://example.org/tracks/\($0.offset + 1)")!,
                provider: radio ? .tuneping : .appleMusic, radioSample: radio ? "2 plays · 1 station" : nil)
        }
        return FeedSnapshot(items: tracks, fetchedAt: Date(), unavailable: tracks.isEmpty ? "The local chart is taking a break. Try again later." : nil)
    }
}
#endif

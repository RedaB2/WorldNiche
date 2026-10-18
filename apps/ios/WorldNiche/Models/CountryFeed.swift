import Foundation

struct MusicTrack: Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
    let url: URL
}

struct NewsStory: Identifiable, Sendable {
    let id: String
    let title: String
    let source: String
    let url: URL
    let publishedAt: Date?
}

struct CountryFeed: Sendable {
    let tracks: [MusicTrack]
    let stories: [NewsStory]
    let musicFetchedAt: Date?
    let newsFetchedAt: Date?
    let musicUnavailable: String?
    let newsUnavailable: String?
}

/// One independently loaded category, including its own source retrieval time.
struct FeedSnapshot<Item: Sendable>: Sendable {
    let items: [Item]
    let fetchedAt: Date
    let unavailable: String?
}

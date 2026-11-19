import Foundation

enum MusicChartProvider: String, Sendable {
    case appleMusic = "Apple Music"
    case tuneping = "Tuneping"

    var chartDescription: String {
        switch self {
        case .appleMusic: "Most-played songs in this country’s Apple Music storefront."
        case .tuneping: "Seven-day radio chart. Plays are detected from station metadata on monitored internet radio stations in this country."
        }
    }
}

struct MusicTrack: Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
    let url: URL
    var provider: MusicChartProvider = .appleMusic
    var radioSample: String? = nil
}

struct FeedSnapshot<Item: Sendable>: Sendable {
    let items: [Item]
    let fetchedAt: Date
    let unavailable: String?
}

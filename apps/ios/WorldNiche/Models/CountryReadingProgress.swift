import Foundation
import CoreGraphics

enum CountryReadingSection: String, CaseIterable, Codable, Sendable {
    case culture, music, news

    var title: String {
        switch self {
        case .culture: "Culture"
        case .music: "Music"
        case .news: "Stories"
        }
    }
}

/// Small, device-local coverage records. Seeing content is a reading cue, not proof of comprehension.
struct CountryReadingProgress: Codable, Equatable, Sendable {
    private var coverage: [String: Set<Int>] = [:]
    static let bandCount = 20
    static let requiredBands = 18

    func fraction(for section: CountryReadingSection) -> Double {
        min(1, Double(coverage[section.rawValue, default: []].count) / Double(Self.requiredBands))
    }

    var fraction: Double {
        CountryReadingSection.allCases.reduce(0) { $0 + fraction(for: $1) } / 3
    }

    var isReady: Bool { CountryReadingSection.allCases.allSatisfy { fraction(for: $0) == 1 } }
    var nextSection: CountryReadingSection? { CountryReadingSection.allCases.first { fraction(for: $0) < 1 } }

    /// Only called after the viewport has rested. A fling cannot credit skipped content.
    mutating func record(_ section: CountryReadingSection, frame: CGRect, viewport: CGRect) {
        guard frame.height > 0, viewport.height > 0, frame.intersects(viewport) else { return }
        let visible = frame.intersection(viewport)
        for band in 0..<Self.bandCount {
            let midpoint = frame.minY + frame.height * (Double(band) + 0.5) / Double(Self.bandCount)
            if midpoint >= visible.minY && midpoint <= visible.maxY {
                coverage[section.rawValue, default: []].insert(band)
            }
        }
    }
}

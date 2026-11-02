import Foundation
import CoreGraphics

/// The furthest scroll percentage reached on this device, independent of content sections.
struct CountryReadingProgress: Codable, Equatable, Sendable {
    private(set) var fraction = 0.0
    var isReady: Bool { fraction == 1 }

    init() {}

    private enum CodingKeys: String, CodingKey { case fraction }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        record(try values.decodeIfPresent(Double.self, forKey: .fraction) ?? 0)
    }

    mutating func record(_ fraction: Double) {
        guard fraction.isFinite else { return }
        self.fraction = max(self.fraction, min(1, max(0, fraction)))
    }

    static func scrollFraction(offset: CGFloat, contentHeight: CGFloat,
                               viewportHeight: CGFloat, topInset: CGFloat) -> Double {
        let distance = contentHeight - viewportHeight
        let position = offset + topInset
        guard distance.isFinite, position.isFinite, distance > 0 else { return 0 }
        // Allow one point for fractional layout rounding at the bottom.
        if position >= distance - 1 { return 1 }
        return Double(min(1, max(0, position / distance)))
    }
}

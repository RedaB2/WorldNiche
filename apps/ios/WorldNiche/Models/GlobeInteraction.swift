import Foundation
import CoreGraphics
import simd

/// Keeps north upright while turning, including after repeated diagonal drags.
struct GlobeOrientation {
    private(set) var latitude: Double
    private(set) var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = min(85, max(-85, latitude)) * .pi / 180
        self.longitude = longitude * .pi / 180
    }

    init(quaternion: simd_quatf) {
        let center = quaternion.inverse.act(SIMD3<Float>(0, 0, 1))
        self.init(latitude: asin(Double(min(1, max(-1, center.y)))) * 180 / .pi,
                  longitude: atan2(Double(center.x), Double(center.z)) * 180 / .pi)
    }

    var quaternion: simd_quatf {
        simd_quatf(angle: Float(latitude), axis: SIMD3<Float>(1, 0, 0)) *
            simd_quatf(angle: Float(-longitude), axis: SIMD3<Float>(0, 1, 0))
    }

    func rotated(horizontal: Double, vertical: Double) -> Self {
        var result = self
        result.latitude = min(85 * .pi / 180, max(-85 * .pi / 180, latitude + vertical))
        result.longitude = (longitude - horizontal).remainder(dividingBy: 2 * .pi)
        return result
    }
}

/// Scene coordinates use a unit sphere; gestures use the circular viewport's diameter.
struct GlobeViewport {
    static let initialScale = 1.18
    static let minimumScale = initialScale / 4
    static let maximumScale = 1.65
    private(set) var scale = initialScale
    private(set) var offset = CGPoint.zero

    var zoomPercent: Int { Int((Self.initialScale / scale * 100).rounded()) }

    mutating func zoom(by magnification: Double, around point: CGPoint, in size: CGSize) {
        let diameter = min(size.width, size.height)
        guard magnification.isFinite, magnification > 0, diameter > 0 else { return }
        let previous = scale
        scale = min(Self.maximumScale, max(Self.minimumScale, scale / magnification))
        // Keep the place between the fingers stationary as it grows.
        offset.x += (point.x - size.width / 2) * 2 / diameter * (scale - previous)
        offset.y -= (point.y - size.height / 2) * 2 / diameter * (scale - previous)
        constrainOffset()
    }

    mutating func move(by translation: CGPoint, in size: CGSize) {
        let diameter = min(size.width, size.height)
        guard diameter > 0, translation.x.isFinite, translation.y.isFinite else { return }
        offset.x += translation.x * 2 * scale / diameter
        offset.y -= translation.y * 2 * scale / diameter
        constrainOffset()
    }

    private mutating func constrainOffset() {
        // The center of the window always intersects the globe, even after a long drag.
        let limit = max(0.25, 1 - scale * 0.6)
        let distance = hypot(offset.x, offset.y)
        if distance > limit {
            offset.x *= limit / distance
            offset.y *= limit / distance
        }
    }
}

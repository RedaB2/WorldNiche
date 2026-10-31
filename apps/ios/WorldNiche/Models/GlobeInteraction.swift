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

    /// Solve the north-upright rotation that puts a grabbed surface point under the finger.
    func following(_ anchor: SIMD3<Float>, to target: SIMD3<Float>) -> Self {
        let radius = hypot(Double(anchor.x), Double(anchor.z))
        guard radius > 0.00001 else { return self }
        let angle = asin(min(1, max(-1, Double(target.x) / radius)))
        let anchorLongitude = atan2(Double(anchor.x), Double(anchor.z))
        let targetTilt = atan2(Double(target.y), Double(target.z))
        // There are two meridians with this screen x. Choose the continuous solution.
        return [angle, .pi - angle].map { meridian in
            let tilt = atan2(Double(anchor.y), radius * cos(meridian)) - targetTilt
            return Self(latitude: tilt * 180 / .pi, longitude: (anchorLongitude - meridian) * 180 / .pi)
        }.min { a, b in
            func distance(_ value: Self) -> Double {
                pow(value.latitude - latitude, 2) + pow((value.longitude - longitude).remainder(dividingBy: 2 * .pi), 2)
            }
            return distance(a) < distance(b)
        } ?? self
    }
}

/// The sphere has radius one. Screen coordinates are measured in view points.
struct GlobeViewport {
    static let initialScale = 1.18
    static let minimumScale = initialScale / 4
    static let maximumScale = 1.65
    private(set) var scale = initialScale
    private(set) var offset = CGPoint.zero

    var zoomPercent: Int { Int((Self.initialScale / scale * 100).rounded()) }

    func scenePoint(at point: CGPoint, in size: CGSize) -> CGPoint {
        let diameter = max(1, min(size.width, size.height))
        return CGPoint(x: (point.x - size.width / 2) * 2 * scale / diameter - offset.x,
                       y: -(point.y - size.height / 2) * 2 * scale / diameter - offset.y)
    }

    func surfacePoint(at point: CGPoint, in size: CGSize, clampToEdge: Bool = false) -> SIMD3<Float>? {
        var p = scenePoint(at: point, in: size)
        let distance = hypot(p.x, p.y)
        guard distance <= 1 || clampToEdge else { return nil }
        if distance > 0.9999 { p.x *= 0.9999 / distance; p.y *= 0.9999 / distance }
        return SIMD3<Float>(Float(p.x), Float(p.y), Float(sqrt(max(0, 1 - p.x * p.x - p.y * p.y))))
    }

    mutating func zoom(by magnification: Double, around point: CGPoint, in size: CGSize) {
        transform(from: point, to: point, magnification: magnification, in: size)
    }

    mutating func move(by translation: CGPoint, in size: CGSize) {
        transform(from: .zero, to: translation, magnification: 1, in: size)
    }

    /// Apply scale and centroid movement together from one touch snapshot, not callback deltas.
    mutating func transform(from start: CGPoint, to end: CGPoint, magnification: Double, in size: CGSize) {
        let diameter = min(size.width, size.height)
        guard magnification.isFinite, magnification > 0, diameter > 0,
              start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else { return }
        let anchor = scenePoint(at: start, in: size)
        scale = min(Self.maximumScale, max(Self.minimumScale, scale / magnification))
        offset = CGPoint(x: (end.x - size.width / 2) * 2 * scale / diameter - anchor.x,
                         y: -(end.y - size.height / 2) * 2 * scale / diameter - anchor.y)
        // The center may leave the view, but a useful slice of the sphere stays reachable.
        let halfWidth = scale * size.width / diameter
        let halfHeight = scale * size.height / diameter
        let excess = CGPoint(x: max(0, abs(offset.x) - halfWidth), y: max(0, abs(offset.y) - halfHeight))
        let distance = hypot(excess.x, excess.y)
        if distance > 0.85 {
            offset.x = copysign(min(abs(offset.x), halfWidth) + excess.x * 0.85 / distance, offset.x)
            offset.y = copysign(min(abs(offset.y), halfHeight) + excess.y * 0.85 / distance, offset.y)
        }
    }

    func interpolated(to destination: Self, fraction: Double) -> Self {
        var result = self
        result.scale = exp(log(scale) + (log(destination.scale) - log(scale)) * fraction)
        result.offset = CGPoint(x: offset.x + (destination.offset.x - offset.x) * fraction,
                                y: offset.y + (destination.offset.y - offset.y) * fraction)
        return result
    }
}

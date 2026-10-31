import Foundation
import CoreGraphics
import simd

@main
struct GlobeChecks {
    static func main() {
        var checks = 0
        func expect(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }
        let size = CGSize(width: 390, height: 355)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var viewport = GlobeViewport()
        expect(viewport.zoomPercent == 100, "Starting composition is unchanged")
        viewport.zoom(by: 100, around: center, in: size)
        expect(viewport.zoomPercent == 400, "Magnification stops at four times the original view")
        viewport.zoom(by: 100, around: center, in: size)
        expect(viewport.zoomPercent == 400, "Repeated pinches cannot overshoot")
        viewport.zoom(by: 0.001, around: center, in: size)
        expect(viewport.zoomPercent == 72, "The existing zoom-out limit is preserved")
        for invalid in [Double.nan, Double.infinity, 0, -1] {
            viewport.zoom(by: invalid, around: center, in: size)
            expect(viewport.zoomPercent == 72, "Invalid input cannot corrupt the camera")
        }

        viewport = GlobeViewport()
        let anchor = CGPoint(x: center.x + 25, y: center.y - 30)
        func pointUnderFinger(_ viewport: GlobeViewport) -> CGPoint {
            CGPoint(x: (anchor.x - center.x) * 2 * viewport.scale / size.height - viewport.offset.x,
                    y: -(anchor.y - center.y) * 2 * viewport.scale / size.height - viewport.offset.y)
        }
        let before = pointUnderFinger(viewport)
        viewport.zoom(by: 1.5, around: anchor, in: size)
        let after = pointUnderFinger(viewport)
        expect(hypot(before.x - after.x, before.y - after.y) < 0.000001, "Off-center pinch preserves its geographic anchor")
        viewport.zoom(by: 1 / 1.5, around: anchor, in: size)
        expect(viewport.zoomPercent == 100 && hypot(viewport.offset.x, viewport.offset.y) < 0.000001,
               "Reversing a pinch restores the framing without drift")
        viewport.zoom(by: 3, around: center, in: size)
        viewport.move(by: CGPoint(x: 35, y: -20), in: size)
        expect(viewport.offset.x > 0 && viewport.offset.y > 0, "Two-finger movement follows both screen axes")
        expect(viewport.zoomPercent == 300, "Moving does not also zoom")
        viewport.move(by: CGPoint(x: 100_000, y: -100_000), in: size)
        expect(hypot(viewport.offset.x, viewport.offset.y) < 1, "A long diagonal pan cannot lose the globe")
        viewport.zoom(by: 0.001, around: center, in: size)
        expect(hypot(viewport.offset.x, viewport.offset.y) <= 0.250001, "Zooming back out constrains an old pan")
        viewport = GlobeViewport()
        expect(viewport.offset == .zero && viewport.zoomPercent == 100, "Reset restores the original camera")
        viewport.move(by: CGPoint(x: 20, y: 20), in: .zero)
        viewport.zoom(by: 2, around: .zero, in: .zero)
        expect(viewport.offset == .zero && viewport.zoomPercent == 100, "A transient zero-sized layout is safe")

        var orientation = GlobeOrientation(latitude: 32, longitude: -5)
        for step in 0..<2_000 {
            orientation = orientation.rotated(horizontal: 0.2, vertical: step % 2 == 0 ? 0.1 : -0.1)
            let north = orientation.quaternion.act(SIMD3<Float>(0, 1, 0))
            expect(abs(north.x) < 0.00001 && north.y > 0, "Repeated diagonal drags cannot roll north sideways or upside-down")
        }
        orientation = orientation.rotated(horizontal: 100_000, vertical: 100_000)
        expect(abs(orientation.latitude - 85 * .pi / 180) < 0.000001, "Dragging across the pole cannot flip the globe")
        expect(abs(orientation.longitude) <= .pi, "Repeated revolutions retain numerical precision")
        let restored = GlobeOrientation(quaternion: orientation.quaternion)
        expect(abs(simd_dot(restored.quaternion.vector, orientation.quaternion.vector)) > 0.99999,
               "Interrupting animation resumes at the visible orientation")
        let near = GlobeOrientation(latitude: 46, longitude: 2)
        let slowTurn = near.rotated(horizontal: 10 * GlobeViewport.minimumScale * 2 / 355, vertical: 0)
        let normalTurn = near.rotated(horizontal: 10 * GlobeViewport.initialScale * 2 / 355, vertical: 0)
        expect(abs(slowTurn.longitude - near.longitude) < abs(normalTurn.longitude - near.longitude),
               "Zoomed rotation is finer for small countries")
        print("\(checks) globe checks passed")
    }
}

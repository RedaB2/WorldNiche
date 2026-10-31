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
        let visibleDistance = hypot(max(0, abs(viewport.offset.x) - viewport.scale * size.width / size.height),
                                    max(0, abs(viewport.offset.y) - viewport.scale))
        expect(visibleDistance <= 0.850001, "A long diagonal pan leaves a reachable slice of the globe")
        expect(abs(viewport.offset.x) > viewport.scale * size.width / size.height,
               "The planet center can move completely outside the viewport")
        viewport.zoom(by: 0.001, around: center, in: size)
        expect(viewport.offset.x.isFinite && viewport.offset.y.isFinite, "Zooming out from an offscreen center stays finite")
        viewport = GlobeViewport()
        expect(viewport.offset == .zero && viewport.zoomPercent == 100, "Reset restores the original camera")
        viewport.move(by: CGPoint(x: 20, y: 20), in: .zero)
        viewport.zoom(by: 2, around: .zero, in: .zero)
        expect(viewport.offset == .zero && viewport.zoomPercent == 100, "A transient zero-sized layout is safe")

        let start = CGPoint(x: center.x + 35, y: center.y - 25)
        let finish = CGPoint(x: center.x - 50, y: center.y + 35)
        let initial = GlobeViewport()
        let geographicPoint = initial.scenePoint(at: start, in: size)
        var combined = initial
        combined.transform(from: start, to: finish, magnification: 2.5, in: size)
        let movedPoint = combined.scenePoint(at: finish, in: size)
        expect(hypot(geographicPoint.x - movedPoint.x, geographicPoint.y - movedPoint.y) < 0.000001,
               "A geographic point follows a moving pinch centroid exactly")
        for step in 1...100 {
            let t = Double(step) / 100
            var sampled = initial
            let point = CGPoint(x: start.x + (finish.x - start.x) * t, y: start.y + (finish.y - start.y) * t)
            sampled.transform(from: start, to: point, magnification: 1 + 1.5 * t, in: size)
            let under = sampled.scenePoint(at: point, in: size)
            expect(hypot(under.x - geographicPoint.x, under.y - geographicPoint.y) < 0.000001,
                   "Pinch anchoring does not accumulate sample drift")
        }
        combined.transform(from: finish, to: start, magnification: 1 / 2.5, in: size)
        expect(abs(combined.scale - initial.scale) < 0.000001 && hypot(combined.offset.x, combined.offset.y) < 0.000001,
               "Reversing combined movement and pinch restores the starting frame")
        viewport.move(by: CGPoint(x: 60, y: 40), in: size)
        let halfway = viewport.interpolated(to: initial, fraction: 0.5)
        expect(halfway.offset.x != 0 && halfway.offset != viewport.offset, "Reset framing has an intermediate state")
        expect(viewport.interpolated(to: initial, fraction: 1).offset == .zero, "Reset ends at the exact initial position")

        for latitude in stride(from: -40.0, through: 40, by: 20) {
            for longitude in stride(from: -170.0, through: 170, by: 34) {
                let startOrientation = GlobeOrientation(latitude: latitude, longitude: longitude)
                let sphere = initial.surfacePoint(at: start, in: size)!
                let grabbed = startOrientation.quaternion.inverse.act(sphere)
                let target = initial.surfacePoint(at: finish, in: size)!
                let followed = startOrientation.following(grabbed, to: target)
                expect(simd_length(followed.quaternion.act(grabbed) - target) < 0.00001,
                       "One-finger dragging keeps the grabbed geography under the finger")
            }
        }
        expect(initial.surfacePoint(at: .zero, in: size) == nil, "Transparent corners are not the sphere")
        expect(initial.surfacePoint(at: center, in: size) != nil, "Visible surface receives gestures")

        // A near-pole grab used to turn over forty degrees for less than one point of travel.
        var polarTurn = GlobeOrientation(latitude: -34, longitude: 0)
        let polarSize = CGSize(width: 400, height: 360)
        var previous = CGPoint(x: 200, y: 306)
        for step in 1...500 {
            let t = Double(step) / 500
            let point = CGPoint(x: 200 - 280 * t, y: 306 - 378 * t)
            let next = polarTurn.dragging(from: previous, to: point, in: polarSize, viewport: initial)
            let angle = 2 * acos(min(1, abs(Double(simd_dot(polarTurn.quaternion.vector, next.quaternion.vector)))))
            expect(angle < 0.03, "Tiny finger movement near a pole must not jump longitude")
            polarTurn = next
            previous = point
        }

        var closeUp = initial
        closeUp.zoom(by: 4, around: center, in: size)
        var shifted = closeUp
        shifted.move(by: CGPoint(x: 560, y: 0), in: size)
        for frame in [initial, closeUp, shifted] {
            func screen(_ x: Double, _ y: Double) -> CGPoint {
                let radius = min(size.width, size.height) / (2 * frame.scale)
                return CGPoint(x: center.x + (x + frame.offset.x) * radius,
                               y: center.y - (y + frame.offset.y) * radius)
            }
            for latitude in [-85.0, -60, -34, 0, 34, 60, 85] {
                for anchor in [CGPoint.zero, CGPoint(x: 0.8, y: 0), CGPoint(x: 0, y: 0.8),
                               CGPoint(x: 0, y: -0.8), CGPoint(x: 0.6, y: 0.6)] {
                    for end in [CGPoint(x: -1.3, y: -1.3), CGPoint(x: 1.3, y: 1.3),
                                CGPoint(x: -1.3, y: 1.3), CGPoint(x: 1.3, y: -1.3)] {
                        var turn = GlobeOrientation(latitude: latitude, longitude: 179)
                        var previous = screen(anchor.x, anchor.y)
                        // Go past the limb and reverse without lifting the finger.
                        for step in 1...240 {
                            let t = Double(step <= 120 ? step : 240 - step) / 120
                            let point = screen(anchor.x + (end.x - anchor.x) * t, anchor.y + (end.y - anchor.y) * t)
                            let next = turn.dragging(from: previous, to: point, in: size, viewport: frame)
                            let limit = hypot(point.x - previous.x, point.y - previous.y) * 8 * frame.scale / min(size.width, size.height)
                            let angle = 2 * acos(min(1, abs(Double(simd_dot(turn.quaternion.vector, next.quaternion.vector)))))
                            expect(angle.isFinite && angle <= limit + 0.001,
                                   "Limb, pole, diagonal and reversed drags remain continuous at every zoom and offset")
                            let north = next.quaternion.act(SIMD3<Float>(0, 1, 0))
                            expect(abs(north.x) < 0.00001 && north.y > 0, "Surface dragging never rolls or flips north")
                            turn = next
                            previous = point
                        }
                        let stopped = turn.dragging(from: previous, to: previous, in: size, viewport: frame)
                        expect(stopped.latitude == turn.latitude && stopped.longitude == turn.longitude,
                               "A stationary finger does not accumulate rotation")
                    }
                }
            }
        }

        var preciseTurn = GlobeOrientation(latitude: 46, longitude: 2)
        let held = preciseTurn.quaternion.inverse.act(initial.surfacePoint(at: start, in: size)!)
        var last = start
        for step in 1...100 {
            let t = Double(step) / 100
            let point = CGPoint(x: start.x + (finish.x - start.x) * t, y: start.y + (finish.y - start.y) * t)
            preciseTurn = preciseTurn.dragging(from: last, to: point, in: size, viewport: initial)
            expect(simd_length(preciseTurn.quaternion.act(held) - initial.surfacePoint(at: point, in: size)!) < 0.0001,
                   "Ordinary country dragging retains its geographic anchor through sampled input")
            last = point
        }

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

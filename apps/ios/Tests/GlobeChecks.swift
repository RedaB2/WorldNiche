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

        expect(initial.surfacePoint(at: .zero, in: size) == nil, "Transparent corners are not the sphere")
        expect(initial.surfacePoint(at: center, in: size) != nil, "Visible surface receives gestures")
        var closeUp = initial
        closeUp.zoom(by: 4, around: center, in: size)
        var shifted = closeUp
        shifted.move(by: CGPoint(x: 560, y: 0), in: size)
        for frame in [initial, closeUp, shifted] {
            for latitude in [-85.0, -60, -32, 0, 32, 60, 85] {
                let original = GlobeOrientation(latitude: latitude, longitude: 179)
                for samples in [1, 15, 30, 60, 120, 240] {
                    for origin in [center, CGPoint(x: 40, y: 60), CGPoint(x: 340, y: 290)] {
                        var turn = original
                        var previous = origin
                        for step in 1...samples {
                            let point = CGPoint(x: origin.x + 140 * Double(step) / Double(samples), y: origin.y)
                            turn = turn.dragging(from: previous, to: point, in: size, viewport: frame)
                            expect(abs(turn.latitude - original.latitude) < 0.0000001,
                                   "A horizontal sweep must not pull toward either pole, including at the limb")
                            previous = point
                        }
                        let single = original.dragging(from: origin, to: previous, in: size, viewport: frame)
                        expect(abs((turn.longitude - single.longitude).remainder(dividingBy: 2 * .pi)) < 0.0000001,
                               "The same horizontal travel gives the same turn at every event rate and touch location")
                        let vertical = original.dragging(from: origin, to: CGPoint(x: origin.x, y: origin.y + 80), in: size, viewport: frame)
                        expect(abs(vertical.longitude - original.longitude) < 0.0000001,
                               "A vertical sweep never introduces a ninety-degree longitude turn")
                        let reverse = turn.dragging(from: previous, to: origin, in: size, viewport: frame)
                        expect(abs((reverse.longitude - original.longitude).remainder(dividingBy: 2 * .pi)) < 0.0000001,
                               "Reversing a horizontal drag returns to the same orientation")
                    }
                }
            }
        }
        // Slow and fast circles and reversals have identical checkpoints and no accumulated pull.
        let waypoints = [center, CGPoint(x: center.x + 60, y: center.y + 35),
                         CGPoint(x: center.x - 40, y: center.y - 45), center]
        for samples in [1, 12, 60, 240] {
            let original = GlobeOrientation(latitude: 32, longitude: -5)
            var turn = original
            for (a, b) in zip(waypoints, waypoints.dropFirst()) {
                var previous = a
                for step in 1...samples {
                    let t = Double(step) / Double(samples)
                    let point = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                    turn = turn.dragging(from: previous, to: point, in: size, viewport: initial)
                    previous = point
                }
                let direct = original.dragging(from: center, to: b, in: size, viewport: initial)
                expect(abs(turn.latitude - direct.latitude) < 0.0000001 && abs(turn.longitude - direct.longitude) < 0.0000001,
                       "Diagonal path checkpoints do not depend on sample count")
            }
            for step in 1...(samples * 10) {
                let a = Double(step - 1) / Double(samples * 10) * 2 * .pi
                let b = Double(step) / Double(samples * 10) * 2 * .pi
                turn = turn.dragging(from: CGPoint(x: center.x + 40 * cos(a), y: center.y + 40 * sin(a)),
                    to: CGPoint(x: center.x + 40 * cos(b), y: center.y + 40 * sin(b)), in: size, viewport: initial)
            }
            expect(abs(turn.latitude - original.latitude) < 0.0000001 && abs(turn.longitude - original.longitude) < 0.0000001,
                   "A small circular drag cannot accumulate roll, pole pull or angular drift")
        }
        let atPole = GlobeOrientation(latitude: 85, longitude: 25)
        let reversed = atPole.dragging(from: center, to: CGPoint(x: center.x, y: center.y - 1), in: size, viewport: initial)
        expect(reversed.latitude < atPole.latitude && reversed.longitude == atPole.longitude,
               "Reversal away from the pole limit responds immediately without overshoot debt")

        for rate in [15, 30, 60, 120, 240] {
            var estimator = GlobeDragVelocity()
            for sample in 0...rate {
                let t = Double(sample) / Double(rate)
                estimator.record(CGPoint(x: 600 * t, y: -150 * t), at: t)
            }
            let velocity = estimator.velocity(at: 1)
            expect(abs(velocity.x - 600) < 0.00001 && abs(velocity.y + 150) < 0.00001,
                   "Release velocity reflects time and travel, not callback count")
            expect(estimator.velocity(at: 1.2) == .zero, "A pause before release suppresses inertia")
            estimator.record(CGPoint(x: 600, y: -150), at: 1.2)
            expect(estimator.velocity(at: 1.2) == .zero, "Holding still does not release an old flick")
            let startTurn = GlobeOrientation(latitude: 32, longitude: -5)
            let coast = GlobeMomentum(orientation: startTurn, velocity: velocity, viewport: initial,
                                      size: size, started: 10, reduceMotion: false)!
            expect(coast.orientation(at: 10).latitude == startTurn.latitude && coast.orientation(at: 10).longitude == startTurn.longitude,
                   "Release starts at the exact dragged orientation")
            let stop = coast.orientation(at: 11)
            expect(stop.latitude == coast.orientation(at: 20).latitude && stop.longitude == coast.orientation(at: 20).longitude,
                   "The short release glide finishes without endless drift")
            let almost = coast.orientation(at: 10 + GlobeMomentum.duration - 0.01)
            expect(abs(almost.longitude - stop.longitude) < 0.00001, "Release speed approaches zero smoothly")
            let interrupted = coast.orientation(at: 10.07)
            let regrab = interrupted.dragging(from: center, to: center, in: size, viewport: initial)
            expect(regrab.latitude == interrupted.latitude && regrab.longitude == interrupted.longitude,
                   "Regrabbing an in-flight glide does not reorient or snap north")
            expect(GlobeMomentum(orientation: startTurn, velocity: velocity, viewport: initial,
                                 size: size, started: 10, reduceMotion: true) == nil,
                   "Reduce Motion disables release inertia")
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

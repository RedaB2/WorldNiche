import XCTest
import UIKit

final class GlobeInteractionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testHorizontalSweepDoesNotPullTowardAPole() {
        let app = launch()
        let globe = globe(in: app)
        let start = CGPoint(x: globe.frame.midX, y: globe.frame.midY)
        let distance: CGFloat = 140
        let points = (0...90).map { NSValue(cgPoint: CGPoint(x: start.x + distance * CGFloat($0) / 90, y: start.y)) }
        capture("Before the horizontal sweep", app: app)
        XCTAssertNil(GlobeTestGestures.trace(points, duration: 1.5, hold: 0.2))
        capture("Horizontal sweep must preserve latitude", app: app)
        let longitude = -5 - Double(distance * 2 * 1.18 / min(globe.frame.width, globe.frame.height)) * 180 / .pi
        tap(latitude: 39, longitude: -98, on: globe, centeredAt: (32, longitude), zoom: 1)
        expectCountry("United States", app: app)
    }

    @MainActor
    func testResetAppearsOnlyAfterTouchingVisibleGlobe() {
        let app = launch()
        let globe = globe(in: app)
        XCTAssertFalse(app.buttons["resetGlobe"].exists, "Startup must not offer a reset action")
        let originalFrame = globe.frame
        tap(latitude: 25, longitude: -35, on: globe, centeredAt: (32, -5), zoom: 1)
        XCTAssertTrue(app.buttons["resetGlobe"].waitForExistence(timeout: 2), "An ocean tap still counts as touching the globe")
        XCTAssertEqual(globe.frame, originalFrame, "Revealing Reset must not move the layout")
        app.buttons["resetGlobe"].tap()
        XCTAssertTrue(app.buttons["resetGlobe"].exists)
        app.terminate()
        app.launch()
        XCTAssertFalse(app.buttons["resetGlobe"].exists, "Touch history must not persist across launches")
    }

    @MainActor
    func testOneFingerLimbDragKeepsThePlanetCentered() throws {
        let app = launch()
        let globe = globe(in: app)
        let originalFrame = globe.frame
        let before = try silhouetteEdges(of: globe)
        XCTAssertEqual((before[0] + before[1]) / 2, globe.frame.width / 2, accuracy: 3)
        let paths: [(CGVector, CGVector)] = [
            (.init(dx: 0.5, dy: 0.5), .init(dx: 0.98, dy: 0.5)),
            (.init(dx: 0.5, dy: 0.5), .init(dx: 0.02, dy: 0.5)),
            (.init(dx: 0.5, dy: 0.5), .init(dx: 0.5, dy: 0.96)),
            (.init(dx: 0.5, dy: 0.5), .init(dx: 0.5, dy: 0.04)),
            (.init(dx: 0.3, dy: 0.3), .init(dx: 0.95, dy: 0.95)),
            (.init(dx: 0.7, dy: 0.7), .init(dx: 0.05, dy: 0.05)),
            // The lower center is covered by the country-name button on the Duo.
            (.init(dx: 0.5, dy: 0.15), .init(dx: 0.02, dy: 0.98)),
            (.init(dx: 0.85, dy: 0.5), .init(dx: 0.1, dy: 0.9))
        ]
        for (start, end) in paths {
            globe.coordinate(withNormalizedOffset: start).press(forDuration: 0.05,
                thenDragTo: globe.coordinate(withNormalizedOffset: end))
            XCTAssertEqual(globe.frame, originalFrame, "A drag on exposed geography must not scroll the page")
            try assertFraming(before, globe: globe, zoom: "100% zoom")
        }
        Thread.sleep(forTimeInterval: 0.5)
        try assertFraming(before, globe: globe, zoom: "100% zoom")
        capture("Repeated limb, pole and diagonal spins keep the sphere centered", app: app)
    }

    @MainActor
    func testOneFingerSpinsPreserveAnOffscreenMaximumZoomFrame() throws {
        let app = launch()
        let globe = focusEurope(app)
        zoomIn(globe)
        // Leave an observable curved silhouette in the viewport at 400% zoom.
        let radius = min(globe.frame.width, globe.frame.height) * 4 / (2 * 1.18)
        let shift = radius - globe.frame.width * 0.1
        let steps = Int(ceil(shift / 100))
        for _ in 0..<steps { move(globe, by: CGPoint(x: shift / CGFloat(steps), y: 0)) }
        let before = try silhouetteEdges(of: globe)
        XCTAssertGreaterThan(before[0], 20, "The shifted sphere must have a visible left edge")
        for end in [CGVector(dx: 0.99, dy: 0.05), .init(dx: 0.3, dy: 0.9),
                    .init(dx: 0.99, dy: 0.95), .init(dx: 0.3, dy: 0.1)] {
            globe.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).press(forDuration: 0.05,
                thenDragTo: globe.coordinate(withNormalizedOffset: end))
            try assertFraming(before, globe: globe, zoom: "400% zoom")
        }
        capture("One-finger spins preserve the intentionally shifted close-up", app: app)
        app.buttons["resetGlobe"].tap()
        waitForZoom("100% zoom", globe: globe)
    }

    @MainActor
    func testFingerCountTransitionsOnlyTranslateDuringTwoFingerMovement() throws {
        let app = launch()
        let globe = globe(in: app)
        let delta = CGPoint(x: 35, y: -20)
        move(globe, by: delta)
        let expected = try silhouetteEdges(of: globe)
        app.buttons["resetGlobe"].tap()
        waitForZoom("100% zoom", globe: globe)
        let first = CGPoint(x: globe.frame.midX - 30, y: globe.frame.midY + 40)
        let second = CGPoint(x: globe.frame.midX + 30, y: globe.frame.midY + 40)
        XCTAssertNil(GlobeTestGestures.transitionFirst(first, second: second, translation: delta,
            finalPoint: CGPoint(x: globe.frame.maxX - 8, y: globe.frame.minY + 20)))
        try assertFraming(expected, globe: globe, zoom: "100% zoom")
        capture("Adding and lifting a finger preserve the intentional two-finger framing", app: app)
    }

    @MainActor
    private func assertFraming(_ expected: [CGFloat], globe: XCUIElement, zoom: String,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(globe.value as? String, zoom, file: file, line: line)
        let actualEdges = try silhouetteEdges(of: globe)
        if zip(actualEdges, expected).contains(where: { abs($0 - $1) > 3 }) {
            let attachment = XCTAttachment(screenshot: globe.screenshot())
            attachment.name = "Sphere outline mismatch"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        for (actual, edge) in zip(actualEdges, expected) {
            XCTAssertEqual(actual, edge, accuracy: 3,
                "One-finger spinning changed the rendered sphere's position or size", file: file, line: line)
        }
    }

    @MainActor
    private func silhouetteEdges(of globe: XCUIElement) throws -> [CGFloat] {
        let image = try XCTUnwrap(globe.screenshot().image.cgImage)
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let background = Array(pixels[0..<3])
        func isSphere(x: Int, y: Int) -> Bool {
            let pixel = (y * width + x) * 4
            return (0..<3).reduce(0) { $0 + abs(Int(pixels[pixel + $1]) - Int(background[$1])) } > 8
        }
        // Multiple horizontal and vertical chords detect translation even in a clipped close-up.
        // Exclude the page's 24-point fade, whose opacity varies with land and ocean colors.
        let inset = Int(ceil(26 * CGFloat(height) / globe.frame.height))
        return [0.5, 0.25, 0.75].flatMap { fraction -> [CGFloat] in
            let row = (0..<width).filter { isSphere(x: $0, y: Int(Double(height) * fraction)) }
            let column = (inset..<(height - inset)).filter { isSphere(x: Int(Double(width) * fraction), y: $0) }
            return [CGFloat(row.first ?? -1) * globe.frame.width / CGFloat(width),
                    CGFloat(row.last ?? -1) * globe.frame.width / CGFloat(width),
                    CGFloat(column.first ?? -1) * globe.frame.height / CGFloat(height),
                    CGFloat(column.last ?? -1) * globe.frame.height / CGFloat(height)]
        }
    }

    @MainActor
    func testCountryTapsPreviewWithoutMovingTheGlobeOrOpeningDetails() {
        let app = launch()
        let globe = globe(in: app)
        tap(latitude: 46, longitude: 2, on: globe, centeredAt: (32, -5), zoom: 1)
        expectCountry("France", app: app)
        XCTAssertFalse(app.staticTexts["countryTitle"].exists)
        // The second coordinate is still relative to Morocco: selecting did not recenter.
        tap(latitude: 40, longitude: -4, on: globe, centeredAt: (32, -5), zoom: 1)
        expectCountry("Spain", app: app)
        XCTAssertFalse(app.staticTexts["countryTitle"].exists)
        capture("Country browsing stays on the globe", app: app)
        app.buttons["landingCountry"].tap()
        XCTAssertTrue(app.staticTexts["countryTitle"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["countryTitle"].label, "Spain")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertEqual(globe.value as? String, "100% zoom")
        expectCountry("Spain", app: app)
    }

    @MainActor
    func testEuropeanCountriesAtMaximumZoomAndTwoFingerRepositioning() {
        let app = launch()
        let globe = focusEurope(app)
        zoomIn(globe)
        tap(latitude: 46.8, longitude: 8.2, on: globe, centeredAt: (46, 2), zoom: 4)
        expectCountry("Switzerland", app: app)
        tap(latitude: 50.8, longitude: 4.5, on: globe, centeredAt: (46, 2), zoom: 4)
        expectCountry("Belgium", app: app)
        XCTAssertFalse(app.staticTexts["countryTitle"].exists)
        capture("Small European countries at four times zoom", app: app)

        // Geographic hit testing follows the same view translation as the rendered sphere.
        let delta = CGPoint(x: -85, y: 30)
        move(globe, by: delta)
        capture("Two-finger movement before the next selection", app: app)
        XCTAssertEqual(globe.value as? String, "400% zoom", "Two-finger movement must not change magnification")
        tap(latitude: 46, longitude: 2, on: globe, centeredAt: (46, 2), zoom: 4, offset: delta)
        expectCountry("France", app: app)
        XCTAssertFalse(app.staticTexts["countryTitle"].exists)
        capture("Country hit testing follows two-finger movement", app: app)
        app.buttons["resetGlobe"].tap()
        waitForZoom("100% zoom", globe: globe)
        globe.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        expectCountry("France", app: app)
        app.buttons["landingCountry"].tap()
        XCTAssertTrue(app.staticTexts["countryTitle"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["countryTitle"].label, "France")
        app.buttons["Close"].firstMatch.tap()
        globe.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: globe.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.55)))
        XCTAssertTrue(globe.isHittable)
        capture("Single-finger rotation after zoom, movement, and country details", app: app)
        app.buttons["resetGlobe"].tap()
    }

    @MainActor
    func testMovingPinchAnchorAndPredictableOneFingerRotation() {
        let app = launch()
        let globe = focusEurope(app)
        let center = CGPoint(x: globe.frame.midX, y: globe.frame.midY)
        XCTAssertNil(GlobeTestGestures.moveFirst(CGPoint(x: center.x - 30, y: center.y),
            second: CGPoint(x: center.x + 30, y: center.y),
            toFirst: CGPoint(x: center.x - 60, y: center.y),
            toSecond: CGPoint(x: center.x + 60, y: center.y), duration: 0.8))
        waitForZoom("200% zoom", globe: globe)
        let anchor = screenPoint(latitude: 46.8, longitude: 8.2, on: globe, centeredAt: (46, 2), zoom: 2)
        let destination = CGPoint(x: anchor.x + 45, y: anchor.y + 25)
        XCTAssertNil(GlobeTestGestures.moveFirst(CGPoint(x: anchor.x - 28, y: anchor.y),
            second: CGPoint(x: anchor.x + 28, y: anchor.y),
            toFirst: CGPoint(x: destination.x - 42, y: destination.y),
            toSecond: CGPoint(x: destination.x + 42, y: destination.y), duration: 1.2))
        waitForZoom("300% zoom", globe: globe)
        // Switzerland must travel with the moving midpoint, before any reset or recentering.
        coordinate(destination, on: globe).tap()
        expectCountry("Switzerland", app: app)
        capture("Moving pinch keeps Switzerland under its centroid", app: app)
        let dragged = CGPoint(x: destination.x - 75, y: destination.y + 20)
        trace(from: destination, to: dragged, duration: 0.8)
        let factor = 2 * 1.18 / (3 * min(globe.frame.width, globe.frame.height)) * 180 / .pi
        let newCenter = (46 + Double(20 * factor), 2 + Double(75 * factor))
        let offset = CGPoint(x: 45 - (anchor.x - center.x) * 0.5, y: 25 - (anchor.y - center.y) * 0.5)
        tap(latitude: 46.8, longitude: 8.2, on: globe, centeredAt: newCenter, zoom: 3, offset: offset)
        expectCountry("Switzerland", app: app)
        XCTAssertFalse(app.staticTexts["countryTitle"].exists)
        capture("Predictable one-finger rotation preserves country hit testing", app: app)
        app.buttons["resetGlobe"].tap()
        waitForZoom("100% zoom", globe: globe)
        globe.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        expectCountry("Switzerland", app: app)
        XCTAssertTrue(app.buttons["spinButton"].isHittable, "Globe movement must not scroll the containing page")
    }

    @MainActor
    func testGlobeCenterCanLeaveTheViewAndResetRecoversIt() {
        let app = launch()
        let globe = focusEurope(app)
        zoomIn(globe)
        // Two successive moves can carry the planet center beyond the right edge.
        for _ in 0..<2 { move(globe, by: CGPoint(x: 140, y: 15)) }
        XCTAssertEqual(globe.value as? String, "400% zoom")
        capture("Planet center outside the viewport", app: app)
        // This French point started at the center. Moving it back remains reversible.
        for _ in 0..<2 { move(globe, by: CGPoint(x: -140, y: -15)) }
        globe.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        expectCountry("France", app: app)
        app.buttons["resetGlobe"].tap()
        waitForZoom("100% zoom", globe: globe)
        capture("Reset restores the whole globe", app: app)
    }

    @MainActor
    func testOceanAndTransparentCornersDoNotSelectCountries() {
        let app = launch()
        let globe = globe(in: app)
        tap(latitude: 25, longitude: -35, on: globe, centeredAt: (32, -5), zoom: 1)
        expectCountry("Morocco", app: app)
        globe.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.02)).tap()
        expectCountry("Morocco", app: app)
        XCTAssertFalse(app.staticTexts["countryTitle"].exists)
        zoomIn(globe)
        move(globe, by: CGPoint(x: 100, y: 70))
        app.buttons["spinButton"].tap()
        waitForZoom("100% zoom", globe: globe)
        XCTAssertFalse(app.staticTexts["countryTitle"].exists)
    }

    @MainActor
    func testTransparentCornerLeavesPageScrollingAvailable() {
        let app = launch()
        let globe = globe(in: app)
        let originalY = globe.frame.minY
        XCTAssertFalse(app.buttons["resetGlobe"].exists)
        let start = globe.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.12))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -140)))
        XCTAssertLessThan(globe.frame.minY, originalY - 30, "Dragging blank space should scroll the page")
        XCTAssertFalse(app.buttons["resetGlobe"].exists, "Blank page scrolling is not a globe interaction")
    }

    @MainActor
    func testExplorationDemo() {
        let app = launch()
        let globe = globe(in: app)
        XCTAssertFalse(app.buttons["resetGlobe"].exists)
        capture("Initial globe has no Reset button", app: app)
        Thread.sleep(forTimeInterval: 0.8)
        let origin = CGPoint(x: globe.frame.midX, y: globe.frame.midY)
        XCTAssertNil(GlobeTestGestures.trace([NSValue(cgPoint: origin)], duration: 0, hold: 0.15))
        XCTAssertTrue(app.buttons["resetGlobe"].exists)
        capture("Reset appears after the first globe touch", app: app)
        trace(from: origin, to: CGPoint(x: origin.x + 130, y: origin.y), duration: 1.5)
        trace(from: origin, to: CGPoint(x: origin.x - 110, y: origin.y), duration: 0.25, hold: 0)
        trace(from: origin, to: CGPoint(x: origin.x + 55, y: origin.y - 45), duration: 1)
        let circle = (0...60).map { step in
            let angle = Double(step) / 60 * 2 * .pi
            return NSValue(cgPoint: CGPoint(x: origin.x + 40 * cos(angle), y: origin.y + 40 * sin(angle)))
        }
        XCTAssertNil(GlobeTestGestures.trace(circle, duration: 1.5, hold: 0.2))
        capture("Smooth horizontal, diagonal, flick and circular turns", app: app)
        app.buttons["resetGlobe"].tap()
        waitForZoom("100% zoom", globe: globe)
        tap(latitude: 46, longitude: 2, on: globe, centeredAt: (32, -5), zoom: 1)
        expectCountry("France", app: app)
        app.buttons["resetGlobe"].tap()
        let anchor = screenPoint(latitude: 46.8, longitude: 8.2, on: globe, centeredAt: (46, 2), zoom: 1)
        let destination = CGPoint(x: anchor.x + 35, y: anchor.y + 18)
        XCTAssertNil(GlobeTestGestures.moveFirst(CGPoint(x: anchor.x - 25, y: anchor.y),
            second: CGPoint(x: anchor.x + 25, y: anchor.y),
            toFirst: CGPoint(x: destination.x - 50, y: destination.y),
            toSecond: CGPoint(x: destination.x + 50, y: destination.y), duration: 2))
        coordinate(destination, on: globe).tap()
        expectCountry("Switzerland", app: app)
        capture("Off-center zoom beyond the original silhouette", app: app)
        XCTAssertNil(GlobeTestGestures.moveFirst(CGPoint(x: destination.x - 25, y: destination.y),
            second: CGPoint(x: destination.x + 25, y: destination.y),
            toFirst: CGPoint(x: destination.x - 50, y: destination.y),
            toSecond: CGPoint(x: destination.x + 50, y: destination.y), duration: 2))
        waitForZoom("400% zoom", globe: globe)
        capture("Crisp borders at maximum zoom", app: app)
        trace(from: destination, to: CGPoint(x: destination.x - 60, y: destination.y + 28), duration: 1)
        for _ in 0..<2 { move(globe, by: CGPoint(x: 140, y: 15)) }
        capture("Exploration with the center offscreen", app: app)
        app.buttons["resetGlobe"].tap()
        waitForZoom("100% zoom", globe: globe)
        capture("Smooth return to the selected country", app: app)
        app.buttons["landingCountry"].tap()
        XCTAssertTrue(app.staticTexts["countryTitle"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["countryTitle"].label, "Switzerland")
        app.buttons["Close"].firstMatch.tap()
    }

    @MainActor
    func testZoomedSweepsAndCircularReversalsKeepPredictableOrientation() {
        let app = launch()
        let globe = focusEurope(app)
        zoomIn(globe)
        let offset = CGPoint(x: -75, y: 20)
        move(globe, by: offset)
        let origin = CGPoint(x: globe.frame.midX, y: globe.frame.midY)
        // Let synthesized input settle before assertions that intentionally exclude release glide.
        trace(from: origin, to: CGPoint(x: origin.x + 100, y: origin.y), duration: 1.2, hold: 0.5)
        trace(from: origin, to: CGPoint(x: origin.x, y: origin.y - 40), duration: 0.3, hold: 0.5)
        let circle = (0...90).map { step in
            let angle = Double(step) / 90 * 2 * .pi
            return NSValue(cgPoint: CGPoint(x: origin.x + 30 * cos(angle), y: origin.y + 30 * sin(angle)))
        }
        XCTAssertNil(GlobeTestGestures.trace(circle, duration: 1.5, hold: 0.5))
        let factor = 2 * 1.18 / (4 * min(globe.frame.width, globe.frame.height)) * 180 / .pi
        tap(latitude: 46.8, longitude: 8.2, on: globe,
            centeredAt: (46 - Double(40 * factor), 2 - Double(100 * factor)), zoom: 4, offset: offset)
        expectCountry("Switzerland", app: app)
        capture("Slow and fast close-up sweeps with circular reversal preserve orientation", app: app)
    }

    @MainActor
    func testTouchInterruptsResetWithoutCompletingItsCameraMovement() {
        let app = launch()
        let globe = focusEurope(app)
        zoomIn(globe)
        move(globe, by: CGPoint(x: 60, y: 15))
        let reset = app.buttons["resetGlobe"].frame
        let origin = CGPoint(x: globe.frame.midX, y: globe.frame.midY)
        let points = (0...60).map { NSValue(cgPoint: CGPoint(x: origin.x + CGFloat($0), y: origin.y)) }
        XCTAssertNil(GlobeTestGestures.reset(at: CGPoint(x: reset.midX, y: reset.midY), thenTrace: points, duration: 1))
        let interrupted = globe.value as? String ?? ""
        let percent = Int(interrupted.replacingOccurrences(of: "% zoom", with: "")) ?? 0
        XCTAssertGreaterThan(percent, 100, "Touch must stop the reset at its visible intermediate zoom")
        XCTAssertLessThan(percent, 400)
        trace(from: origin, to: CGPoint(x: origin.x - 60, y: origin.y + 20), duration: 0.5)
        XCTAssertEqual(globe.value as? String, interrupted, "Subsequent one-finger turning keeps the interrupted framing")
        capture("Reset interruption holds the current frame", app: app)
    }

    @MainActor
    private func trace(from start: CGPoint, to end: CGPoint, duration: Double, hold: Double = 0.2) {
        let points = (0...60).map { step in
            let t = CGFloat(step) / 60
            return NSValue(cgPoint: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
        }
        XCTAssertNil(GlobeTestGestures.trace(points, duration: duration, hold: hold))
    }

    @MainActor
    private func launch() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-worldniche-skip-intro", "-worldniche-journal-fixture", "reset"]
        app.launch()
        XCTAssertTrue(app.buttons["landingCountry"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func globe(in app: XCUIApplication) -> XCUIElement {
        let globe = app.descendants(matching: .any)["interactiveGlobe"].firstMatch
        XCTAssertTrue(globe.isHittable)
        return globe
    }

    @MainActor
    private func focusEurope(_ app: XCUIApplication) -> XCUIElement {
        let globe = globe(in: app)
        tap(latitude: 46, longitude: 2, on: globe, centeredAt: (32, -5), zoom: 1)
        expectCountry("France", app: app)
        app.buttons["resetGlobe"].tap()
        return globe
    }

    @MainActor
    private func zoomIn(_ globe: XCUIElement) {
        // XCTest's generic pinch rectangle is off-center on the Duo's sidebar layout.
        // Explicit touch paths keep geographic assertions anchored to the visible center.
        let center = CGPoint(x: globe.frame.midX, y: globe.frame.midY)
        for _ in 0..<2 {
            XCTAssertNil(GlobeTestGestures.moveFirst(CGPoint(x: center.x - 30, y: center.y),
                second: CGPoint(x: center.x + 30, y: center.y),
                toFirst: CGPoint(x: center.x - 90, y: center.y),
                toSecond: CGPoint(x: center.x + 90, y: center.y), duration: 0.8))
        }
        waitForZoom("400% zoom", globe: globe)
    }

    @MainActor
    private func move(_ globe: XCUIElement, by delta: CGPoint) {
        let first = CGPoint(x: globe.frame.midX - 30, y: globe.frame.midY + 40)
        let second = CGPoint(x: globe.frame.midX + 30, y: globe.frame.midY + 40)
        XCTAssertNil(GlobeTestGestures.moveFirst(first, second: second,
            toFirst: CGPoint(x: first.x + delta.x, y: first.y + delta.y),
            toSecond: CGPoint(x: second.x + delta.x, y: second.y + delta.y), duration: 0.8))
    }

    @MainActor
    private func tap(latitude: Double, longitude: Double, on globe: XCUIElement,
                     centeredAt center: (Double, Double), zoom: Double, offset: CGPoint = .zero) {
        coordinate(screenPoint(latitude: latitude, longitude: longitude, on: globe, centeredAt: center,
                               zoom: zoom, offset: offset), on: globe).tap()
    }

    @MainActor
    private func screenPoint(latitude: Double, longitude: Double, on globe: XCUIElement,
                             centeredAt center: (Double, Double), zoom: Double, offset: CGPoint = .zero) -> CGPoint {
        let lat = latitude * .pi / 180, deltaLon = (longitude - center.1) * .pi / 180
        let tilt = center.0 * .pi / 180
        let radius = min(globe.frame.width, globe.frame.height) / (2 * 1.18) * zoom
        return CGPoint(x: globe.frame.midX + cos(lat) * sin(deltaLon) * radius + offset.x,
            y: globe.frame.midY - (cos(tilt) * sin(lat) - sin(tilt) * cos(lat) * cos(deltaLon)) * radius + offset.y)
    }

    @MainActor
    private func coordinate(_ point: CGPoint, on globe: XCUIElement) -> XCUICoordinate {
        globe.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - globe.frame.minX, dy: point.y - globe.frame.minY))
    }

    @MainActor
    private func expectCountry(_ name: String, app: XCUIApplication) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", name),
                                                 object: app.buttons["landingCountry"])
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
    }

    @MainActor
    private func waitForZoom(_ value: String, globe: XCUIElement) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: globe)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

import XCTest
import UIKit

final class GlobeInteractionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

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
    func testMovingPinchCentroidAndOneFingerDragKeepTheGrabbedCountry() {
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
        coordinate(destination, on: globe).press(forDuration: 0.05, thenDragTo: coordinate(dragged, on: globe))
        coordinate(dragged, on: globe).tap()
        expectCountry("Switzerland", app: app)
        XCTAssertFalse(app.staticTexts["countryTitle"].exists)
        capture("One finger carries the same Swiss surface point", app: app)
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
        let start = globe.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.12))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -140)))
        XCTAssertLessThan(globe.frame.minY, originalY - 30, "Dragging blank space should scroll the page")
    }

    @MainActor
    func testExplorationDemo() {
        let app = launch()
        let globe = globe(in: app)
        capture("Initial globe composition", app: app)
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
        let dragged = CGPoint(x: destination.x - 60, y: destination.y + 28)
        coordinate(destination, on: globe).press(forDuration: 0.05, thenDragTo: coordinate(dragged, on: globe))
        coordinate(dragged, on: globe).tap()
        expectCountry("Switzerland", app: app)
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

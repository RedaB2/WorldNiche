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

        // UIKit's pan recognition slop varies by device. Use a long move and a
        // country's interior to check hit testing without assuming zero slop.
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
    func testPinchAndMoveTogetherThenSingleFingerRotationRemainUsable() {
        let app = launch()
        let globe = focusEurope(app)
        let center = CGPoint(x: globe.frame.midX, y: globe.frame.midY)
        let error = GlobeTestGestures.moveFirst(CGPoint(x: center.x - 35, y: center.y),
            second: CGPoint(x: center.x + 35, y: center.y),
            toFirst: CGPoint(x: center.x - 45, y: center.y + 20),
            toSecond: CGPoint(x: center.x + 95, y: center.y + 20), duration: 1)
        XCTAssertNil(error)
        XCTAssertNotEqual(globe.value as? String, "100% zoom")
        XCTAssertFalse(app.staticTexts["countryTitle"].exists)
        for _ in 0..<3 {
            globe.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4))
                .press(forDuration: 0.05, thenDragTo: globe.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)))
        }
        app.buttons["resetGlobe"].tap()
        waitForZoom("100% zoom", globe: globe)
        tap(latitude: 46.8, longitude: 8.2, on: globe, centeredAt: (46, 2), zoom: 1)
        expectCountry("Switzerland", app: app)
        XCTAssertTrue(app.buttons["spinButton"].isHittable, "Globe movement must not scroll the containing page")
        app.buttons["spinButton"].tap()
        XCTAssertFalse(app.staticTexts["countryTitle"].exists)
        XCTAssertEqual(globe.value as? String, "100% zoom")
        XCTAssertTrue(app.buttons["landingCountry"].isHittable)
    }

    @MainActor
    func testOceanAndOutsideCircleDoNotSelectCountries() {
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
        let lat = latitude * .pi / 180, deltaLon = (longitude - center.1) * .pi / 180
        let tilt = center.0 * .pi / 180
        let radius = min(globe.frame.width, globe.frame.height) / (2 * 1.18) * zoom
        let x = cos(lat) * sin(deltaLon) * radius + offset.x
        let y = -(cos(tilt) * sin(lat) - sin(tilt) * cos(lat) * cos(deltaLon)) * radius + offset.y
        globe.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: x, dy: y)).tap()
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

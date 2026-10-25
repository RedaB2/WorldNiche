import UIKit
import XCTest

final class AdaptiveLayoutUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    override func tearDown() async throws {
        await MainActor.run {
            XCUIDevice.shared.orientation = .portrait
            XCUIApplication().terminate()
        }
        try await super.tearDown()
    }

    @MainActor
    func testCountryDetailPreservesSelectionAndBookmarkThroughRotation() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Discover"].tap()
        let landing = app.buttons["landingCountry"]
        XCTAssertTrue(landing.waitForExistence(timeout: 10))
        waitUntilHittable(landing)
        landing.tap()

        let title = app.staticTexts["countryTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertEqual(title.label, "Morocco")
        let save = app.buttons["saveCountry"]
        waitUntilHittable(save)
        let originalLabel = save.label
        XCTAssertTrue(["Save country", "Unsave country"].contains(originalLabel))
        let changedLabel = originalLabel == "Save country" ? "Unsave country" : "Save country"
        save.tap()
        waitForLabel(changedLabel, on: save)
        // Restore the existing journal choice even if a rotation assertion fails.
        defer {
            if save.exists, save.isHittable, save.label == changedLabel { save.tap() }
        }

        rotate(.landscapeLeft, app: app)
        assertCountryRemainsOpen("Morocco", bookmark: changedLabel, app: app)
        capture("Country and bookmark after landscape rotation", app: app)

        rotate(.portrait, app: app)
        assertCountryRemainsOpen("Morocco", bookmark: changedLabel, app: app)
        capture("Country and bookmark restored to portrait", app: app)
        save.tap()
        waitForLabel(originalLabel, on: save)
        app.navigationBars["A little more local"].buttons["Close"].tap()
        waitUntilHittable(landing)
        XCTAssertTrue(landing.label.contains("Morocco"))
    }

    @MainActor
    func testAtlasCapitalSearchAndCountryPresentationInLandscapeWithLargeText() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXL"]
        app.launch()
        app.tabBars.buttons["Atlas"].tap()
        rotate(.landscapeLeft, app: app)

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        for _ in 0..<3 where !search.isHittable { app.swipeDown() }
        waitUntilHittable(search)
        search.tap()
        // Search by the capital so this also exercises the Atlas filter.
        search.typeText("Tokyo\n")
        let japan = app.buttons.containing(.staticText, identifier: "Japan").firstMatch
        XCTAssertTrue(japan.waitForExistence(timeout: 8))
        for _ in 0..<5 where !japan.isHittable { app.swipeUp() }
        waitUntilHittable(japan)
        capture("Atlas capital search in landscape with large text", app: app)
        japan.tap()

        let title = app.staticTexts["countryTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertEqual(title.label, "Japan")
        for _ in 0..<4 where !title.isHittable { app.swipeUp() }
        waitUntilHittable(title)
        XCTAssertGreaterThan(title.frame.width, 0)
        XCTAssertGreaterThanOrEqual(title.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(title.frame.maxX, app.frame.maxX)
        let close = app.navigationBars["A little more local"].buttons["Close"]
        waitUntilHittable(close)
        waitUntilHittable(app.buttons["saveCountry"])
        capture("Country presentation in landscape with large text", app: app)
        close.tap()

        XCTAssertTrue(app.navigationBars["Atlas"].waitForExistence(timeout: 5))
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "Tokyo")
        XCTAssertTrue(japan.exists)
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
    }

    @MainActor
    func testGlobePinchExtendsZoomAndStillSelectsTheVisibleCountry() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Discover"].tap()
        let globe = app.descendants(matching: .any)["interactiveGlobe"].firstMatch
        XCTAssertTrue(globe.waitForExistence(timeout: 10))
        waitUntilHittable(globe)
        XCTAssertEqual(globe.value as? String, "100% zoom")
        globe.pinch(withScale: 1.35, velocity: 1)
        let zoomed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "100% zoom"), object: globe)
        XCTAssertEqual(XCTWaiter.wait(for: [zoomed], timeout: 5), .completed)

        // Repeated gestures reach the new limit and cannot overshoot it.
        globe.pinch(withScale: 2, velocity: 1)
        globe.pinch(withScale: 2, velocity: 1)
        waitForValue("197% zoom", on: globe)
        globe.pinch(withScale: 1.3, velocity: 1)
        XCTAssertEqual(globe.value as? String, "197% zoom")
        capture("Globe at the modestly extended zoom limit", app: app)

        // Tap the rendered surface, rather than the overlaid country button,
        // to exercise SceneKit hit testing after the camera has zoomed.
        globe.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let title = app.staticTexts["countryTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertEqual(title.label, "Morocco")
        app.navigationBars["A little more local"].buttons["Close"].tap()
        waitUntilHittable(globe)
        XCTAssertEqual(globe.value as? String, "197% zoom")

        globe.pinch(withScale: 0.4, velocity: -1)
        globe.pinch(withScale: 0.4, velocity: -1)
        waitForValue("72% zoom", on: globe)
        capture("Globe retains its original zoom-out limit", app: app)
    }

    @MainActor
    private func assertCountryRemainsOpen(_ name: String, bookmark: String, app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["A little more local"].exists)
        XCTAssertEqual(app.staticTexts["countryTitle"].label, name)
        let save = app.buttons["saveCountry"]
        waitUntilHittable(save)
        XCTAssertEqual(save.label, bookmark)
        waitUntilHittable(app.navigationBars["A little more local"].buttons["Close"])
    }

    @MainActor
    private func rotate(_ orientation: UIDeviceOrientation, app: XCUIApplication) {
        XCUIDevice.shared.orientation = orientation
        let landscape = orientation.isLandscape
        let geometry = NSPredicate { _, _ in
            MainActor.assumeIsolated {
                landscape ? app.frame.width > app.frame.height : app.frame.height > app.frame.width
            }
        }
        let settled = XCTNSPredicateExpectation(predicate: geometry, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed,
                       "The app window must resize to the requested orientation.")
    }

    @MainActor
    private func waitUntilHittable(_ element: XCUIElement) {
        let hittable = NSPredicate { _, _ in
            MainActor.assumeIsolated { element.exists && element.isHittable }
        }
        let ready = XCTNSPredicateExpectation(predicate: hittable, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed,
                       "Expected an accessible control: \(element)")
    }

    @MainActor
    private func waitForLabel(_ label: String, on element: XCUIElement) {
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
    }

    @MainActor
    private func waitForValue(_ value: String, on element: XCUIElement) {
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

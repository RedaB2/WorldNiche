import XCTest

final class CountryReadingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testOpeningAndFastScrollingDoNotExploreAndPartialProgressSurvivesRelaunch() {
        let app = launch()
        openMorocco(app)
        XCTAssertTrue(progress(app).contains("0 percent"))
        XCTAssertFalse(app.descendants(matching: .any)["countryExplored"].exists)
        app.buttons["toggleCountryGlobe"].tap()
        readStep(app)
        let partial = progress(app)
        XCTAssertFalse(partial.hasPrefix("0 percent"), partial)
        XCTAssertFalse(partial.contains("Explored"))
        app.terminate()
        app.launchArguments = arguments(reset: false)
        app.launch()
        openMorocco(app)
        XCTAssertEqual(progress(app), partial)
        let scroll = app.scrollViews["countryReadingScroll"]
        for _ in 0..<5 { scroll.swipeUp(velocity: .fast) }
        XCTAssertFalse(app.descendants(matching: .any)["countryExplored"].exists)
        XCTAssertFalse(app.buttons["completeCountryExploration"].exists, "A fling cannot credit skipped content")
        capture("Partial reading stays separate from explored", app)
    }

    @MainActor
    func testReadHoldCancelCompleteAndReopen() {
        let app = launch()
        openMorocco(app)
        app.buttons["saveCountry"].tap()
        app.buttons["toggleCountryGlobe"].tap()
        readToEnd(app)
        let finish = app.buttons["completeCountryExploration"]
        XCTAssertTrue(finish.isHittable)
        finish.press(forDuration: 0.25)
        XCTAssertFalse(app.descendants(matching: .any)["countryExplored"].exists, "A released hold must cancel")
        capture("Ready to mark explored", app)
        finish.press(forDuration: 1.2)
        XCTAssertTrue(app.descendants(matching: .any)["countryExplored"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertEqual(progress(app), "Explored")
        capture("Exploration completed", app)
        app.navigationBars["A little more local"].buttons["Close"].tap()
        openMorocco(app, selectAtlas: false)
        XCTAssertEqual(progress(app), "Explored")
        XCTAssertEqual(app.buttons["saveCountry"].label, "Unsave country")
        app.navigationBars["A little more local"].buttons["Close"].tap()
        let searchClose = app.navigationBars["Atlas"].buttons["Close"]
        if searchClose.exists { searchClose.tap() }
        let journal = app.tabBars.buttons["Journal"]
        (journal.exists ? journal : app.buttons["Journal"].firstMatch).tap()
        XCTAssertTrue(app.staticTexts["1"].waitForExistence(timeout: 4))
    }

    @MainActor
    func testPullAndHoldCompletesOnlyAfterReading() {
        let app = launch()
        openMorocco(app)
        app.buttons["toggleCountryGlobe"].tap()
        readToEnd(app)
        let scroll = app.scrollViews["countryReadingScroll"]
        scroll.swipeUp()
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.7))
        let end = start.withOffset(CGVector(dx: 0, dy: -230))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1.3)
        XCTAssertTrue(app.descendants(matching: .any)["countryExplored"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertEqual(progress(app), "Explored")
        capture("Pull and hold completes the discovery", app)
    }

    @MainActor
    func testUnavailableFeedsStillAllowCompletion() {
        let app = launch(mode: "unavailable")
        openMorocco(app)
        app.buttons["toggleCountryGlobe"].tap()
        readToEnd(app)
        XCTAssertTrue(app.buttons["retryMusic"].exists)
        XCTAssertTrue(app.buttons["retryNews"].exists)
        app.buttons["completeCountryExploration"].press(forDuration: 1.2)
        XCTAssertTrue(app.descendants(matching: .any)["countryExplored"].firstMatch.waitForExistence(timeout: 4))
        capture("Unavailable feeds keep exploration usable", app)
    }

    @MainActor
    func testLargeTextReadingAndCompletion() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXL"])
        openMorocco(app)
        app.buttons["toggleCountryGlobe"].tap()
        readToEnd(app, limit: 85)
        app.buttons["completeCountryExploration"].press(forDuration: 1.2)
        XCTAssertTrue(app.descendants(matching: .any)["countryExplored"].firstMatch.waitForExistence(timeout: 4))
        capture("Large text exploration completed", app)
    }

    @MainActor
    private func arguments(reset: Bool = true, mode: String = "ready") -> [String] {
        ["-worldniche-skip-intro", "-worldniche-journal-fixture", reset ? "reading-reset" : "resume",
         "-worldniche-reading-fixture", mode]
    }

    @MainActor
    private func launch(mode: String = "ready", extra: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = arguments(mode: mode) + extra
        app.launch()
        return app
    }

    @MainActor
    private func openMorocco(_ app: XCUIApplication, selectAtlas: Bool = true) {
        if selectAtlas {
            let atlas = app.tabBars.buttons["Atlas"]
            (atlas.exists ? atlas : app.buttons["Atlas"].firstMatch).tap()
        }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        if search.value as? String != "Morocco" {
            search.tap()
            search.typeText("Morocco")
        }
        app.buttons.containing(.staticText, identifier: "Morocco").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["countryTitle"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func progress(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any)["countryReadingProgress"].firstMatch.value as? String ?? "missing"
    }

    @MainActor
    private func readStep(_ app: XCUIApplication) {
        let scroll = app.scrollViews["countryReadingScroll"]
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.70))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.42))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        Thread.sleep(forTimeInterval: 0.85)
    }

    @MainActor
    private func readToEnd(_ app: XCUIApplication, limit: Int = 32) {
        let finish = app.buttons["completeCountryExploration"]
        for _ in 0..<limit {
            if finish.exists && finish.isHittable { return }
            let more = app.buttons["continueCountryReading"]
            if more.exists && more.isHittable {
                more.tap()
                Thread.sleep(forTimeInterval: 1.1)
            } else { readStep(app) }
        }
        XCTFail("Could not finish reading: \(progress(app))\n\(app.debugDescription)")
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let content = app.scrollViews["countryReadingScroll"]
        let attachment = XCTAttachment(screenshot: content.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

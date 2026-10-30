import XCTest

/// Live provider smoke checks, run separately from deterministic feed checks.
final class NewsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testMoroccoShowsLicensedNewsWithBylinesAndDates() {
        let app = XCUIApplication()
        app.launchArguments = ["-worldniche-skip-intro", "-worldniche-journal-fixture", "reset"]
        app.launch()
        let landing = app.buttons["landingCountry"]
        XCTAssertTrue(landing.waitForExistence(timeout: 10))
        landing.tap()
        XCTAssertTrue(app.staticTexts["countryTitle"].waitForExistence(timeout: 8))
        let source = app.staticTexts["GLOBAL VOICES"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 30), "The live Morocco feed should load")
        let scroll = app.scrollViews.containing(.staticText, identifier: "countryTitle").firstMatch
        XCTAssertTrue(scroll.exists)
        reveal(source, in: scroll)
        XCTAssertTrue(source.isHittable)
        let author = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "By ")).firstMatch
        XCTAssertTrue(author.exists)
        let license = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Headlines: CC BY 3.0")).firstMatch
        reveal(license, in: scroll)
        XCTAssertTrue(license.isHittable)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Google News")).firstMatch.exists)
        capture("Morocco licensed news", app)
    }

    @MainActor
    func testIntroLoadsLiveUnitedStatesNewsWithAttribution() {
        let app = XCUIApplication()
        app.launchArguments = ["-worldniche-intro-fixture", "fresh"]
        app.launch()
        XCTAssertTrue(app.buttons["introContinue"].waitForExistence(timeout: 10))
        app.buttons["introContinue"].tap()
        let news = app.buttons["introNewsPreview"]
        XCTAssertTrue(news.waitForExistence(timeout: 5))
        news.tap()
        let story = app.descendants(matching: .any)["introStory0"].firstMatch
        XCTAssertTrue(story.waitForExistence(timeout: 30))
        let author = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "By ")).firstMatch
        XCTAssertTrue(author.exists)
        let license = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Headlines: CC BY 3.0")).firstMatch
        let scroll = app.descendants(matching: .any)["introScroll1"].firstMatch
        for _ in 0..<5 where !license.isHittable { scroll.swipeUp() }
        XCTAssertTrue(license.isHittable)
        capture("Intro licensed news", app)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in scroll: XCUIElement) {
        // Short swipes stay inside the sheet and do not jump over a headline.
        for _ in 0..<24 where !element.isHittable {
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}

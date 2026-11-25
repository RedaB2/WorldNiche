import XCTest

final class CountryReadingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testOverviewHistoricalSourceAndChartAcrossCountries() {
        let app = launch()
        let examples = [("Morocco", "Fatima"), ("Japan", "Shirakawa"), ("Peru", "Machu Picchu")]
        for (index, example) in examples.enumerated() {
            let (country, topic) = example
            openCountry(country, in: app, selectAtlas: index == 0)
            let overview = app.staticTexts["countryOverview"]
            let title = app.staticTexts["historicalFactTitle"]
            let body = app.staticTexts["historicalFactBody"]
            let source = app.descendants(matching: .any)["historicalFactSource"].firstMatch
            XCTAssertFalse(overview.label.isEmpty)
            let population = app.descendants(matching: .any)["countryPopulation"].firstMatch
            XCTAssertNotNil(population.label.range(of: #"\b20\d{2}\b"#, options: .regularExpression))
            XCTAssertFalse(app.staticTexts["In the conversation"].exists)
            app.buttons["toggleCountryGlobe"].tap()
            XCTAssertLessThan(overview.frame.maxY, title.frame.minY)
            XCTAssertTrue((title.label + " " + body.label).localizedCaseInsensitiveContains(topic))
            XCTAssertTrue(source.exists)
            let firstTrack = app.descendants(matching: .any)["musicTrack-0"].firstMatch
            let fifthTrack = app.descendants(matching: .any)["musicTrack-4"].firstMatch
            XCTAssertTrue(fifthTrack.exists)
            XCTAssertLessThan(source.frame.maxY, firstTrack.frame.minY)
            for _ in 0..<10 where !source.isHittable { readStep(app) }
            XCTAssertTrue(source.isHittable)
            capture("\(country) historical fact and source", app)
            app.navigationBars["A little more local"].buttons["Close"].tap()
        }
    }

    @MainActor
    func testSharedExplorationFollowsChartAndShowsFriend() {
        let app = XCUIApplication()
        app.launchArguments = ["-worldniche-skip-intro", "-worldniche-social-fixture", "marketing",
                               "-worldniche-reading-fixture", "ready"]
        app.launch()
        app.buttons["landingCountry"].tap()
        app.buttons["toggleCountryGlobe"].tap()
        let friends = app.buttons["Friends"]
        let name = app.staticTexts["Jun"]
        for _ in 0..<32 where !name.isHittable { readStep(app) }
        XCTAssertTrue(name.isHittable, app.debugDescription)
        XCTAssertTrue(friends.isHittable)
        let track = app.descendants(matching: .any)["musicTrack-4"].firstMatch
        XCTAssertLessThan(track.frame.maxY, friends.frame.minY)
        let disclaimers = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "physical visit", "a country contains many cultures"))
        XCTAssertEqual(disclaimers.count, 0)
        capture("Morocco chart and explored together", app)
    }

    @MainActor
    func testNextFactPersistsAndMatchesTheCompanionSourceWhenMusicIsUnavailable() {
        let app = launch(mode: "unavailable")
        openMorocco(app)
        app.buttons["toggleCountryGlobe"].tap()
        let title = app.staticTexts["historicalFactTitle"]
        let original = title.label
        let next = app.buttons["nextHistoricalFact"]
        for _ in 0..<12 where !next.isHittable { readStep(app) }
        XCTAssertTrue(next.isHittable)
        next.tap()
        let selected = title.label
        XCTAssertNotEqual(selected, original)
        app.buttons["askNiche"].tap()
        let source = app.descendants(matching: .any)["companionHistoricalSource"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(source.label.contains(selected), source.label)
        XCTAssertTrue(app.descendants(matching: .any)["companionPopulationSource"].firstMatch.exists)
        app.terminate()
        app.launchArguments = arguments(reset: false, mode: "unavailable")
        app.launch()
        openMorocco(app)
        XCTAssertEqual(title.label, selected)
    }

    @MainActor
    func testRadioChartShowsStationSampleAndProviderCredit() {
        let app = launch(mode: "radio")
        openCountry("Cuba", in: app)
        app.buttons["toggleCountryGlobe"].tap()
        XCTAssertTrue(app.staticTexts["TUNEPING · CUBA"].exists)
        let track = app.descendants(matching: .any)["musicTrack-0"].firstMatch
        XCTAssertTrue(track.label.contains("2 plays · 1 station"))
        let credit = app.descendants(matching: .any)["Data by Tuneping"].firstMatch
        for _ in 0..<16 where !credit.isHittable { readStep(app) }
        XCTAssertTrue(credit.isHittable)
    }

    @MainActor
    func testTakeMeSomewhereRequiresCompletionAndSharesProgressWithAtlas() {
        let app = launch()
        let landing = app.buttons["landingCountry"]
        XCTAssertTrue(landing.waitForExistence(timeout: 8))
        let original = landing.label
        app.buttons["spinButton"].tap()
        expectation(for: NSPredicate(format: "label != %@", original), evaluatedWith: landing)
        waitForExpectations(timeout: 8)
        landing.tap()
        XCTAssertTrue(app.staticTexts["countryTitle"].waitForExistence(timeout: 5))
        let country = app.staticTexts["countryTitle"].label
        capture("Random country starts unexplored", app)
        XCTAssertEqual(progress(app), "0 percent", "Choosing a destination must not mark it explored")
        app.navigationBars["A little more local"].buttons["Close"].tap()
        let journal = app.tabBars.buttons["Journal"]
        (journal.exists ? journal : app.buttons["Journal"].firstMatch).tap()
        XCTAssertTrue(app.staticTexts["0"].waitForExistence(timeout: 4), "Choosing a destination must not add journal history")

        openCountry(country, in: app)
        XCTAssertEqual(progress(app), "0 percent")
        app.buttons["toggleCountryGlobe"].tap()
        readStep(app)
        let partial = progress(app)
        XCTAssertGreaterThan(percentage(app), 0)
        app.navigationBars["A little more local"].buttons["Close"].tap()
        let searchClose = app.navigationBars["Atlas"].buttons["Close"]
        if searchClose.exists { searchClose.tap() }
        let discover = app.tabBars.buttons["Discover"]
        (discover.exists ? discover : app.buttons["Discover"].firstMatch).tap()
        landing.tap()
        XCTAssertTrue(app.staticTexts["countryTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["countryTitle"].label, country)
        XCTAssertEqual(progress(app), partial, "Discover and Atlas must share the same saved progress")
        app.buttons["toggleCountryGlobe"].tap()
        readToEnd(app)
        app.buttons["completeCountryExploration"].press(forDuration: 1.2)
        XCTAssertTrue(app.descendants(matching: .any)["countryExplored"].firstMatch.waitForExistence(timeout: 4))
        app.navigationBars["A little more local"].buttons["Close"].tap()
        (journal.exists ? journal : app.buttons["Journal"].firstMatch).tap()
        XCTAssertTrue(app.staticTexts["1"].waitForExistence(timeout: 4))
        openCountry(country, in: app)
        XCTAssertEqual(progress(app), "Explored")
    }

    @MainActor
    func testScrollProgressOnlyIncreasesAndSurvivesRelaunch() {
        let app = launch()
        openMorocco(app)
        XCTAssertTrue(progress(app).contains("0 percent"))
        XCTAssertFalse(app.descendants(matching: .any)["countryExplored"].exists)
        app.buttons["toggleCountryGlobe"].tap()
        readStep(app)
        let first = percentage(app)
        XCTAssertGreaterThan(first, 0)
        readStep(app)
        XCTAssertGreaterThan(percentage(app), first, "Each further scroll advances the page percentage")
        let partial = progress(app)
        XCTAssertFalse(partial.contains("Explored"))
        app.scrollViews["countryReadingScroll"].swipeDown()
        XCTAssertEqual(progress(app), partial, "Scrolling back must keep the furthest percentage")
        capture("Scrolling back keeps the earned progress", app)
        app.terminate()
        app.launchArguments = arguments(reset: false)
        app.launch()
        openMorocco(app)
        XCTAssertEqual(progress(app), partial)
        app.buttons["toggleCountryGlobe"].tap()
        let scroll = app.scrollViews["countryReadingScroll"]
        for _ in 0..<5 { scroll.swipeUp(velocity: .fast) }
        XCTAssertFalse(app.descendants(matching: .any)["countryExplored"].exists)
        XCTAssertEqual(percentage(app), 100, "Progress follows the page distance even during a fast scroll")
        XCTAssertTrue(app.buttons["completeCountryExploration"].exists, "Reaching the end unlocks confirmation")
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
    func testUnavailableChartKeepsReadingAndCompletionAvailable() {
        let app = launch(mode: "unavailable")
        openMorocco(app)
        app.buttons["toggleCountryGlobe"].tap()
        readToEnd(app)
        XCTAssertTrue(app.buttons["retryMusic"].exists)
        XCTAssertTrue(app.staticTexts["historicalFactBody"].exists)
        XCTAssertTrue(app.staticTexts["countryOverview"].exists)
        app.buttons["completeCountryExploration"].press(forDuration: 1.2)
        XCTAssertTrue(app.descendants(matching: .any)["countryExplored"].firstMatch.waitForExistence(timeout: 4))
        capture("Unavailable chart keeps exploration usable", app)
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
        openCountry("Morocco", in: app, selectAtlas: selectAtlas)
    }

    @MainActor
    private func openCountry(_ country: String, in app: XCUIApplication, selectAtlas: Bool = true) {
        if selectAtlas {
            let atlas = app.tabBars.buttons["Atlas"]
            (atlas.exists ? atlas : app.buttons["Atlas"].firstMatch).tap()
        }
        let search = app.searchFields.firstMatch
        if !search.exists { app.scrollViews.firstMatch.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        if search.value as? String != country {
            search.tap()
            if let value = search.value as? String, !value.isEmpty, value != search.placeholderValue {
                search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
            }
            search.typeText(country)
        }
        app.buttons.containing(.staticText, identifier: country).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["countryTitle"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func progress(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any)["countryReadingProgress"].firstMatch.value as? String ?? "missing"
    }

    @MainActor
    private func percentage(_ app: XCUIApplication) -> Int {
        Int(progress(app).split(separator: " ").first ?? "") ?? -1
    }

    @MainActor
    private func readStep(_ app: XCUIApplication) {
        let scroll = app.scrollViews["countryReadingScroll"]
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.70))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.42))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    @MainActor
    private func readToEnd(_ app: XCUIApplication, limit: Int = 32) {
        let finish = app.buttons["completeCountryExploration"]
        for _ in 0..<limit {
            if finish.exists && finish.isHittable,
               finish.frame.maxY + 40 < app.buttons["askNiche"].frame.minY { return }
            readStep(app)
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

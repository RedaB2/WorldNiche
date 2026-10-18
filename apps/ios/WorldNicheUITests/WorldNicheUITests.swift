import XCTest

final class WorldNicheUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testInvitationSheetFromWarmAndColdURLLaunch() throws {
        let app = XCUIApplication()
        // Invalid input still presents the real invitation sheet, without
        // touching a hosted invitation or requiring an authenticated account.
        let url = try XCTUnwrap(URL(string: "worldniche://invite/not-a-valid-token"))
        app.launch()
        app.open(url)
        assertInvitationRemainsInteractive(app)

        app.terminate()
        app.open(url)
        assertInvitationRemainsInteractive(app)
    }

    @MainActor
    private func assertInvitationRemainsInteractive(_ app: XCUIApplication) {
        let navigation = app.navigationBars["Friend invitation"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["invitationError"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
        navigation.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["landingCountry"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCountryDiscoveryAndSavedJournal() throws {
        let app = XCUIApplication()
        app.launch()
        let landing = app.buttons["landingCountry"]
        XCTAssertTrue(landing.waitForExistence(timeout: 15))
        capture("Discover", app: app)
        let original = landing.label
        app.buttons["spinButton"].tap()
        let changed = NSPredicate(format: "label != %@", original)
        expectation(for: changed, evaluatedWith: landing)
        waitForExpectations(timeout: 8)
        landing.tap()
        XCTAssertTrue(app.staticTexts["countryTitle"].waitForExistence(timeout: 10))
        let country = app.staticTexts["countryTitle"].label
        let save = app.buttons["saveCountry"]
        if save.label == "Unsave country" { save.tap() }
        save.tap()
        XCTAssertEqual(save.label, "Unsave country")
        capture("Country", app: app)
        waitForCompanion(app)
        app.buttons["askNiche"].tap()
        XCTAssertTrue(app.navigationBars["Ask Niche"].waitForExistence(timeout: 8))
        capture("Ask Niche", app: app)
        app.buttons["Close companion"].tap()
        app.buttons["Close"].firstMatch.tap()
        app.tabBars.buttons["Journal"].tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: country).firstMatch.waitForExistence(timeout: 5))
        capture("Journal", app: app)
        app.terminate()
        app.launch()
        app.tabBars.buttons["Journal"].tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: country).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testAtlasSearch() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Atlas"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 6))
        search.tap()
        search.typeText("Japan")
        let country = app.buttons.containing(.staticText, identifier: "Japan").firstMatch
        XCTAssertTrue(country.waitForExistence(timeout: 5))
        country.tap()
        XCTAssertTrue(app.staticTexts["countryTitle"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["countryTitle"].label, "Japan")
        capture("Japan", app: app)
    }

    @MainActor
    func testAtlasRegionFiltersAndLargeText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXL"]
        app.launch()
        app.tabBars.buttons["Atlas"].tap()
        let america = app.buttons["Americas"]
        if !america.isHittable { app.scrollViews.firstMatch.swipeLeft() }
        america.tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Antigua and Barbuda").firstMatch.waitForExistence(timeout: 5))
        let oceania = app.buttons["Oceania"]
        oceania.tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Australia").firstMatch.waitForExistence(timeout: 5))
        capture("Atlas accessibility text", app: app)
    }

    @MainActor
    func testCompanionRespondsWhenModelIsAvailable() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["landingCountry"].tap()
        waitForCompanion(app)
        app.buttons["askNiche"].tap()
        let input = app.descendants(matching: .any)["questionInput"].firstMatch
        guard input.waitForExistence(timeout: 8) else {
            throw XCTSkip("Apple Intelligence is unavailable on this simulator; availability UI remains accessible.")
        }
        input.tap()
        input.typeText("Give me one simple question I can ask about the cultural note shown here.")
        app.buttons["Send question"].tap()
        XCTAssertTrue(app.staticTexts["assistantMessage"].firstMatch.waitForExistence(timeout: 45))
        let message = app.staticTexts["assistantMessage"].firstMatch.label
        XCTAssertGreaterThan(message.count, 10)
        capture("Companion response", app: app)
    }

    @MainActor
    func testLiveDiscoveryCanRotate() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["landingCountry"].tap()
        let title = app.staticTexts["liveCultureTitle"]
        guard title.waitForExistence(timeout: 40) else {
            throw XCTSkip("The public cultural service did not respond; fallback remains dated.")
        }
        let original = title.label
        capture("Live discovery", app: app)
        let another = app.buttons["anotherDiscovery"]
        for _ in 0..<5 where !another.isHittable { app.swipeUp() }
        another.tap()
        let changed = NSPredicate(format: "label != %@", original)
        expectation(for: changed, evaluatedWith: title)
        waitForExpectations(timeout: 40)
        app.swipeDown()
        capture("Another live discovery", app: app)
    }

    @MainActor
    private func waitForCompanion(_ app: XCUIApplication) {
        let button = app.buttons["askNiche"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: button)
        waitForExpectations(timeout: 45)
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

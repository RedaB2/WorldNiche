import XCTest

final class WorldNicheUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testDiscoverGuidanceAppearsAboveInteractiveGlobe() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Discover"].tap()
        assertDiscoverGuidanceOrdering(app)
        let globe = app.descendants(matching: .any)["interactiveGlobe"].firstMatch
        XCTAssertEqual(globe.label, "Interactive world globe")
        XCTAssertTrue(globe.isHittable)
        globe.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: globe.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.45)))
        XCTAssertTrue(globe.isHittable)
        capture("Discover guidance above globe", app: app)
        let landing = app.buttons["landingCountry"]
        XCTAssertTrue(landing.isHittable)
        landing.tap()
        XCTAssertTrue(app.staticTexts["countryTitle"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["countryTitle"].label, "Morocco")
    }

    @MainActor
    func testDiscoverGuidanceLargeTextKeepsCountryControlsAccessible() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXL"]
        app.launch()
        app.tabBars.buttons["Discover"].tap()
        assertDiscoverGuidanceOrdering(app)
        let guidance = app.staticTexts["discoverGuidance"]
        XCTAssertGreaterThanOrEqual(guidance.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(guidance.frame.maxX, app.frame.maxX)
        capture("Discover guidance with large text", app: app)
        let spin = app.buttons["spinButton"]
        if !spin.isHittable {
            // A swipe starting inside SceneKit rotates the globe. Start on
            // the guidance to exercise the surrounding page's scroll gesture.
            XCTAssertTrue(guidance.isHittable)
            guidance.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        }
        XCTAssertTrue(spin.isHittable)
        let landing = app.buttons["landingCountry"]
        let original = landing.label
        spin.tap()
        expectation(for: NSPredicate(format: "label != %@", original), evaluatedWith: landing)
        waitForExpectations(timeout: 8)
        for _ in 0..<5 where !landing.isHittable { app.swipeDown() }
        XCTAssertTrue(landing.isHittable)
        landing.tap()
        XCTAssertTrue(app.staticTexts["countryTitle"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func assertDiscoverGuidanceOrdering(_ app: XCUIApplication) {
        let headline = app.staticTexts["discoverHeadline"]
        let guidance = app.staticTexts["discoverGuidance"]
        let globe = app.descendants(matching: .any)["interactiveGlobe"].firstMatch
        XCTAssertTrue(headline.waitForExistence(timeout: 10))
        XCTAssertTrue(guidance.exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "discoverGuidance").count, 1)
        XCTAssertEqual(guidance.label, "Turn the globe. Tap a country. Stay curious.")
        XCTAssertTrue(globe.exists)
        XCTAssertGreaterThan(guidance.frame.height, 0)
        XCTAssertLessThanOrEqual(headline.frame.maxY, guidance.frame.minY)
        XCTAssertLessThanOrEqual(guidance.frame.maxY, globe.frame.minY)
    }

    @MainActor
    func testNewAccountSharingStartsOnAndCanBeDisabled() throws {
        let app = XCUIApplication()
        openSignedOutSignIn(app)
        let sharing = app.switches["signUpSharingToggle"]
        XCTAssertTrue(sharing.waitForExistence(timeout: 5))
        XCTAssertEqual(sharing.value as? String, "1")
        for _ in 0..<3 where !sharing.isHittable { app.swipeUp() }
        XCTAssertTrue(sharing.isHittable)
        // SwiftUI can expose the entire labeled row as the switch frame.
        // Tap its trailing control and wait for the native value transition.
        sharing.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == %@", "0"), evaluatedWith: sharing)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(sharing.value as? String, "0")
        capture("New account sharing disabled before sign-in", app: app)
        app.navigationBars["Sign in"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAppleSignInIsVisibleAndEmailRecoveryIsOptIn() throws {
        let app = XCUIApplication()
        openSignedOutSignIn(app)
        let apple = app.buttons["signInWithApple"]
        XCTAssertTrue(apple.waitForExistence(timeout: 5))
        for _ in 0..<3 where apple.frame.midY >= app.frame.maxY - 50 { app.swipeUp() }
        XCTAssertTrue(app.frame.contains(CGPoint(x: apple.frame.midX, y: apple.frame.midY)))
        let email = app.textFields["signInEmailField"]
        XCTAssertFalse(email.exists)
        let recover = app.buttons["recoverEmailAccount"]
        for _ in 0..<3 where !recover.isHittable { app.swipeUp() }
        XCTAssertTrue(recover.isHittable)
        recover.tap()
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        XCTAssertTrue(email.isHittable)
        XCTAssertFalse(app.buttons["recoverEmailAccount"].exists)
        email.typeText("not-an-address")
        XCTAssertFalse(app.buttons["requestEmailCode"].isEnabled)
        XCTAssertFalse(app.textFields["emailCodeField"].exists)
        capture("Existing email account recovery", app: app)
        app.navigationBars["Sign in"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func openSignedOutSignIn(_ app: XCUIApplication) {
        app.launch()
        app.tabBars.buttons["Profile"].tap()
        let signIn = app.buttons["signInForFriends"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 8), "Run this check with a signed-out simulator.")
        for _ in 0..<4 where !signIn.isHittable { app.swipeUp() }
        XCTAssertTrue(signIn.isHittable)
        signIn.tap()
        XCTAssertTrue(app.navigationBars["Sign in"].waitForExistence(timeout: 5))
    }

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

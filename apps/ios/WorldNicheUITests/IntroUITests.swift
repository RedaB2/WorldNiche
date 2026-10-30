import XCTest

final class IntroUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testSkipIntroExploresWithoutAnAccountAndStaysDismissed() {
        let app = launchIntro()
        XCTAssertTrue(app.staticTexts["introTitle0"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["introSkip"].isHittable)
        app.buttons["introSkip"].tap()
        assertDiscovery(app)
        app.terminate()
        app.launchArguments = ["-worldniche-intro-fixture", "resume"]
        app.launch()
        assertDiscovery(app)
        XCTAssertFalse(app.buttons["introSkip"].exists)
    }

    @MainActor
    func testIntroExplainsDiscoveryAndAllowsGuestCompletion() {
        let app = launchIntro()
        XCTAssertTrue(app.buttons["introContinue"].waitForExistence(timeout: 8))
        app.buttons["introContinue"].tap()
        XCTAssertTrue(app.staticTexts["introTitle1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["introSkip"].isHittable)
        app.buttons["introBack"].tap()
        XCTAssertTrue(app.staticTexts["introTitle0"].waitForExistence(timeout: 5))
        app.buttons["introContinue"].tap()
        app.buttons["introContinue"].tap()
        XCTAssertTrue(app.staticTexts["introTitle2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["introAccountEntry"].isHittable)
        XCTAssertTrue(app.buttons["introContinueExploring"].isHittable)
        app.buttons["introContinueExploring"].tap()
        assertDiscovery(app)
    }

    @MainActor
    func testIntroSignupOpensNativeSignInAndCancellationKeepsAppAvailable() {
        let app = launchIntro()
        XCTAssertTrue(app.buttons["introContinue"].waitForExistence(timeout: 8))
        app.buttons["introContinue"].tap()
        app.buttons["introContinue"].tap()
        XCTAssertTrue(app.buttons["introAccountEntry"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["introAccountEntry"].label, "Continue with Apple")
        app.buttons["introAccountEntry"].tap()
        XCTAssertTrue(app.buttons["signInWithApple"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textFields["signInEmailField"].exists)
        app.navigationBars["Sign in"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["introSkip"].exists)
        discoveryDestination(app).tap()
        assertDiscovery(app)
    }

    @MainActor
    func testIntroLargeTextKeepsSkipAndGuestActionsReachable() {
        let app = launchIntro(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXL"])
        XCTAssertTrue(app.buttons["introSkip"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["introSkip"].isHittable)
        app.buttons["introContinue"].tap()
        app.buttons["introContinue"].tap()
        XCTAssertTrue(app.buttons["introContinueExploring"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["introContinueExploring"].isHittable)
        app.buttons["introContinueExploring"].tap()
        assertDiscovery(app)
    }

    @MainActor
    private func launchIntro(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-worldniche-intro-fixture", "fresh"] + extra
        app.launch()
        return app
    }

    @MainActor
    private func assertDiscovery(_ app: XCUIApplication) {
        XCTAssertTrue(discoveryDestination(app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["discoverHeadline"].exists)
        XCTAssertFalse(app.buttons["signInWithApple"].exists)
    }

    @MainActor
    private func discoveryDestination(_ app: XCUIApplication) -> XCUIElement {
        let tab = app.tabBars.buttons["Discover"]
        return tab.exists ? tab : app.buttons["Discover"].firstMatch
    }
}

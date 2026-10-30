import XCTest

final class IntroInteractionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testDemoGlobeCanTurnAndZoomWithoutOpeningACountry() {
        let app = launchIntro()
        let globe = element("introDemoGlobe", in: app)
        reveal(globe, on: 0, in: app)
        XCTAssertEqual(globe.value as? String, "100% zoom")
        globe.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: globe.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)))
        globe.pinch(withScale: 1.3, velocity: 1)
        let zoomed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "100% zoom"), object: globe)
        XCTAssertEqual(XCTWaiter.wait(for: [zoomed], timeout: 5), .completed)
        globe.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["introContinue"].isHittable)
        XCTAssertTrue(app.buttons["introSkip"].exists)
        XCTAssertFalse(app.staticTexts["discoverHeadline"].exists)
        XCTAssertFalse(app.buttons["signInWithApple"].exists)
        app.buttons["introContinue"].tap()
        XCTAssertTrue(app.buttons["introMusicPreview"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPreviewsExpandOneAtATimeAndCanCollapse() {
        let app = launchIntro()
        app.buttons["introContinue"].tap()
        let music = app.buttons["introMusicPreview"]
        reveal(music, on: 1, in: app)
        XCTAssertEqual(music.value as? String, "Collapsed")
        music.tap()
        XCTAssertTrue(element("introMusicContent", in: app).waitForExistence(timeout: 5))
        for index in 0..<5 { XCTAssertTrue(element("introTrack\(index)", in: app).exists) }
        XCTAssertEqual(music.value as? String, "Expanded")
        XCTAssertFalse(element("introNewsContent", in: app).exists)
        XCTAssertFalse(element("introCultureContent", in: app).exists)

        let news = app.buttons["introNewsPreview"]
        reveal(news, on: 1, in: app)
        news.tap()
        XCTAssertTrue(element("introNewsContent", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("introMusicContent", in: app).exists)
        XCTAssertEqual(music.value as? String, "Collapsed")

        let culture = app.buttons["introCulturePreview"]
        reveal(culture, on: 1, in: app)
        culture.tap()
        XCTAssertTrue(element("introCultureContent", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("introNewsContent", in: app).exists)
        XCTAssertFalse(element("introMusicContent", in: app).exists)
        reveal(culture, on: 1, in: app)
        culture.tap()
        XCTAssertEqual(culture.value as? String, "Collapsed")
        XCTAssertFalse(element("introCultureContent", in: app).exists)
        XCTAssertTrue(app.buttons["introContinue"].isHittable)
    }

    @MainActor
    func testMusicRetryKeepsNewsUsableAndDoesNotOpenBothPanels() {
        let app = launchIntro(previews: "music-retry")
        app.buttons["introContinue"].tap()
        let music = app.buttons["introMusicPreview"]
        reveal(music, on: 1, in: app)
        music.tap()
        XCTAssertTrue(app.buttons["introMusicRetry"].waitForExistence(timeout: 5))
        let news = app.buttons["introNewsPreview"]
        reveal(news, on: 1, in: app)
        news.tap()
        XCTAssertTrue(element("introNewsContent", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["introMusicRetry"].exists)
        reveal(music, on: 1, in: app)
        music.tap()
        let retry = app.buttons["introMusicRetry"]
        reveal(retry, on: 1, in: app)
        retry.tap()
        XCTAssertTrue(element("introTrack4", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["introMusicRetry"].exists)
        XCTAssertFalse(element("introNewsContent", in: app).exists)
    }

    @MainActor
    func testLargeTextKeepsInteractivePreviewAndSignupActionsReachable() {
        let app = launchIntro(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXL"])
        XCTAssertTrue(app.buttons["introSkip"].isHittable)
        app.buttons["introContinue"].tap()
        let music = app.buttons["introMusicPreview"]
        reveal(music, on: 1, in: app)
        music.tap()
        let lastSong = element("introTrack4", in: app)
        reveal(lastSong, on: 1, in: app)
        assertFitsWindow(lastSong, in: app)
        XCTAssertTrue(app.buttons["introContinue"].isHittable)
        app.buttons["introContinue"].tap()
        let invite = element("introInviteAnimation", in: app)
        reveal(invite, on: 2, in: app)
        assertFitsWindow(invite, in: app)
        XCTAssertTrue(app.buttons["introAccountEntry"].isHittable)
        XCTAssertTrue(app.buttons["introContinueExploring"].isHittable)
        app.buttons["introContinueExploring"].tap()
        XCTAssertTrue(app.staticTexts["discoverHeadline"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testReducedMotionShowsAConnectedPairAndAppleOnlySignup() {
        let app = launchIntro(extra: ["-worldniche-intro-reduced-motion"])
        app.buttons["introContinue"].tap()
        app.buttons["introContinue"].tap()
        let invite = element("introInviteAnimation", in: app)
        reveal(invite, on: 2, in: app)
        XCTAssertEqual(invite.label, "An invitation connects two friends")
        XCTAssertEqual(invite.value as? String, "Connected")
        app.buttons["introAccountEntry"].tap()
        XCTAssertTrue(app.buttons["signInWithApple"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["recoverEmailAccount"].exists)
        XCTAssertFalse(app.textFields["signInEmailField"].exists)
        XCTAssertFalse(app.buttons["requestEmailCode"].exists)
    }

    @MainActor
    private func launchIntro(previews: String = "ready", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-worldniche-intro-fixture", "fresh", "-worldniche-intro-previews-fixture", previews] + extra
        app.launch()
        XCTAssertTrue(app.buttons["introContinue"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func reveal(_ element: XCUIElement, on page: Int, in app: XCUIApplication) {
        let scroll = self.element("introScroll\(page)", in: app)
        XCTAssertTrue(scroll.exists, app.debugDescription)
        for _ in 0..<8 where !element.isHittable { scroll.swipeUp() }
        if !element.isHittable {
            for _ in 0..<8 where !element.isHittable { scroll.swipeDown() }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    @MainActor
    private func assertFitsWindow(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.containing(.any, identifier: element.identifier).firstMatch
        XCTAssertTrue(window.exists)
        XCTAssertGreaterThan(element.frame.width, 0)
        XCTAssertGreaterThanOrEqual(element.frame.minX, window.frame.minX)
        XCTAssertLessThanOrEqual(element.frame.maxX, window.frame.maxX)
    }
}

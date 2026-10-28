import XCTest

final class ProfileSetupUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testChosenNameOptionalPhotoAndRememberedConsent() {
        let app = openSetup()
        let name = app.textFields["profileNameField"]
        XCTAssertEqual(name.value as? String, "Your name")
        for _ in 0..<7 where !app.buttons["completeProfileSetup"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["completeProfileSetup"].exists)
        XCTAssertFalse(app.buttons["completeProfileSetup"].isEnabled)
        XCTAssertFalse(app.staticTexts["Explorer"].exists)
        for _ in 0..<7 where !name.isHittable { app.swipeDown() }
        XCTAssertTrue(name.isHittable)
        name.tap()
        name.typeText("Mira Sun")
        dismissNameKeyboard(name, in: app)
        let sharing = app.switches["profileSharingToggle"]
        reveal(sharing, in: app)
        XCTAssertEqual(sharing.value as? String, "1")
        let consent = app.staticTexts["signupProfileConsent"]
        reveal(consent, in: app)
        XCTAssertTrue(consent.label.contains("OpenAI"))
        XCTAssertTrue(app.buttons["completeProfileWithoutChecks"].exists)
        let finish = app.buttons["completeProfileSetup"]
        reveal(finish, in: app)
        capture("Chosen profile with one-time consent", app)
        finish.tap()
        XCTAssertTrue(app.buttons["editProfile"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["profileName"].label, "Mira Sun")
        XCTAssertFalse(app.staticTexts["Explorer"].exists)
        XCTAssertFalse(app.buttons["removeProfilePhoto"].exists)
        capture("Profile uses initials without a photo", app)

        app.buttons["editProfile"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        assertNormalEditHasNoConsentControls(app)
        for _ in 0..<7 where !name.isHittable { app.swipeDown() }
        XCTAssertTrue(name.isHittable)
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "Mira Moon")
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.buttons["editProfile"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["profileName"].label, "Mira Moon")
        XCTAssertFalse(app.buttons["Allow quick checks and save"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "OpenAI")).firstMatch.exists)
        app.buttons["profileSettings"].tap()
        let remembered = app.switches["automaticProfileChecks"]
        reveal(remembered, in: app)
        XCTAssertEqual(remembered.value as? String, "1")
    }

    @MainActor
    func testSetupAllowsSharingOffAndDecliningAutomaticChecks() {
        let app = openSetup()
        let name = app.textFields["profileNameField"]
        name.tap(); name.typeText("Mira Lake")
        dismissNameKeyboard(name, in: app)
        let sharing = app.switches["profileSharingToggle"]
        reveal(sharing, in: app)
        XCTAssertEqual(sharing.value as? String, "1")
        sharing.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(sharing.value as? String, "0")
        let consent = app.staticTexts["signupProfileConsent"]
        reveal(consent, in: app)
        XCTAssertTrue(consent.label.contains("OpenAI"))
        let finish = app.buttons["completeProfileWithoutChecks"]
        reveal(finish, in: app); finish.tap()
        XCTAssertTrue(app.buttons["editProfile"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["profileName"].label, "Mira Lake")
        app.buttons["profileSettings"].tap()
        let savedSharing = app.switches["settingsSharingToggle"]
        reveal(savedSharing, in: app)
        XCTAssertEqual(savedSharing.value as? String, "0")
        let savedConsent = app.switches["automaticProfileChecks"]
        reveal(savedConsent, in: app)
        XCTAssertEqual(savedConsent.value as? String, "0")
        capture("Signup preserves both privacy choices", app)
    }

    @MainActor
    func testExistingProfileKeepsSharingAndConsentOff() {
        let app = XCUIApplication()
        app.launchArguments = ["-worldniche-skip-intro", "-worldniche-social-fixture", "existing-private"]
        app.launch()
        openProfileDestination(app)
        XCTAssertTrue(app.buttons["editProfile"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["completeProfileSetup"].exists)
        app.buttons["profileSettings"].tap()
        let sharing = app.switches["settingsSharingToggle"]
        reveal(sharing, in: app)
        XCTAssertEqual(sharing.value as? String, "0")
        let consent = app.switches["automaticProfileChecks"]
        reveal(consent, in: app)
        XCTAssertEqual(consent.value as? String, "0")
        app.navigationBars["Settings"].buttons["Done"].tap()
        app.buttons["editProfile"].tap()
        XCTAssertTrue(app.textFields["profileNameField"].waitForExistence(timeout: 5))
        assertNormalEditHasNoConsentControls(app)
    }

    @MainActor
    func testLargeTextSignupKeepsNameSharingAndBothChoicesReachable() {
        let app = openSetup(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXL"])
        let name = app.textFields["profileNameField"]
        reveal(name, in: app)
        assertHorizontalBounds(name, in: app)
        name.tap(); name.typeText("Mira Bloom")
        dismissNameKeyboard(name, in: app)
        XCTAssertEqual(name.value as? String, "Mira Bloom")

        let sharing = app.switches["profileSharingToggle"]
        reveal(sharing, in: app)
        XCTAssertEqual(sharing.value as? String, "1")
        assertHorizontalBounds(sharing, in: app)

        let disclosure = app.staticTexts["signupProfileConsent"]
        reveal(disclosure, in: app)
        XCTAssertTrue(disclosure.label.contains("OpenAI"))
        assertHorizontalBounds(disclosure, in: app)
        let agree = app.buttons["completeProfileSetup"]
        reveal(agree, in: app)
        XCTAssertTrue(agree.isEnabled)
        XCTAssertEqual(agree.label, "Agree and continue")
        assertHorizontalBounds(agree, in: app)
        let decline = app.buttons["completeProfileWithoutChecks"]
        reveal(decline, in: app)
        XCTAssertTrue(decline.isEnabled)
        assertHorizontalBounds(decline, in: app)
        capture("Large text signup choices remain accessible", app)
        decline.tap()
        XCTAssertTrue(app.buttons["editProfile"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["profileName"].label, "Mira Bloom")
    }

    @MainActor
    func testPhotoPickerCanBeCancelledWithoutLosingChosenName() {
        let app = openSetup()
        let name = app.textFields["profileNameField"]
        name.tap(); name.typeText("Mira Sky")
        dismissNameKeyboard(name, in: app)
        let picker = app.buttons["chooseProfilePhoto"]
        reveal(picker, in: app); picker.tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        cancel.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Mira Sky")
        XCTAssertFalse(app.buttons["removeProfilePhoto"].exists)
    }

    @MainActor
    private func openSetup(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-worldniche-skip-intro", "-worldniche-social-fixture", "signup"] + extraArguments
        app.launch()
        openProfileDestination(app)
        XCTAssertTrue(app.navigationBars["Your profile"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["profileNameField"].exists)
        return app
    }

    @MainActor
    private func openProfileDestination(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["Profile"]
        let destination = tab.exists ? tab : app.buttons.matching(NSPredicate(format: "label == %@", "Profile")).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 8), "Profile must be available in the native navigation.")
        XCTAssertTrue(destination.isHittable)
        destination.tap()
    }

    @MainActor
    private func assertNormalEditHasNoConsentControls(_ app: XCUIApplication) {
        for _ in 0..<4 { app.swipeUp() }
        XCTAssertFalse(app.staticTexts["signupProfileConsent"].exists)
        XCTAssertFalse(app.buttons["completeProfileSetup"].exists)
        XCTAssertFalse(app.buttons["completeProfileWithoutChecks"].exists)
        XCTAssertFalse(app.switches["automaticProfileChecks"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "OpenAI")).firstMatch.exists)
    }

    @MainActor
    private func assertHorizontalBounds(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertGreaterThan(element.frame.width, 0)
        XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX)
    }

    @MainActor
    private func dismissNameKeyboard(_ name: XCUIElement, in app: XCUIApplication) {
        name.typeText("\n")
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { app.keyboards.count == 0 }
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<7 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}

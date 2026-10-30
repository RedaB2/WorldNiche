import XCTest
import UIKit

final class WorldNicheUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testDiscoverGuidanceAppearsAboveInteractiveGlobe() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-worldniche-skip-intro"]
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
        app.launchArguments = ["-worldniche-skip-intro"]
        app.launchArguments = ["-worldniche-skip-intro", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXL"]
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
    func testAppleIsTheOnlySignInOption() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-worldniche-skip-intro"]
        openSignedOutSignIn(app)
        assertAppleOnlySignIn(app)
        capture("Apple-only sign-in", app: app)
        app.navigationBars["Sign in"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAppleOnlySignInWithLargeTextRemainsAccessible() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-worldniche-skip-intro", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXL"]
        openSignedOutSignIn(app)
        assertAppleOnlySignIn(app)
        capture("Apple-only sign-in with large text", app: app)
        app.navigationBars["Sign in"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func assertAppleOnlySignIn(_ app: XCUIApplication) {
        let apple = app.buttons["signInWithApple"]
        XCTAssertTrue(apple.waitForExistence(timeout: 5))
        let form = app.collectionViews.firstMatch
        for _ in 0..<5 where !apple.isHittable { form.swipeUp() }
        XCTAssertTrue(apple.isHittable)
        XCTAssertFalse(app.textFields["signInEmailField"].exists)
        XCTAssertFalse(app.textFields["emailCodeField"].exists)
        XCTAssertFalse(app.buttons["requestEmailCode"].exists)
        XCTAssertFalse(app.buttons["recoverEmailAccount"].exists)
        // Inspect the footer too, where the recovery option used to appear.
        form.swipeUp()
        XCTAssertFalse(app.buttons["recoverEmailAccount"].exists)
        XCTAssertFalse(app.staticTexts["Already used email? Recover your account"].exists)
    }

    @MainActor
    private func openSignedOutSignIn(_ app: XCUIApplication) {
        app.launch()
        let profile = app.tabBars.buttons["Profile"].exists
            ? app.tabBars.buttons["Profile"]
            : app.buttons.matching(NSPredicate(format: "label == %@", "Profile")).firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 8))
        profile.tap()
        let signIn = app.buttons["profileAccountEntry"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 8), "Run this check with a signed-out simulator.")
        XCTAssertEqual(signIn.label, "Continue with Apple")
        XCTAssertEqual(app.buttons.matching(identifier: "profileAccountEntry").count, 1)
        XCTAssertFalse(app.buttons["createProfile"].exists)
        XCTAssertFalse(app.buttons["signInForFriends"].exists)
        XCTAssertFalse(app.staticTexts["Curiosity, together."].exists)
        capture("One account entry for new and returning explorers", app: app)
        for _ in 0..<4 where !signIn.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(signIn.isHittable)
        signIn.tap()
        XCTAssertTrue(app.navigationBars["Sign in"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testProfileSaveShowsChosenNameWithoutReviewPrompts() throws {
        let app = openProfileFixture("approval")
        editFixtureName(app, name: "Mira Rose", allowChecks: true)
        XCTAssertTrue(app.staticTexts["profileName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["profileName"].label, "Mira Rose")
        XCTAssertFalse(app.staticTexts["Checking before sharing with friends…"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "OpenAI")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["profileSaveConfirmation"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["profileSaveConfirmation"].label, "Profile saved.")
        XCTAssertEqual(app.staticTexts["profileName"].label, "Mira Rose")
        XCTAssertFalse(app.staticTexts["Checking before sharing with friends…"].exists)
        capture("Saved profile without review prompts", app: app)
    }

    @MainActor
    func testProfileCheckFailureKeepsSavedNameWithoutExtraPrompts() throws {
        let app = openProfileFixture("retry")
        editFixtureName(app, name: "Mira Rose", allowChecks: true)
        XCTAssertEqual(app.staticTexts["profileName"].label, "Mira Rose")
        XCTAssertFalse(app.buttons["retryProfileCheck"].exists)
        XCTAssertFalse(app.staticTexts["Checking before sharing with friends…"].exists)
        let confirmation = app.staticTexts["profileSaveConfirmation"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertEqual(confirmation.label, "Profile saved.")
        app.buttons["profileSettings"].tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["profileName"].label, "Mira Rose")
        XCTAssertEqual(confirmation.label, "Profile saved.")
        XCTAssertFalse(app.buttons["retryProfileCheck"].exists)
        capture("Saved profile survives a failed check without extra prompts", app: app)
    }

    @MainActor
    func testRememberedPrivacyChoiceDoesNotPromptOnEdits() throws {
        let app = openProfileFixture("manual")
        editFixtureName(app, name: "Mira Rose", allowChecks: false)
        XCTAssertEqual(app.staticTexts["profileName"].label, "Mira Rose")
        XCTAssertFalse(app.buttons["retryProfileCheck"].exists)
        XCTAssertFalse(app.buttons["Use quick safety checks"].exists)
        XCTAssertFalse(app.staticTexts["Name saved for review"].exists)
        app.buttons["profileSettings"].tap()
        let choice = app.switches["automaticProfileChecks"]
        for _ in 0..<4 where !choice.isHittable { app.swipeUp() }
        XCTAssertTrue(choice.exists)
        XCTAssertEqual(choice.value as? String, "0")
        capture("Remembered profile privacy choice", app: app)
    }

    @MainActor
    func testOpenFriendProfileRefreshesApprovedNameAutomatically() throws {
        let app = openProfileFixture("friend")
        let friend = app.buttons["friend-33333333-3333-4333-8333-333333333333"]
        for _ in 0..<4 where !friend.isHittable { app.swipeUp() }
        XCTAssertTrue(friend.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Jun"].exists)
        friend.tap()
        XCTAssertTrue(app.navigationBars["Friend"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Jun Updated"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["Jun"].exists)
        capture("Friend approval appears without manual refresh", app: app)
    }

    @MainActor
    func testFriendPhotoRecoversAfterTemporaryOutageWithoutNavigation() throws {
        let app = openProfileFixture("photo")
        let friend = app.buttons["friend-33333333-3333-4333-8333-333333333333"]
        for _ in 0..<5 where !friend.isHittable || friend.frame.maxY > app.frame.maxY - 100 { app.swipeUp() }
        XCTAssertTrue(friend.isHittable)
        // The fixture rejects both initial image requests, then serves the
        // same immutable photo path. A successful retry paints a red avatar.
        let recovered = NSPredicate { _, _ in
            MainActor.assumeIsolated { self.hasRedAvatar(row: friend) }
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: recovered, object: app)], timeout: 20)
        let rowImage = friend.screenshot().image
        let rowCapture = XCTAttachment(image: rowImage)
        rowCapture.name = "Recovered friend photo row"
        rowCapture.lifetime = .keepAlways
        add(rowCapture)
        capture("Friend photo recovery screen", app: app)
        XCTAssertEqual(result, .completed, "Row frame: \(friend.frame), screenshot size: \(rowImage.size), orientation: \(rowImage.imageOrientation.rawValue)")
        XCTAssertTrue(app.navigationBars["Profile"].exists)
        capture("Friend photo recovers on the same visible screen", app: app)
    }

    @MainActor
    private func hasRedAvatar(row: XCUIElement) -> Bool {
        let screenshot = row.screenshot().image
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: screenshot.size, format: format).image { _ in
            screenshot.draw(in: CGRect(origin: .zero, size: screenshot.size))
        }
        guard let cgImage = image.cgImage, row.frame.width > 0, row.frame.height > 0 else { return false }
        let scaleX = CGFloat(cgImage.width) / row.frame.width
        let scaleY = CGFloat(cgImage.height) / row.frame.height
        // Dual-display XCTest snapshots can encode rotated pixels with an up
        // orientation. Check both row ends, also allowing right-to-left layout.
        for centerX in [CGFloat(22), row.frame.width - 22] {
            let rect = CGRect(x: centerX * scaleX, y: row.frame.height * 0.5 * scaleY, width: 1, height: 1)
            guard let pixel = cgImage.cropping(to: rect) else { continue }
            var rgba = [UInt8](repeating: 0, count: 4)
            let rendered = rgba.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                              bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                return true
            }
            if rendered && rgba[0] > 220 && rgba[1] < 40 && rgba[2] < 40 { return true }
        }
        return false
    }

    @MainActor
    private func openProfileFixture(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-worldniche-skip-intro"]
        app.launchArguments = ["-worldniche-skip-intro", "-worldniche-social-fixture", mode]
        app.launch()
        let tab = app.tabBars.buttons["Profile"]
        let destination = tab.exists ? tab : app.buttons.matching(NSPredicate(format: "label == %@", "Profile")).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 8), "Profile must be available in the native navigation.")
        XCTAssertTrue(destination.isHittable)
        destination.tap()
        XCTAssertTrue(app.buttons["editProfile"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["profileName"].label, "Mira")
        return app
    }

    @MainActor
    private func editFixtureName(_ app: XCUIApplication, name: String, allowChecks: Bool) {
        app.buttons["editProfile"].tap()
        let field = app.textFields["profileNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count) + name)
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Allow quick checks and save"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "OpenAI")).firstMatch.exists)
    }

    @MainActor
    func testInvitationSheetFromWarmAndColdURLLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-worldniche-skip-intro"]
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
        app.launchArguments = ["-worldniche-skip-intro"]
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
        app.launchArguments = ["-worldniche-skip-intro"]
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
        app.launchArguments = ["-worldniche-skip-intro"]
        app.launchArguments = ["-worldniche-skip-intro", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXL"]
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
        app.launchArguments = ["-worldniche-skip-intro"]
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
        let responseAppeared = app.staticTexts["assistantMessage"].firstMatch.waitForExistence(timeout: 45)
        capture("Companion response state", app: app)
        XCTAssertTrue(responseAppeared, app.debugDescription)
        let message = app.staticTexts["assistantMessage"].firstMatch.label
        XCTAssertGreaterThan(message.count, 10)
        capture("Companion response", app: app)
    }

    @MainActor
    func testLiveDiscoveryCanRotate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-worldniche-skip-intro"]
        app.launch()
        // Start with an unread catalog instead of inheriting prior live runs.
        // Source exhaustion and history preservation have deterministic coverage.
        let profile = app.tabBars.buttons["Profile"].exists
            ? app.tabBars.buttons["Profile"] : app.buttons["Profile"].firstMatch
        profile.tap()
        XCTAssertTrue(app.buttons["profileAccountEntry"].waitForExistence(timeout: 8), "Use a signed-out test simulator.")
        app.buttons["profileSettings"].tap()
        let clear = app.buttons["clearLocalData"]
        for _ in 0..<8 where !clear.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(clear.isHittable)
        clear.tap()
        let confirm = app.buttons["Clear device data"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        let discover = app.tabBars.buttons["Discover"].exists
            ? app.tabBars.buttons["Discover"] : app.buttons["Discover"].firstMatch
        discover.tap()
        app.buttons["landingCountry"].tap()
        let title = app.staticTexts["liveCultureTitle"]
        guard title.waitForExistence(timeout: 40) else {
            throw XCTSkip("The public cultural service did not respond; fallback remains dated.")
        }
        let original = title.label
        capture("Live discovery", app: app)
        let another = app.buttons["anotherDiscovery"]
        for _ in 0..<5 where !another.isHittable { app.swipeUp() }
        capture("Before requesting another discovery", app: app)
        another.tap()
        let changed = NSPredicate(format: "label != %@", original)
        let change = XCTNSPredicateExpectation(predicate: changed, object: title)
        let result = XCTWaiter.wait(for: [change], timeout: 40)
        capture("Discovery rotation result", app: app)
        XCTAssertEqual(result, .completed, app.debugDescription)
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

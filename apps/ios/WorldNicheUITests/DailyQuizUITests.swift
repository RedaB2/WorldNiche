import XCTest

final class DailyQuizUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testPreviouslyDisabledQuizReminderStaysOff() {
        let app = XCUIApplication()
        launchReminderFixture(app, choice: "off")
        XCTAssertEqual(openReminderSettings(app).value as? String, "0")
    }

    @MainActor
    func testFirstLaunchQuizReminderPermission() throws {
        // XCTest cannot reset notification authorization. The release check selects a fresh simulator.
        let response = ProcessInfo.processInfo.environment["WORLDNICHE_REMINDER_PERMISSION"]
        try XCTSkipUnless(response == "allow" || response == "deny", "Select allow or deny on a fresh simulator.")
        let app = XCUIApplication()
        let offer = app.alerts["Daily quiz reminder?"]
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permission = springboard.alerts.firstMatch

        launchReminderFixture(app, choice: "fresh")
        XCTAssertTrue(offer.waitForExistence(timeout: 12))
        offer.buttons["No thanks"].tap()
        XCTAssertEqual(openReminderSettings(app).value as? String, "0")
        XCTAssertFalse(permission.exists)
        app.terminate()
        launchReminderFixture(app, choice: "resume")
        XCTAssertEqual(openReminderSettings(app).value as? String, "0")

        app.terminate()
        launchReminderFixture(app, choice: "fresh")
        XCTAssertTrue(offer.waitForExistence(timeout: 12))
        offer.buttons["Remind me"].tap()
        XCTAssertTrue(permission.waitForExistence(timeout: 12), "Expected iOS to request notification permission.")
        XCTAssertTrue(permission.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'notifications'")).firstMatch.exists)
        let allow = response == "allow"
        let answer = allow ? permission.buttons["Allow"] : permission.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Don'")).firstMatch
        XCTAssertTrue(answer.isHittable)
        answer.tap()
        let reminder = openReminderSettings(app)
        XCTAssertEqual(reminder.value as? String, allow ? "1" : "0")
        XCTAssertEqual(app.buttons["Open notification settings"].exists, !allow)

        app.terminate()
        launchReminderFixture(app, choice: "resume")
        let saved = openReminderSettings(app)
        XCTAssertEqual(saved.value as? String, allow ? "1" : "0")
        if allow {
            let control = saved.switches.firstMatch
            XCTAssertTrue(control.isHittable)
            control.tap()
            let turnedOff = expectation(for: NSPredicate(format: "value == %@", "0"), evaluatedWith: saved)
            wait(for: [turnedOff], timeout: 5)
            app.terminate()
            launchReminderFixture(app, choice: "resume")
            XCTAssertEqual(openReminderSettings(app).value as? String, "0")
        }
    }

    @MainActor
    private func launchReminderFixture(_ app: XCUIApplication, choice: String) {
        app.launchArguments = ["-worldniche-skip-intro", "-worldniche-social-fixture", "quiz",
                               "-worldniche-reading-fixture", "unavailable", "-worldniche-reminder-fixture", choice]
        app.launch()
    }

    @MainActor
    private func openReminderSettings(_ app: XCUIApplication) -> XCUIElement {
        let profile = app.buttons.matching(NSPredicate(format: "label == %@", "Profile")).firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts["Daily quiz reminder?"].exists)
        profile.tap()
        let settings = app.buttons["profileSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let reminder = app.switches["Daily quiz reminder"].firstMatch
        XCTAssertTrue(reminder.waitForExistence(timeout: 8))
        return reminder
    }

    // Allow review recordings to show each screen after its transition finishes.
    @MainActor private func holdForRecording() async throws {
        if ProcessInfo.processInfo.environment["WORLDNICHE_RECORD_QUIZ"] == "1" {
            try await Task.sleep(for: .seconds(2))
        }
    }

    @MainActor
    func testDailyQuizRevealAndFriendsStreak() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["-worldniche-skip-intro", "-worldniche-social-fixture", "quiz",
                               "-worldniche-reading-fixture", "unavailable"]
        app.launch()
        let play = app.buttons["dailyQuiz"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        if ProcessInfo.processInfo.environment["WORLDNICHE_UI_TEST_DISPLAY_ID"] == "3" {
            XCTAssertGreaterThan(app.frame.width, 600, "Run the Duo proof on its unfolded inner display.")
        }
        try await holdForRecording()
        play.tap()
        XCTAssertEqual(app.staticTexts["quizQuestion"].label, "Which country has Vienna as its capital?")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'quizChoice-'")).count, 4)
        try await holdForRecording()
        app.buttons["quizChoice-AT"].tap()
        let title = app.staticTexts["countryTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 12))
        XCTAssertEqual(title.label, "Austria")
        try await holdForRecording()
        app.buttons["Close"].tap()
        XCTAssertFalse(play.exists)
        try await holdForRecording()
        let streak = app.buttons["quizStreak"]
        XCTAssertEqual(streak.label, "2-day streak")
        streak.tap()
        XCTAssertTrue(app.staticTexts["Friends leaderboard"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Jun"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 / 7"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Wednesday, completed"].firstMatch.exists)
        try await holdForRecording()
        app.buttons["Done"].tap()
        XCTAssertTrue(streak.waitForExistence(timeout: 6))
        XCTAssertFalse(play.exists)
    }

    @MainActor
    func testWrongGuessStillEarnsStreak() {
        let app = XCUIApplication()
        app.launchArguments = ["-worldniche-skip-intro", "-worldniche-social-fixture", "quiz",
                               "-worldniche-reading-fixture", "unavailable"]
        app.launch()
        app.buttons["dailyQuiz"].tap()
        app.buttons["quizChoice-HU"].tap()
        XCTAssertTrue(app.staticTexts["countryTitle"].waitForExistence(timeout: 12))
        XCTAssertEqual(app.staticTexts["countryTitle"].label, "Austria")
        app.buttons["Close"].tap()
        XCTAssertEqual(app.buttons["quizStreak"].label, "2-day streak")
        XCTAssertFalse(app.buttons["dailyQuiz"].exists)
    }
}

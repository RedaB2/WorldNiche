import XCTest

final class DailyQuizUITests: XCTestCase {
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

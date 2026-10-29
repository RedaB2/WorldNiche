import XCTest

final class JournalUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testNoteSaveRelaunchEditCancelAndErase() {
        let app = launch(mode: "reset")
        openJournal(app)
        let note = app.buttons["journalNote_MA"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        let editor = app.textViews["journalNoteEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Ask about the music in Marrakech.")
        app.buttons["saveJournalNote"].tap()
        XCTAssertTrue(app.staticTexts["Ask about the music in Marrakech."].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-worldniche-skip-intro", "-worldniche-journal-fixture", "resume"]
        app.launch()
        openJournal(app)
        XCTAssertTrue(app.staticTexts["Ask about the music in Marrakech."].waitForExistence(timeout: 5))
        app.buttons["journalNote_MA"].tap()
        XCTAssertEqual(editor.value as? String, "Ask about the music in Marrakech.")
        editor.tap()
        editor.typeText(" This edit should be cancelled.")
        app.buttons["cancelJournalNote"].tap()
        XCTAssertTrue(app.staticTexts["Ask about the music in Marrakech."].exists)
        app.buttons["journalNote_MA"].tap()
        app.buttons["clearJournalNote"].tap()
        XCTAssertEqual(editor.value as? String, "")
        app.buttons["saveJournalNote"].tap()
        XCTAssertTrue(app.staticTexts["Add a note"].waitForExistence(timeout: 5))
        capture("Journal note removed", app)
    }

    @MainActor
    func testNoteEditorAndJournalWorkWithLargeText() {
        let app = launch(mode: "reset", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXL"])
        openJournal(app)
        let button = app.buttons["journalNote_MA"]
        for _ in 0..<8 where !button.isHittable { app.scrollViews["journalScroll"].swipeUp() }
        if !button.isHittable { print(app.debugDescription); capture("Journal scroll diagnostic", app) }
        XCTAssertTrue(button.isHittable)
        button.tap()
        let editor = app.textViews["journalNoteEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Try the local radio.")
        XCTAssertTrue(app.buttons["saveJournalNote"].isHittable)
        XCTAssertTrue(app.buttons["cancelJournalNote"].isHittable)
        capture("Private journal note at large text", app)
        app.buttons["saveJournalNote"].tap()
        XCTAssertTrue(app.staticTexts["Try the local radio."].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launch(mode: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-worldniche-skip-intro", "-worldniche-journal-fixture", mode] + extra
        app.launch()
        return app
    }

    @MainActor
    private func openJournal(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["Journal"]
        let button = tab.exists ? tab : app.buttons["Journal"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        button.tap()
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}

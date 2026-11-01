import XCTest
import UIKit

final class CountryLocationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testAtlasGlobeRotatesWithAFixedPinAndRecenters() throws {
        let app = launch()
        let globe = open("Japan", in: app)
        let initial = try renderedLocation(globe)
        capture("Japan initial location", app)
        XCTAssertEqual(initial.pin.x, globe.frame.width / 2, accuracy: 4)
        XCTAssertEqual(initial.pin.y, globe.frame.height / 2, accuracy: 22)
        let originalFrame = globe.frame
        let start = CGPoint(x: globe.frame.midX, y: globe.frame.midY)
        let points = (0...60).map { step in
            NSValue(cgPoint: CGPoint(x: start.x + 55 * CGFloat(step) / 60, y: start.y))
        }
        XCTAssertNil(GlobeTestGestures.trace(points, duration: 1, hold: 0.5))
        let turned = try renderedLocation(globe)
        XCTAssertGreaterThan(turned.pin.x, initial.pin.x + 25, "The pin must travel with its country")
        XCTAssertEqual(globe.frame, originalFrame, "Turning the globe must not scroll the page")
        XCTAssertEqual(turned.diameter, initial.diameter, accuracy: 3)
        capture("Japan after turning the globe", app)

        XCTAssertNil(GlobeTestGestures.moveFirst(CGPoint(x: start.x - 25, y: start.y),
            second: CGPoint(x: start.x + 25, y: start.y),
            toFirst: CGPoint(x: start.x - 70, y: start.y + 20),
            toSecond: CGPoint(x: start.x + 110, y: start.y + 20), duration: 1))
        let pinched = try renderedLocation(globe)
        XCTAssertEqual(pinched.diameter, initial.diameter, accuracy: 3, "Country previews have a fixed scale")
        XCTAssertEqual(pinched.pin.x, turned.pin.x, accuracy: 3, "Two fingers must not pan the preview")
        XCTAssertEqual(pinched.pin.y, turned.pin.y, accuracy: 3)
        XCTAssertEqual(globe.value as? String, "100% zoom")
        globe.tap()
        XCTAssertEqual(app.staticTexts["countryTitle"].label, "Japan")
        app.buttons["recenterCountryGlobe"].tap()
        // Wait for the existing short recenter animation before inspecting rendered pixels.
        Thread.sleep(forTimeInterval: 0.7)
        let reset = try renderedLocation(globe)
        XCTAssertEqual(reset.pin.x, initial.pin.x, accuracy: 3)
        XCTAssertEqual(reset.pin.y, initial.pin.y, accuracy: 3)
        capture("Japan centered on its location", app)
    }

    @MainActor
    func testHideShowAndCountryChangesRestoreTheCorrectLocation() throws {
        let app = launch()
        for name in ["Morocco", "New Zealand", "Singapore"] {
            let globe = open(name, in: app)
            XCTAssertEqual(globe.label, "\(name) on the globe")
            let rendered = try renderedLocation(globe)
            XCTAssertEqual(rendered.pin.x, globe.frame.width / 2, accuracy: 4)
            XCTAssertEqual(rendered.pin.y, globe.frame.height / 2, accuracy: 22)
            globe.swipeLeft()
            app.buttons["toggleCountryGlobe"].tap()
            XCTAssertFalse(globe.exists)
            XCTAssertFalse(app.buttons["recenterCountryGlobe"].exists)
            XCTAssertEqual(app.buttons["toggleCountryGlobe"].value as? String, "Collapsed")
            capture("\(name) with the globe hidden", app)
            app.buttons["toggleCountryGlobe"].tap()
            XCTAssertTrue(globe.waitForExistence(timeout: 3))
            let reopened = try renderedLocation(globe)
            XCTAssertEqual(reopened.pin.x, globe.frame.width / 2, accuracy: 4)
            XCTAssertEqual(reopened.pin.y, globe.frame.height / 2, accuracy: 22)
            capture("\(name) with its location restored", app)
            app.buttons["Close"].firstMatch.tap()
        }
    }

    @MainActor
    func testLocationControlsAndPageScrollingWithLargeText() {
        let app = launch(largeText: true)
        let globe = open("Japan", in: app)
        let toggle = app.buttons["toggleCountryGlobe"]
        XCTAssertTrue(toggle.isHittable)
        toggle.tap()
        XCTAssertFalse(globe.exists)
        toggle.tap()
        XCTAssertTrue(globe.waitForExistence(timeout: 3))
        let originalY = toggle.frame.minY
        let scroll = app.scrollViews.containing(.staticText, identifier: "countryTitle").firstMatch
        // The outside margin remains available for vertical reading gestures.
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.75))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -160)))
        XCTAssertLessThan(toggle.frame.minY, originalY - 30)
        capture("Large text keeps the country page scrollable", app)
    }

    @MainActor
    private func launch(largeText: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-worldniche-skip-intro", "-worldniche-journal-fixture", "reset"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXL"]
        }
        app.launch()
        let atlas = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Atlas")).firstMatch
        XCTAssertTrue(atlas.waitForExistence(timeout: 10))
        atlas.tap()
        return app
    }

    @MainActor
    private func open(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        if let value = search.value as? String, !value.isEmpty, value != search.placeholderValue {
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        search.typeText(name)
        let row = app.buttons.containing(.staticText, identifier: name).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["countryTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["countryTitle"].label, name)
        let globe = app.descendants(matching: .any)["countryLocationGlobe"].firstMatch
        XCTAssertTrue(globe.waitForExistence(timeout: 5))
        return globe
    }

    @MainActor
    private func renderedLocation(_ globe: XCUIElement) throws -> (pin: CGPoint, diameter: CGFloat) {
        let screenshot = globe.screenshot().image
        // The unfolded display returns rotated screenshot pixels. Honor UIImage's orientation.
        let image = try XCTUnwrap(UIGraphicsImageRenderer(size: screenshot.size).image { _ in
            screenshot.draw(at: .zero)
        }.cgImage)
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var pin: [CGPoint] = []
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if pixels[i] < 60 && (60...105).contains(pixels[i + 1]) && (40...85).contains(pixels[i + 2]) {
                    pin.append(CGPoint(x: x, y: y))
                }
            }
        }
        XCTAssertGreaterThan(pin.count, 12, "A visible pin must be rendered on the globe")
        let count = CGFloat(max(1, pin.count))
        let center = CGPoint(x: pin.reduce(0) { $0 + $1.x } / count * globe.frame.width / CGFloat(width),
            y: pin.reduce(0) { $0 + $1.y } / count * globe.frame.height / CGFloat(height))
        let background = Array(pixels[0..<3])
        let row = (0..<width).filter { x in
            let i = ((height / 2) * width + x) * 4
            return (0..<3).reduce(0) { $0 + abs(Int(pixels[i + $1]) - Int(background[$1])) } > 8
        }
        let diameter = CGFloat((row.last ?? 0) - (row.first ?? 0)) * globe.frame.width / CGFloat(width)
        return (center, diameter)
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        // Capture the content's display; the Duo's default application screenshot uses its outer screen.
        let content = app.scrollViews.containing(.staticText, identifier: "countryTitle").firstMatch
        let attachment = XCTAttachment(screenshot: content.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

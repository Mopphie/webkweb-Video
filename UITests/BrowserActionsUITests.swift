import XCTest

/// Uses the generated local decoder signal, never a claimed provider fixture.
@MainActor
final class BrowserActionsUITests: XCTestCase {
    private func launchFixture() throws -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        let url = try XCTUnwrap(Bundle(for: BrowserActionsUITests.self).url(forResource: "sample", withExtension: "mp4"))
        app.launchArguments = ["--ui-test-browser"]
        app.launchEnvironment["WEBKWEB_UI_TEST_MEDIA"] = try Data(contentsOf: url).base64EncodedString()
        app.launch()
        XCTAssertTrue(app.buttons["browser.actions"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Video läuft"].waitForExistence(timeout: 15))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            if app.collectionViews.firstMatch.exists { app.collectionViews.firstMatch.swipeUp() }
            else if app.tables.firstMatch.exists { app.tables.firstMatch.swipeUp() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Action remains reachable in the modal panel")
    }

    func testActionsStayReachableDuringPlaybackAndRestoreNormalWebsite() throws {
        let app = try launchFixture()
        app.buttons["browser.actions"].tap()
        XCTAssertTrue(app.navigationBars["Browser"].waitForExistence(timeout: 5))
        let filter = app.switches["browser.filter"]
        reveal(filter, in: app); filter.tap()
        XCTAssertTrue(app.buttons["browser.actions.close"].isHittable)
        app.buttons["browser.actions.close"].tap()
        app.buttons["browser.actions"].tap()
        let normal = app.buttons["Normale YouTube-Ansicht"]
        reveal(normal, in: app); normal.tap()
        XCTAssertTrue(app.textFields["Suchen oder Adresse"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["browser.watch.exit"].exists)
        XCTAssertTrue(app.staticTexts["Lokale UI-Testfixture"].exists)
    }

    func testFirstRealHostTouchResumesStoppedWebsiteVideo() throws {
        let app = try launchFixture()
        app.buttons["browser.actions"].tap()
        let pause = app.buttons["Alles pausieren"]
        reveal(pause, in: app); pause.tap()
        XCTAssertTrue(app.staticTexts["Video pausiert"].waitForExistence(timeout: 5))
        // The button deliberately says "Start", not semantic Play/Abspielen.
        // Only the real UIKit touch inside the media rectangle arms the bridge.
        app.buttons["Videostart"].tap()
        XCTAssertTrue(app.staticTexts["Video läuft"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["browser.watch.exit"].isHittable)
        XCTAssertTrue(app.buttons["browser.watch.home"].isHittable)
    }
}

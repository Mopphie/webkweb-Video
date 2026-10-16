import XCTest

/// Uses the generated local decoder signal, never a claimed provider fixture.
@MainActor
final class BrowserActionsUITests: XCTestCase {
    private func milestone(_ message: String) {
        print("WEBKWEB_UI_PROGRESS \(Date().timeIntervalSince1970): \(message)")
        XCTContext.runActivity(named: message) { _ in }
    }

    private func capturePlayerDiagnostic(_ app: XCUIApplication) {
        let report = app.buttons["browser.actions"].value as? String ?? "Player diagnostic unavailable"
        print("WEBKWEB_UI_MEDIA_DIAGNOSTIC \(report)")
        let attachment = XCTAttachment(string: report)
        attachment.name = "Player state at failed playback assertion"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launchFixture(audible: Bool = false) throws -> XCUIApplication {
        continueAfterFailure = false
        // A cold CI simulator completed the menu assertions but spent 132s
        // including launch/quiescence. Keep the functional wait limits intact.
        executionTimeAllowance = 180
        let app = XCUIApplication()
        let url = try XCTUnwrap(Bundle(for: BrowserActionsUITests.self).url(forResource: "sample", withExtension: "mp4"))
        app.launchArguments = ["--ui-test-browser"]
        app.launchEnvironment["WEBKWEB_UI_TEST_MEDIA"] = try Data(contentsOf: url).base64EncodedString()
        app.launchEnvironment["WEBKWEB_UI_TEST_AUDIBLE"] = audible ? "1" : "0"
        milestone("Launch local real-video fixture")
        app.launch()
        milestone("App launched; wait for browser actions and decoded playback")
        XCTAssertTrue(app.buttons["browser.actions"].waitForExistence(timeout: 20))
        if audible {
            milestone("Start unmuted media with an actual user Play gesture")
            app.buttons["Videostart"].tap()
        }
        let running = app.staticTexts["Video läuft"].waitForExistence(timeout: 15)
        if !running { capturePlayerDiagnostic(app) }
        XCTAssertTrue(running)
        milestone("Local decoder is playing")
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            milestone("Scroll actions panel to the requested control")
            if app.collectionViews.firstMatch.exists { app.collectionViews.firstMatch.swipeUp() }
            else if app.tables.firstMatch.exists { app.tables.firstMatch.swipeUp() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Action remains reachable in the modal panel")
    }

    func testActionsStayReachableDuringPlaybackAndRestoreNormalWebsite() throws {
        let app = try launchFixture()
        milestone("Open stable actions panel during playback")
        app.buttons["browser.actions"].tap()
        XCTAssertTrue(app.navigationBars["Browser"].waitForExistence(timeout: 5))
        let filter = app.switches["browser.filter"]
        reveal(filter, in: app)
        milestone("Toggle filter in modal panel")
        filter.tap()
        XCTAssertTrue(app.buttons["browser.actions.close"].isHittable)
        app.buttons["browser.actions.close"].tap()
        milestone("Reopen actions and restore the same website document")
        app.buttons["browser.actions"].tap()
        let normal = app.buttons["Normale YouTube-Ansicht"]
        reveal(normal, in: app); normal.tap()
        XCTAssertTrue(app.textFields["Suchen oder Adresse"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["browser.watch.exit"].exists)
        XCTAssertTrue(app.staticTexts["Lokale UI-Testfixture"].exists)
        milestone("Normal website and native browser controls are reachable")
    }

    func testFirstRealHostTouchResumesStoppedWebsiteVideo() throws {
        let app = try launchFixture()
        milestone("Open actions and pause the real video")
        app.buttons["browser.actions"].tap()
        let pause = app.buttons["Alles pausieren"]
        reveal(pause, in: app); pause.tap()
        XCTAssertTrue(app.staticTexts["Video pausiert"].waitForExistence(timeout: 5))
        milestone("Pause confirmed; perform first real UIKit touch in video rectangle")
        // The button deliberately says "Start", not semantic Play/Abspielen.
        // Only the real UIKit touch inside the media rectangle arms the bridge.
        app.buttons["Videostart"].tap()
        XCTAssertTrue(app.staticTexts["Video läuft"].waitForExistence(timeout: 5))
        milestone("First real host touch resumed decoder playback")
        XCTAssertTrue(app.buttons["browser.watch.exit"].isHittable)
        XCTAssertTrue(app.buttons["browser.watch.home"].isHittable)
    }

    func testAudibleVideoKeepsAdvancingWithRealWebsiteAndNativePlayControls() throws {
        let app = try launchFixture(audible: true)
        XCTAssertTrue(app.staticTexts["Ton aktiv"].exists)
        milestone("Unmuted fixture keeps decoding beyond startup")
        for _ in 0..<3 {
            Thread.sleep(forTimeInterval: 1)
            XCTAssertTrue(app.staticTexts["Video läuft"].exists)
        }
        app.buttons["browser.actions"].tap()
        let pause = app.buttons["Alles pausieren"]
        reveal(pause, in: app); pause.tap()
        XCTAssertTrue(app.staticTexts["Video pausiert"].waitForExistence(timeout: 5))
        app.buttons["Videostart"].tap()
        let resumed = app.staticTexts["Video läuft"].waitForExistence(timeout: 8)
        if !resumed { capturePlayerDiagnostic(app) }
        XCTAssertTrue(resumed)
        for _ in 0..<3 {
            Thread.sleep(forTimeInterval: 1)
            XCTAssertTrue(app.staticTexts["Video läuft"].exists)
        }
        milestone("Unmuted player remains advancing after first real website Play")
    }
}

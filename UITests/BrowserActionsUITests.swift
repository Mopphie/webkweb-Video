import XCTest

/// Uses the generated local decoder signal, never a claimed provider fixture.
@MainActor
final class BrowserActionsUITests: XCTestCase {
    override func tearDownWithError() throws {
        // Retire the fixture and its WebContent processes before the next
        // independent launch, rather than during that test's launch deadline.
        XCUIApplication().terminate()
        try super.tearDownWithError()
    }
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

    private func mediaIdentity(_ app: XCUIApplication) throws -> String {
        let text = try XCTUnwrap(app.buttons["browser.actions"].value as? String)
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let native = try XCTUnwrap(report["native"] as? [String: Any])
        let id = try XCTUnwrap(native["media_id"] as? String)
        XCTAssertFalse(id.isEmpty)
        return id
    }

    private func requireSustainedPlayback(_ app: XCUIApplication) throws {
        func snapshot() throws -> (time: Double, duration: Double, valid: Bool) {
            let text = try XCTUnwrap(app.buttons["browser.actions"].value as? String)
            let report = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            let native = try XCTUnwrap(report["native"] as? [String: Any])
            let web = try XCTUnwrap(report["web"] as? [String: Any])
            let time = try XCTUnwrap(native["time"] as? NSNumber).doubleValue
            let duration = try XCTUnwrap(native["duration"] as? NSNumber).doubleValue
            return (time, duration, native["playing"] as? Bool == true && native["waiting"] as? Bool == false && native["stop_latched"] as? Bool == false && web["paused"] as? Bool == false)
        }
        var previous = try snapshot().time
        for _ in 0..<3 {
            // Leave room for the one-second bridge heartbeat and AX delivery.
            // WebKit's simulator may report zero playback-quality frames even
            // while media time advances. Require actual clock progress instead.
            Thread.sleep(forTimeInterval: 2)
            let next = try snapshot()
            var progress = next.time - previous
            if progress < 0 && next.duration > 0 { progress += next.duration }
            if !next.valid || progress <= 0.1 { capturePlayerDiagnostic(app) }
            XCTAssertTrue(next.valid)
            XCTAssertGreaterThan(next.duration, 59)
            XCTAssertGreaterThan(progress, 0.1)
            previous = next.time
        }
    }

    private func launchFixture(audible: Bool = false, scrolled: Bool = false) throws -> XCUIApplication {
        continueAfterFailure = false
        // A cold CI simulator completed the menu assertions but spent 132s
        // including launch/quiescence. Keep the functional wait limits intact.
        executionTimeAllowance = 300
        let app = XCUIApplication()
        let url = try XCTUnwrap(Bundle(for: BrowserActionsUITests.self).url(forResource: audible ? "audible" : "sample", withExtension: "mp4"))
        app.launchArguments = ["--ui-test-browser"]
        app.launchEnvironment["WEBKWEB_UI_TEST_MEDIA"] = try Data(contentsOf: url).base64EncodedString()
        app.launchEnvironment["WEBKWEB_UI_TEST_AUDIBLE"] = audible ? "1" : "0"
        app.launchEnvironment["WEBKWEB_UI_TEST_SCROLLED"] = scrolled ? "1" : "0"
        milestone("Launch local real-video fixture")
        app.launch()
        milestone("App launched; wait for browser actions and decoded playback")
        XCTAssertTrue(app.buttons["browser.actions"].waitForExistence(timeout: 20))
        // A native toolbar does not prove the cold WebContent document is ready.
        // Keep document startup separate from the functional playback deadline.
        let start = app.buttons["Videostart"]
        let documentReady = start.waitForExistence(timeout: 45)
        if !documentReady { capturePlayerDiagnostic(app) }
        XCTAssertTrue(documentReady)
        if audible {
            milestone("Start unmuted media with an actual user Play gesture")
            start.tap()
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
        let address = app.buttons["Adresse oder Suche"]
        XCTAssertTrue(address.isHittable)
        milestone("Navigation remains reachable in modal panel")
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

    func testDownSwipeOnScrolledVideoRestoresBrowserAndKeepsPlayback() throws {
        let app = try launchFixture(audible: true, scrolled: true)
        let identity = try mediaIdentity(app)
        let web = app.webViews.firstMatch
        let start = app.buttons["Videostart"]
        // Start below the overlay and above the native video seek controls.
        // The fixture has a 260px header and scrollY=160: the video is neither
        // at y=0 nor at the document's upper edge (both old assumptions fail).
        let point = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: start.frame.minX + 200, dy: start.frame.minY + 80))
        milestone("Pull down from actual video on scrolled website")
        point.press(forDuration: 0.05, thenDragTo: point.withOffset(CGVector(dx: 0, dy: 115)))
        XCTAssertTrue(app.textFields["Suchen oder Adresse"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["browser.watch.exit"].exists)
        XCTAssertTrue(web.exists)
        XCTAssertTrue(app.staticTexts["Lokale UI-Testfixture"].exists)
        XCTAssertEqual(try mediaIdentity(app), identity)
        try requireSustainedPlayback(app)
        milestone("Swipe restored normal browser without a page navigation or player restart")
    }

    func testVisibleReturnButtonKeepsSameWebsiteAndPlayback() throws {
        let app = try launchFixture(audible: true)
        let identity = try mediaIdentity(app)
        app.buttons["browser.watch.exit"].tap()
        XCTAssertTrue(app.textFields["Suchen oder Adresse"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["browser.watch.exit"].exists)
        XCTAssertTrue(app.staticTexts["Lokale UI-Testfixture"].exists)
        XCTAssertEqual(try mediaIdentity(app), identity)
        try requireSustainedPlayback(app)
    }

    func testCommentsKeepScrollingAndNativeHeaderCanRestoreBrowser() throws {
        let app = try launchFixture(audible: true)
        let identity = try mediaIdentity(app)
        let web = app.webViews.firstMatch
        let start = web.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.75))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 85)))
        XCTAssertTrue(app.buttons["browser.watch.exit"].isHittable,
                      "An ordinary pull in comments must not leave the watch presentation")
        let header = app.buttons["browser.watch.exit"]
            .coordinate(withNormalizedOffset: CGVector(dx: 3.5, dy: 0.5))
        header.press(forDuration: 0.05, thenDragTo: header.withOffset(CGVector(dx: 0, dy: 95)))
        XCTAssertTrue(app.textFields["Suchen oder Adresse"].waitForExistence(timeout: 8))
        XCTAssertEqual(try mediaIdentity(app), identity)
        try requireSustainedPlayback(app)
    }

    func testWebsiteSystemFullscreenReturnsToSameVideoAndBrowser() throws {
        let app = try launchFixture(audible: true)
        let identity = try mediaIdentity(app)
        app.buttons["Website-Systemplayer"].tap()
        // Native WebKit video fullscreen, including on an iPhone whose HTML
        // Element Fullscreen API may be unavailable. Actual system control.
        let exit = app.buttons.matching(NSPredicate(format:
            "identifier == 'Close Button' OR label MATCHES[c] '(Done|Fertig|Close|Schließen|.*Exit Full.?Screen.*|.*Vollbild beenden.*)'"
        )).firstMatch
        if !exit.exists || !exit.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        }
        let visible = exit.waitForExistence(timeout: 8)
        if !visible {
            print("WEBKIT_IPHONE_FULLSCREEN_CONTROLS \(app.debugDescription)")
            capturePlayerDiagnostic(app)
        }
        XCTAssertTrue(visible)
        XCTAssertTrue(exit.isHittable)
        exit.tap()
        XCTAssertTrue(app.buttons["browser.actions"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["browser.watch.exit"].isHittable)
        XCTAssertEqual(try mediaIdentity(app), identity)
        try requireSustainedPlayback(app)
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
        // Actual input inside the media rectangle must arm the bridge before play.
        app.buttons["Videostart"].tap()
        let resumed = app.staticTexts["Video läuft"].waitForExistence(timeout: 8)
        if !resumed { capturePlayerDiagnostic(app) }
        XCTAssertTrue(resumed)
        milestone("First real host touch resumed decoder playback")
        XCTAssertTrue(app.buttons["browser.watch.exit"].isHittable)
        XCTAssertTrue(app.buttons["browser.watch.home"].isHittable)
    }

    func testAudibleVideoKeepsAdvancingWithRealWebsitePlayAndAppPause() throws {
        let app = try launchFixture(audible: true)
        XCTAssertTrue(app.staticTexts["Ton aktiv"].exists)
        milestone("Unmuted fixture keeps decoding beyond startup")
        try requireSustainedPlayback(app)
        app.buttons["browser.actions"].tap()
        let pause = app.buttons["Alles pausieren"]
        reveal(pause, in: app); pause.tap()
        XCTAssertTrue(app.staticTexts["Video pausiert"].waitForExistence(timeout: 5))
        app.buttons["Videostart"].tap()
        let resumed = app.staticTexts["Video läuft"].waitForExistence(timeout: 8)
        if !resumed { capturePlayerDiagnostic(app) }
        XCTAssertTrue(resumed)
        try requireSustainedPlayback(app)
        milestone("Unmuted player remains advancing after first real website Play")
    }
}

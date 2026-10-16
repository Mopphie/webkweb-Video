import XCTest
import AVKit

/// A real HTML video inside the app's WKWebView, not its separate AVPlayer.
/// Own generated media only; does not establish YouTube availability/permission.
@MainActor
final class BrowserWebPlaybackJourneyUITests: XCTestCase {
    override func tearDownWithError() throws {
        let app = XCUIApplication()
        if testRun?.hasSucceeded == false, let value = app.buttons["browser.actions"].value as? String {
            print("WEBKIT_MEDIA_DIAGNOSTIC \(value)")
            let attachment = XCTAttachment(string: value)
            attachment.name = "Own WebKit media state at failure"; attachment.lifetime = .keepAlways; add(attachment)
        }
        app.terminate()
        try super.tearDownWithError()
    }

    private func report(_ app: XCUIApplication) throws -> (id: String, time: Double, duration: Double, playing: Bool, mode: String) {
        let value = try XCTUnwrap(app.buttons["browser.actions"].value as? String)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any])
        let native = try XCTUnwrap(json["native"] as? [String: Any]), web = try XCTUnwrap(json["web"] as? [String: Any])
        return (try XCTUnwrap(native["media_id"] as? String),
                try XCTUnwrap(native["time"] as? Double), try XCTUnwrap(native["duration"] as? Double),
                native["playing"] as? Bool == true, web["presentation_mode"] as? String ?? "unknown")
    }

    private func wait(_ predicate: @escaping () -> Bool, seconds: TimeInterval = 12) {
        expectation(for: NSPredicate { _, _ in predicate() }, evaluatedWith: nil)
        waitForExpectations(timeout: seconds)
    }

    private func systemButton(_ pattern: String, identifier: String, in app: XCUIApplication) -> XCUIElement {
        // Actual identifiers/labels from run 38965491481: PIP Button is labeled
        // "Video minimieren" in German, rather than containing "Bild in Bild".
        let button = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label MATCHES[c] %@", identifier, pattern)).firstMatch
        if !button.exists || !button.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap() }
        if !button.waitForExistence(timeout: 8) {
            let details = app.debugDescription
            print("WEBKIT_PLAYER_CONTROLS \(details)")
            let attachment = XCTAttachment(string: details)
            attachment.name = "Own WebKit video system controls"; attachment.lifetime = .keepAlways; add(attachment)
            XCTFail("Required public system player control missing: \(pattern)")
        }
        return button
    }

    private func launchWebsiteFixture() throws -> XCUIApplication {
        let app = XCUIApplication()
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "audible", withExtension: "mp4"))
        app.launchArguments = ["--ui-test-browser"]
        app.launchEnvironment["WEBKWEB_UI_TEST_MEDIA"] = try Data(contentsOf: url).base64EncodedString()
        app.launchEnvironment["WEBKWEB_UI_TEST_AUDIBLE"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["Videostart"].waitForExistence(timeout: 60))
        app.buttons["Videostart"].tap()
        XCTAssertTrue(app.staticTexts["Video läuft"].waitForExistence(timeout: 15))
        return app
    }

    func testElementFullscreenAndReturnWhenDocumentReportsSupport() throws {
        continueAfterFailure = false; executionTimeAllowance = 300
        let app = try launchWebsiteFixture()
        try XCTSkipIf(app.staticTexts["Element-Vollbild nicht unterstützt"].exists,
                      "The actual WebKit document reports no Element Fullscreen API. Element journey NOT EXECUTED; video system fullscreen is tested separately.")
        XCTAssertTrue(app.staticTexts["Element-Vollbild unterstützt"].exists)
        let initial = try report(app)
        app.buttons["Website-Vollbild"].tap()
        // Only a real fullscreenchange with document.fullscreenElement makes
        // this fixture-owned exit visible. No configuration-only pass.
        let exit = app.buttons["Website-Vollbild verlassen"]
        XCTAssertTrue(exit.waitForExistence(timeout: 8)); exit.tap()
        XCTAssertTrue(exit.waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.buttons["browser.watch.exit"].isHittable)
        XCTAssertEqual(try report(app).id, initial.id)
    }

    func testWebKitVideoSystemPiPOtherAppAndReturnToBrowser() throws {
        continueAfterFailure = false; executionTimeAllowance = 600
        try XCTSkipIf(!AVPictureInPictureController.isPictureInPictureSupported(),
                      "Framework reports no system PiP support. WebKit journey NOT EXECUTED.")
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.activate()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 20))
        let app = try launchWebsiteFixture()
        let initial = try report(app)
        XCTAssertFalse(initial.id.isEmpty)
        XCTAssertGreaterThan(initial.duration, 59)
        app.buttons["Website-Systemplayer"].tap()
        systemButton(".*(Picture.?in.?Picture|Bild.?in.?Bild|Video minimieren).*", identifier: "PIP Button", in: app).tap()
        XCTAssertTrue(app.buttons["browser.actions"].waitForExistence(timeout: 12))
        wait { (try? self.report(app).mode) == "picture-in-picture" }
        let before = try report(app), wall = Date()
        print("WEBKIT_PIP_BEFORE time=\(before.time) mode=\(before.mode) playing=\(before.playing)")
        XCTAssertEqual(before.id, initial.id)
        XCTAssertTrue(before.playing)
        XCUIDevice.shared.press(.home)
        safari.activate()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 20))
        Thread.sleep(forTimeInterval: 5)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        wait { (try? self.report(app).playing) == true }
        let after = try report(app), elapsed = Date().timeIntervalSince(wall)
        var progress = after.time - before.time
        while progress < elapsed - after.duration / 2 { progress += after.duration }
        print("WEBKIT_PIP_AFTER time=\(after.time) mode=\(after.mode) playing=\(after.playing) wall=\(elapsed) progress=\(progress)")
        XCTAssertEqual(after.id, initial.id)
        XCTAssertEqual(after.mode, "picture-in-picture")
        XCTAssertGreaterThanOrEqual(progress, elapsed - 3)
        XCTAssertLessThanOrEqual(progress, elapsed + 3)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let restore = springboard.buttons.matching(NSPredicate(format:
            "label == 'Restore fullscreen' OR label == 'Vollbild wiederherstellen'")).firstMatch
        if !restore.waitForExistence(timeout: 1) {
            let window = springboard.windows.matching(NSPredicate(format:
                "label == 'Picture in Picture' OR label == 'Bild in Bild'")).firstMatch
            XCTAssertTrue(window.waitForExistence(timeout: 5))
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        }
        XCTAssertTrue(restore.waitForExistence(timeout: 8)); restore.tap()
        systemButton("(Done|Fertig|Close|Schließen|.*Exit Full.?Screen.*|.*Vollbild beenden.*)", identifier: "Close Button", in: app).tap()
        XCTAssertTrue(app.buttons["browser.watch.exit"].waitForExistence(timeout: 12))
        app.buttons["browser.watch.exit"].tap()
        XCTAssertTrue(app.textFields["Suchen oder Adresse"].waitForExistence(timeout: 8))
        XCTAssertEqual(try report(app).id, initial.id)
        XCTAssertNotEqual(try report(app).mode, "picture-in-picture")
    }
}

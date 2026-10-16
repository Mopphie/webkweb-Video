import XCTest

/// Own generated media only. MUST run on a PiP-capable iPhone/iPad; not yet run.
@MainActor
final class NativePlaybackJourneyUITests: XCTestCase {
    private func systemButton(_ pattern: String, app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", pattern)).firstMatch
    }
    func testVideoFullscreenBackPiPOtherAppQueueNextAndSearch() throws {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = XCUIApplication()
        let clip = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "audible", withExtension: "mp4"))
        app.launchArguments = ["--ui-test-native"]
        app.launchEnvironment["WEBKWEB_UI_TEST_MEDIA"] = try Data(contentsOf: clip).base64EncodedString()
        app.launch()
        let status = app.buttons["native.expand"]
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        let playing = NSPredicate { _, _ in (status.value as? String)?.contains("playing=true") == true }
        expectation(for: playing, evaluatedWith: nil); waitForExpectations(timeout: 20)
        let before = try XCTUnwrap(status.value as? String)
        func seconds(_ text: String) -> Double { Double(text.components(separatedBy: ";").first?.replacingOccurrences(of: "time=", with: "") ?? "") ?? -1 }
        let beforeClock = seconds(before), beforeWall = Date()
        let full = systemButton(".*(Enter Full.?Screen|Vollbild).*", app: app)
        XCTAssertTrue(full.waitForExistence(timeout: 5)); full.tap()
        let done = systemButton("(Done|Fertig|Exit Full.?Screen|Vollbild beenden)", app: app)
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let pip = systemButton(".*(Picture in Picture|Bild.in.Bild|Start PiP).*", app: app)
        XCTAssertTrue(pip.waitForExistence(timeout: 5), "This mandatory journey needs real PiP support; no fallback pass")
        pip.tap()
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 5))
        app.activate()
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let after = try XCTUnwrap(status.value as? String)
        XCTAssertTrue(after.contains("playing=true"))
        let progress = seconds(after) - beforeClock
        XCTAssertGreaterThan(progress, 0.1, "Clock must advance across PiP/background; no restart fallback")
        XCTAssertLessThanOrEqual(progress, Date().timeIntervalSince(beforeWall) + 2, "Unexpected seek or wrong clock")
        let identity = before.components(separatedBy: ";media=").last
        XCTAssertEqual(after.components(separatedBy: ";media=").last, identity)
        app.buttons["native.queue"].tap()
        let next = app.buttons["native.queue.next"]; XCTAssertTrue(next.waitForExistence(timeout: 5)); next.tap()
        app.buttons["Fertig"].firstMatch.tap()
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let changed = NSPredicate { _, _ in (status.value as? String)?.components(separatedBy: ";media=").last != identity }
        expectation(for: changed, evaluatedWith: nil); waitForExpectations(timeout: 10)
        let search = app.textFields["Suchen oder Adresse"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Eigene Testsuche")
        XCTAssertTrue(app.buttons["native.queue"].isHittable)
    }
}

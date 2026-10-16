import XCTest

/// Own generated media only. Requires actual AVKit fullscreen and system PiP.
@MainActor
final class NativePlaybackJourneyUITests: XCTestCase {
    override func tearDownWithError() throws {
        XCUIApplication().terminate()
        try super.tearDownWithError()
    }
    private func systemButton(_ pattern: String, app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", pattern)).firstMatch
    }
    private func revealPlayerControls(in app: XCUIApplication) {
        let surface = app.descendants(matching: .any).matching(identifier: "native.player").firstMatch
        // AVKit hides controls while the test waits for actual playback. Reveal
        // them with a real touch away from the central Play/Pause hit target.
        if surface.exists && surface.isHittable {
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        } else {
            // AVKit presents a separate fullscreen controller. The original
            // inline representable is intentionally absent from its AX tree.
            // The expected system button must still appear after this touch.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        }
    }
    private func requireSystemButton(_ pattern: String, app: XCUIApplication,
                                     file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let button = systemButton(pattern, app: app)
        if !button.exists { revealPlayerControls(in: app) }
        let exists = button.waitForExistence(timeout: 5)
        if !exists {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "System player controls"; hierarchy.lifetime = .keepAlways
            add(hierarchy)
            print("NATIVE_PLAYER_ACCESSIBILITY \(app.debugDescription)")
        }
        XCTAssertTrue(exists, "Required system player control: \(pattern)", file: file, line: line)
        return button
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
        // AVKit auto-hides controls while playing, including during XCTest's
        // quiescence wait between lookup and tap. A real Pause keeps them
        // reachable without changing AVKit or relying on private test APIs.
        app.buttons["native.toggle"].tap()
        let paused = NSPredicate { _, _ in (status.value as? String)?.contains("playing=false") == true }
        expectation(for: paused, evaluatedWith: nil); waitForExpectations(timeout: 5)
        let full = requireSystemButton(".*(Full.?Screen|Vollbild).*", app: app)
        full.tap()
        let done = requireSystemButton("(Done|Fertig|.*Exit Full.?Screen.*|.*Vollbild beenden.*)", app: app)
        done.tap()
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let pip = requireSystemButton(".*(Picture in Picture|Bild.in.Bild|Start PiP).*", app: app)
        pip.tap()
        let enteredPiP = NSPredicate { _, _ in (status.value as? String)?.contains("pip=true") == true }
        expectation(for: enteredPiP, evaluatedWith: nil); waitForExpectations(timeout: 10)
        app.buttons["native.toggle"].tap()
        expectation(for: playing, evaluatedWith: nil); waitForExpectations(timeout: 10)
        let beforeClock = seconds(try XCTUnwrap(status.value as? String)), beforeWall = Date()
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

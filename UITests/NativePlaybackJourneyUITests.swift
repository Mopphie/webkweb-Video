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
    private func launchNativeFixture() throws -> XCUIApplication {
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
        return app
    }
    private func waitUntilPlaying(_ status: XCUIElement) {
        let playing = NSPredicate { _, _ in (status.value as? String)?.contains("playing=true") == true }
        expectation(for: playing, evaluatedWith: nil); waitForExpectations(timeout: 20)
    }
    private func fullscreenAndReturn(_ app: XCUIApplication, status: XCUIElement) {
        // AVKit auto-hides controls while playing, including during XCTest's
        // quiescence wait between lookup and tap. A real Pause keeps them
        // reachable without changing AVKit or relying on private test APIs.
        app.buttons["native.toggle"].tap()
        let paused = NSPredicate { _, _ in (status.value as? String)?.contains("playing=false") == true }
        expectation(for: paused, evaluatedWith: nil); waitForExpectations(timeout: 5)
        let full = requireSystemButton(".*(Full.?Screen|Vollbild).*", app: app)
        full.tap()
        let done = requireSystemButton("(Done|Fertig|Close|Schließen|.*Exit Full.?Screen.*|.*Vollbild beenden.*)", app: app)
        done.tap()
        XCTAssertTrue(status.waitForExistence(timeout: 5))
    }
    private func seconds(_ text: String) -> Double {
        Double(text.components(separatedBy: ";").first?.replacingOccurrences(of: "time=", with: "") ?? "") ?? -1
    }
    private func queueNextAndSearch(_ app: XCUIApplication, status: XCUIElement, identity: String?) throws {
        app.buttons["native.queue"].tap()
        let next = app.buttons["native.queue.next"]; XCTAssertTrue(next.waitForExistence(timeout: 5)); next.tap()
        app.buttons["Fertig"].firstMatch.tap()
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let changed = NSPredicate { _, _ in
            guard let text = status.value as? String else { return false }
            return text.components(separatedBy: ";media=").last != identity && text.contains("playing=true") && self.seconds(text) > 0.5
        }
        expectation(for: changed, evaluatedWith: nil); waitForExpectations(timeout: 10)
        let search = app.textFields["Suchen oder Adresse"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Eigene Testsuche")
        XCTAssertTrue(app.buttons["native.queue"].isHittable)
    }
    func testNativeFullscreenBackQueueNextAndSearch() throws {
        let app = try launchNativeFixture(), status = app.buttons["native.expand"]
        let identity = (status.value as? String)?.components(separatedBy: ";media=").last
        fullscreenAndReturn(app, status: status)
        app.buttons["native.toggle"].tap(); waitUntilPlaying(status)
        try queueNextAndSearch(app, status: status, identity: identity)
    }
    func testVideoFullscreenBackPiPOtherAppQueueNextAndSearch() throws {
        let app = try launchNativeFixture(), status = app.buttons["native.expand"]
        let before = try XCTUnwrap(status.value as? String)
        let capability = try XCTUnwrap(before.components(separatedBy: ";").first(where: { $0.hasPrefix("pip_supported=") }))
        print("NATIVE_SYSTEM_CAPABILITY \(capability)")
        // Only the public framework's explicit unsupported result permits a
        // skip. Missing buttons, failed PiP callbacks or stalled clocks on a
        // supported device continue to fail; no simulated PiP success.
        try XCTSkipIf(capability == "pip_supported=false", "System-PiP wird von dieser Laufzeit nicht unterstützt. Pflichtreise NICHT AUSGEFÜHRT; auf unterstütztem Gerät erforderlich.")
        fullscreenAndReturn(app, status: status)
        app.buttons["native.toggle"].tap(); waitUntilPlaying(status)
        func field(_ text: String, _ key: String) throws -> Double {
            let value = try XCTUnwrap(text.components(separatedBy: ";").first(where: { $0.hasPrefix(key + "=") }))
            return try XCTUnwrap(Double(value.dropFirst(key.count + 1)))
        }
        let ready = try XCTUnwrap(status.value as? String)
        let startsBefore = try field(ready, "pip_starts")
        let beforeClock = seconds(ready), beforeWall = Date()
        // Exercise the supported automatic inline PiP behavior that users get
        // when leaving the app. AVKit's own delegate is the sole event source.
        XCUIDevice.shared.press(.home)
        let otherApp = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        otherApp.activate()
        XCTAssertTrue(otherApp.wait(for: .runningForeground, timeout: 10))
        Thread.sleep(forTimeInterval: 3)
        let returningAt = Date()
        app.activate()
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let returned = try XCTUnwrap(status.value as? String)
        XCTAssertGreaterThan(try field(returned, "pip_starts"), startsBefore, "Actual AVKit PiP start callback required")
        let startedAt = try field(returned, "pip_started_at")
        XCTAssertGreaterThanOrEqual(startedAt, beforeWall.timeIntervalSince1970)
        XCTAssertLessThanOrEqual(startedAt, returningAt.timeIntervalSince1970, "PiP must start during the real app switch")
        if returned.contains("pip=true") {
            // AVKit's inline placeholder restores the same player with a touch.
            app.descendants(matching: .any).matching(identifier: "native.player").firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let restored = NSPredicate { _, _ in (status.value as? String)?.contains("pip=false") == true }
            expectation(for: restored, evaluatedWith: nil); waitForExpectations(timeout: 10)
        }
        let after = try XCTUnwrap(status.value as? String)
        XCTAssertTrue(after.contains("playing=true"))
        let progress = seconds(after) - beforeClock
        XCTAssertGreaterThan(progress, 0.1, "Clock must advance across PiP/background; no restart fallback")
        XCTAssertGreaterThanOrEqual(progress, Date().timeIntervalSince(beforeWall) - 2, "Playback must continue throughout the app switch")
        XCTAssertLessThanOrEqual(progress, Date().timeIntervalSince(beforeWall) + 2, "Unexpected seek or wrong clock")
        let identity = before.components(separatedBy: ";media=").last
        XCTAssertEqual(after.components(separatedBy: ";media=").last, identity)
        try queueNextAndSearch(app, status: status, identity: identity)
    }
}

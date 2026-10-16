import XCTest
import UIKit
import WebKit
@testable import WebKWeb

/// Decodes the generated H.264/AAC fixture in a visible, real WKWebView.
/// These tests require the Apple SDK and a running iOS simulator/device.
@MainActor
final class MediaPlaybackIntegrationTests: XCTestCase {
    private enum Failure: Error { case timeout(String) }

    @MainActor
    private final class Session {
        let browser: BrowserModel
        let window: UIWindow
        private weak var previousKeyWindow: UIWindow?
        private static let keys = [PreferencesStorage.key, "browserSessionV2", "sleepPlanV2", "playbackQueueV1"]
        private let saved: [String: Any]

        init() {
            let defaults = UserDefaults.standard
            var stored: [String: Any] = [:]
            for key in Self.keys { stored[key] = defaults.object(forKey: key) }
            saved = stored
            var options = BrowserPreferences()
            options.blocking = false; options.restoreTabs = false; options.history = false
            PreferencesStorage.save(options)
            for key in Self.keys where key != PreferencesStorage.key { defaults.removeObject(forKey: key) }
            browser = BrowserModel()
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            if let scene { window = UIWindow(windowScene: scene) }
            else { window = UIWindow(frame: UIScreen.main.bounds) }
            previousKeyWindow = scene?.windows.first(where: \.isKeyWindow)
            window.frame = scene?.coordinateSpace.bounds ?? UIScreen.main.bounds
            let controller = UIViewController()
            window.rootViewController = controller
            browser.current.webView.frame = controller.view.bounds
            browser.current.webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            controller.view.addSubview(browser.current.webView)
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
        }

        func close() {
            browser.cancelSleep()
            browser.tabs.forEach { $0.close() }
            window.isHidden = true; window.rootViewController = nil
            previousKeyWindow?.makeKey()
            let defaults = UserDefaults.standard
            for key in Self.keys {
                if let value = saved[key] { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
    }

    private func waitFor(_ description: String, timeout: TimeInterval = 12,
                         until condition: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? await condition()) == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Timed out: \(description)")
        throw Failure.timeout(description)
    }

    private func loadFixture(in session: Session) async throws {
        let bundle = Bundle(for: MediaPlaybackIntegrationTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "sample", withExtension: "mp4"))
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 0)
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body style="margin:0;background:black"><video id="player" playsinline muted preload="auto"
        style="width:320px;height:180px" src="data:video/mp4;base64,\(data.base64EncodedString())"></video></body></html>
        """
        let tab = session.browser.current
        tab.webView.loadHTMLString(html, baseURL: nil)
        try await waitFor("original bridge and decoded video metadata") {
            guard tab.hasMedia, tab.activeMediaKind == "video", !tab.activeMediaID.isEmpty,
                  let duration = tab.duration, duration > 3 else { return false }
            return try await tab.webView.evaluateJavaScript(
                "Boolean(globalThis.__webkweb) && document.getElementById('player').readyState >= 2",
                in: nil, in: BrowserTab.world) as? Bool == true
        }
    }

    func testRealVideoStartsAdvancesPausesAndSeeksThroughNativeBridge() async throws {
        let session = Session(); defer { session.close() }
        try await loadFixture(in: session)
        let browser = session.browser, tab = browser.current
        XCTAssertFalse(tab.playing)
        browser.play()
        try await waitFor("native playing state and actual playback progress") { tab.playing && tab.playbackTime > 0.2 }
        browser.pauseAll()
        try await waitFor("native pause acknowledgement") { !tab.playing && !tab.hasActivePlayback }
        let pausedTime = try await tab.webView.evaluateJavaScript(
            "document.getElementById('player').currentTime", in: nil, in: BrowserTab.world) as? Double ?? -1
        try await Task.sleep(for: .milliseconds(250))
        let stableTime = try await tab.webView.evaluateJavaScript(
            "document.getElementById('player').currentTime", in: nil, in: BrowserTab.world) as? Double ?? -2
        XCTAssertEqual(stableTime, pausedTime, accuracy: 0.15)
        browser.seek(0.8)
        try await waitFor("real seek updates native position while remaining paused") {
            !tab.playing && tab.playbackTime >= pausedTime + 0.6
        }
        tab.runMedia("globalThis.__webkweb?.setRate(1.5)")
        try await waitFor("native playback rate acknowledgement") { tab.playbackRate == 1.5 }
        XCTAssertTrue(tab.muted)
        browser.play()
        try await waitFor("explicit resume clears native stop latch") { tab.playing && !browser.playbackStopped }
    }

    func testNaturalVideoEndCompletesNativeTimerAndStopsNewAutoplayPlayer() async throws {
        let session = Session(); defer { session.close() }
        try await loadFixture(in: session)
        let browser = session.browser, tab = browser.current
        browser.sleep(videos: 1)
        XCTAssertEqual(browser.sleepPlan.remainingVideos, 1)
        browser.seek(3.1)
        browser.play()
        try await waitFor("real decoder reaches natural end and native N-video timer stops") {
            browser.playbackStopped && !browser.sleepPlan.isActive && !tab.playing
        }
        let ended = try await tab.webView.evaluateJavaScript(
            "document.getElementById('player').ended", in: nil, in: BrowserTab.world) as? Bool
        XCTAssertEqual(ended, true)
        XCTAssertTrue(browser.notice?.contains("Sleep-Timer") == true)
        _ = try await tab.webView.evaluateJavaScript("""
            (() => {
              const next = document.getElementById('player').cloneNode(true);
              next.id = 'next'; next.autoplay = true; next.muted = true;
              document.body.appendChild(next); next.play().catch(() => {}); return true;
            })()
            """, in: nil, in: BrowserTab.world)
        try await waitFor("timer stop latch pauses a newly inserted real autoplay player") {
            try await tab.webView.evaluateJavaScript(
                "document.getElementById('next').readyState >= 2 && document.getElementById('next').paused",
                in: nil, in: BrowserTab.world) as? Bool == true
        }
        XCTAssertTrue(browser.playbackStopped)
    }
}

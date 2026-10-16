import XCTest
import UIKit
import WebKit
import AVFoundation
@testable import WebKWeb

/// Decodes the generated H.264/AAC fixture in a visible, real WKWebView.
/// These tests require the Apple SDK and a running iOS simulator/device.
@MainActor
final class MediaPlaybackIntegrationTests: XCTestCase {
    private enum Failure: Error { case timeout(String), javaScriptTimeout }
    private weak var activeSession: Session?

    @MainActor
    private final class JavaScriptReply {
        private var continuation: CheckedContinuation<Any, Error>?
        init(_ continuation: CheckedContinuation<Any, Error>) { self.continuation = continuation }
        func finish(_ result: Result<Any, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(with: result)
        }
    }

    private func evaluate(_ script: String, in tab: BrowserTab) async throws -> Any {
        // The named-content-world overload has an optional callback and returns
        // Void when omitted. Explicitly await its Result instead of that overload.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any, Error>) in
            let reply = JavaScriptReply(continuation)
            let deadline = Task {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                reply.finish(.failure(Failure.javaScriptTimeout))
            }
            tab.webView.evaluateJavaScript(script, in: nil, in: BrowserTab.world) { result in
                deadline.cancel()
                reply.finish(result)
            }
        }
    }

    @MainActor
    private final class Session {
        let browser: BrowserModel
        let window: UIWindow
        private weak var previousKeyWindow: UIWindow?
        private static let keys = [PreferencesStorage.key, "browserSessionV2", "sleepPlanV2", "playbackQueueV1"]
        private let saved: [String: Any]

        init(restored: Bool = false) {
            let defaults = UserDefaults.standard
            var stored: [String: Any] = [:]
            for key in Self.keys { stored[key] = defaults.object(forKey: key) }
            saved = stored
            var options = BrowserPreferences()
            options.blocking = false; options.restoreTabs = restored; options.history = false
            PreferencesStorage.save(options)
            for key in Self.keys where key != PreferencesStorage.key { defaults.removeObject(forKey: key) }
            if restored {
                let tab = TabSnapshot(id: UUID(), address: "", title: "Restored")
                defaults.set(try? JSONEncoder().encode(BrowserSessionSnapshot(tabs: [tab], selected: tab.id)), forKey: "browserSessionV2")
            }
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
        let details = await diagnostics()
        print("WEBKWEB_MEDIA_DIAGNOSTIC \(description): \(details)")
        let attachment = XCTAttachment(string: details)
        attachment.name = "Media state at \(description)"; attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail("Timed out: \(description). \(details)")
        throw Failure.timeout(description)
    }

    private func diagnostics() async -> String {
        guard let session = activeSession else { return "No active media test session" }
        let tab = session.browser.current
        let native = "nativeHasMedia=\(tab.hasMedia), playing=\(tab.playing), activeMedia=\(tab.activeMediaID), kind=\(tab.activeMediaKind), time=\(tab.playbackTime), duration=\(String(describing: tab.duration)), stop=\(session.browser.playbackStopped), error=\(tab.error ?? tab.mediaError), windowHidden=\(session.window.isHidden), frame=\(tab.webView.frame)"
        do {
            let result = try await evaluate("""
                JSON.stringify((() => {
                  const v = document.getElementById('player');
                  return {bridge: typeof globalThis.__webkweb,
                    handler: Boolean(window.webkit?.messageHandlers?.playback),
                    documentReady: document.readyState, visibility: document.visibilityState,
                    location: location.href, userAgent: navigator.userAgent,
                    player: v ? {readyState:v.readyState, networkState:v.networkState,
                      duration:Number.isFinite(v.duration) ? v.duration : String(v.duration),
                      time:v.currentTime, paused:v.paused, ended:v.ended, muted:v.muted,
                      sourceScheme:v.currentSrc.split(':')[0],
                      error:v.error ? {code:v.error.code, message:v.error.message} : null} : null};
                })())
                """, in: tab)
            return "\(native); JavaScript=\(result)"
        } catch { return "\(native); JavaScript error=\(error)" }
    }

    private func loadFixture(in session: Session, audible: Bool = false) async throws {
        activeSession = session
        let bundle = Bundle(for: MediaPlaybackIntegrationTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "sample", withExtension: "mp4"))
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 0)
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body style="margin:0;background:black"><video id="player" playsinline \(audible ? "" : "muted") preload="auto"
        style="width:320px;height:180px" src="data:video/mp4;base64,\(data.base64EncodedString())"></video></body></html>
        """
        let tab = session.browser.current
        tab.webView.loadHTMLString(html, baseURL: nil)
        try await waitFor("original bridge and native frame registration") {
            let ready = try await self.evaluate(
                "Boolean(globalThis.__webkweb) && Boolean(document.getElementById('player'))", in: tab) as? Bool == true
            return ready && tab.hasMedia && tab.activeMediaKind == "video" && !tab.activeMediaID.isEmpty
        }
    }

    func testRealVideoStartsAdvancesPausesAndSeeksThroughNativeBridge() async throws {
        let session = Session(); defer { session.close() }
        try await loadFixture(in: session)
        let browser = session.browser, tab = browser.current
        XCTAssertFalse(tab.playing)
        browser.play()
        try await waitFor("native playing state and actual playback progress") { tab.playing && tab.playbackTime > 0.2 }
        XCTAssertGreaterThan(try XCTUnwrap(tab.duration), 3)
        browser.pauseAll()
        try await waitFor("native pause acknowledgement") { !tab.playing && !tab.hasActivePlayback }
        let pausedTime = try await evaluate("document.getElementById('player').currentTime", in: tab) as? Double ?? -1
        try await Task.sleep(for: .milliseconds(250))
        let stableTime = try await evaluate("document.getElementById('player').currentTime", in: tab) as? Double ?? -2
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
        // Mobile WebKit may ignore preload. Start through the actual native Play
        // path before requiring decoded metadata, then arm the end timer paused.
        browser.play()
        try await waitFor("play loads real media metadata") {
            let decoded = try await self.evaluate("document.getElementById('player').readyState >= 2", in: tab) as? Bool == true
            return decoded && tab.playing && (tab.duration ?? 0) > 3
        }
        browser.pauseAll()
        try await waitFor("pause before arming end timer") { !tab.playing && !tab.hasActivePlayback }
        browser.sleep(videos: 1)
        XCTAssertEqual(browser.sleepPlan.remainingVideos, 1)
        browser.seek(3.1)
        browser.play()
        try await waitFor("real decoder reaches natural end and native N-video timer stops") {
            browser.playbackStopped && !browser.sleepPlan.isActive && !tab.playing
        }
        let ended = try await evaluate("document.getElementById('player').ended", in: tab) as? Bool
        XCTAssertEqual(ended, true)
        XCTAssertTrue(browser.notice?.contains("Sleep-Timer") == true)
        _ = try await evaluate("""
            (() => {
              const next = document.getElementById('player').cloneNode(true);
              next.id = 'next'; next.autoplay = true; next.muted = true;
              next.addEventListener('play', () => { next.dataset.playObserved = 'true'; });
              document.body.appendChild(next); next.play().catch(() => {}); return true;
            })()
            """, in: tab)
        try await waitFor("timer stop latch pauses a newly inserted real autoplay player") {
            try await self.evaluate(
                "document.getElementById('next').dataset.playObserved === 'true' && document.getElementById('next').paused",
                in: tab) as? Bool == true
        }
        XCTAssertTrue(browser.playbackStopped)
    }

    func testRestoredRealPlayerStaysQuietAndExplicitStartWorksAfterSelection() async throws {
        let session = Session(restored: true); defer { session.close() }
        try await loadFixture(in: session)
        let browser = session.browser, tab = browser.current
        XCTAssertEqual(tab.webView.configuration.mediaTypesRequiringUserActionForPlayback, [])
        _ = try await evaluate("document.getElementById('player').play().catch(() => {}); true", in: tab)
        try await Task.sleep(for: .milliseconds(300))
        let paused = try await evaluate("document.getElementById('player').paused", in: tab) as? Bool
        XCTAssertEqual(paused, true)
        XCTAssertFalse(tab.playing)
        browser.play()
        try await waitFor("restored real video starts after explicit native Play") { tab.playing && tab.playbackTime > 0.2 }
        XCTAssertGreaterThan(try XCTUnwrap(tab.duration), 3)
    }

    func testAudibleVideoContinuesWithoutPermanentStopOnAudioNotification() async throws {
        let session = Session(); defer { session.close() }
        try await loadFixture(in: session, audible: true)
        let browser = session.browser, tab = browser.current
        browser.play()
        try await waitFor("unmuted H264/AAC actually advances") { tab.playing && tab.playbackTime > 0.3 }
        let muted = try await evaluate("document.getElementById('player').muted", in: tab) as? Bool
        XCTAssertEqual(muted, false)
        // Notification injection tests the app's response; it does not pretend
        // to create an actual phone call or hardware audio interruption.
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(browser.playbackStopped, "A temporary audio notification must not install the timer/autoplay stop latch")
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                       AVAudioSessionInterruptionOptionKey: UInt(0)])
        try await waitFor("unmuted playback remains advancing beyond the short startup window") {
            tab.playing && tab.playbackTime > 2.0 && !browser.playbackStopped
        }
    }

    func testAudioInterruptionDoesNotOverrideExplicitUserStop() async throws {
        let session = Session(); defer { session.close() }
        try await loadFixture(in: session, audible: true)
        let browser = session.browser, tab = browser.current
        browser.play()
        try await waitFor("audible video starts before interruption") { tab.playing && tab.playbackTime > 0.2 }
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        try await Task.sleep(for: .milliseconds(100))
        browser.pauseAll()
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                       AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
        try await waitFor("user pause remains acknowledged after shouldResume") { !tab.playing && browser.playbackStopped }
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(browser.playbackStopped)
        XCTAssertFalse(tab.playing)
    }

    func testAudioInterruptionCannotResumePastExpiredSleepDeadline() async throws {
        let session = Session(); defer { session.close() }
        try await loadFixture(in: session, audible: true)
        let browser = session.browser, tab = browser.current
        browser.play()
        try await waitFor("audible video starts before deadline interruption") { tab.playing && tab.playbackTime > 0.2 }
        browser.sleep(seconds: 1)
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        try await Task.sleep(for: .milliseconds(1200))
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                       AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
        try await waitFor("expired sleep timer stays stopped despite shouldResume") {
            browser.playbackStopped && !browser.sleepPlan.isActive && !tab.playing
        }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(browser.playbackStopped)
        XCTAssertFalse(tab.playing)
    }

    func testWatchExitRestoresSameRealDocumentWithoutRecreatingWebView() async throws {
        let session = Session(); defer { session.close() }
        activeSession = session
        let tab = session.browser.current, view = tab.webView
        tab.webView.loadHTMLString("<html><head><title>Original title</title></head><body><ytm-mobile-topbar-renderer>Website navigation</ytm-mobile-topbar-renderer><p id='content'>Original content</p></body></html>", baseURL: URL(string: "https://m.youtube.com/watch?v=abcdefghijk"))
        try await waitFor("genuine watch route is presented") {
            let decorated = try await self.evaluate("document.documentElement.hasAttribute('data-webkweb-watch')", in: tab) as? Bool == true
            return tab.presentsWatchImmersively && decorated
        }
        tab.showNormalWebsite()
        try await waitFor("normal website navigation is restored") {
            try await self.evaluate("!document.documentElement.hasAttribute('data-webkweb-watch') && !document.getElementById('webkweb-watch-presentation') && document.getElementById('content').textContent === 'Original content'", in: tab) as? Bool == true
        }
        XCTAssertFalse(tab.presentsWatchImmersively)
        XCTAssertTrue(tab.webView === view)
        XCTAssertEqual(tab.address, "https://m.youtube.com/watch?v=abcdefghijk")
    }
}

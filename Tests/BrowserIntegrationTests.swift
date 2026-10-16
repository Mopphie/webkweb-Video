import XCTest
import Combine
import WebKit
@testable import WebKWeb

@MainActor
final class BrowserIntegrationTests: XCTestCase {
    func testPrivateTabUsesNonPersistentStore() {
        let tab = BrowserTab(isPrivate: true)
        XCTAssertFalse(tab.webView.configuration.websiteDataStore.isPersistent)
        tab.close()
    }
    func testPlayerDiagnosticsExcludePrivatePagesCredentialsQueriesAndTitles() throws {
        for privateMode in [false, true] {
            let tab = BrowserTab(isPrivate: privateMode); defer { tab.close() }
            tab.address = "https://alice:secret@example.com/watch?v=private-token#fragment"
            tab.title = "Confidential page title"
            for _ in 0..<60 { tab.notePlaybackEvent("native.play") }
            let report = tab.mediaDiagnosticReport()
            for value in ["alice", "secret", "private-token", "fragment", "Confidential page title", "https://"] {
                XCTAssertFalse(report.contains(value))
            }
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(report.utf8)) as? [String: Any])
            XCTAssertEqual(json["site"] as? String, privateMode ? "private" : "example.com")
            XCTAssertEqual((json["events"] as? [[String: String]])?.count, 40)
        }
    }
    func testPrivatePopupRetainsConfiguredWebsiteDataStore() {
        let configuration = WKWebViewConfiguration()
        let existingStore = WKWebsiteDataStore.nonPersistent()
        configuration.websiteDataStore = existingStore
        let popup = BrowserTab(isPrivate: true, configuration: configuration)
        defer { popup.close() }
        XCTAssertTrue(popup.webView.configuration.websiteDataStore === existingStore)
        XCTAssertTrue(popup.webView.customUserAgent?.isEmpty ?? true,
                      "Use WebKit's native identity without a custom agent override")
    }
    func testCommittedDocumentReplacesPendingAddressForReloadAndRestore() async throws {
        let tab = BrowserTab(isPrivate: true)
        defer { tab.close() }
        tab.load(URL(string: "https://pending.example/original")!)
        tab.cancelPendingLoad()
        let destination = URL(string: "https://committed.example/final")!
        tab.webView.loadHTMLString("<html><body>committed</body></html>", baseURL: destination)
        var ready = false
        for _ in 0..<100 {
            if !tab.webView.isLoading, tab.address == destination.absoluteString,
               let text = try? await tab.webView.evaluateJavaScript("document.body.textContent") as? String,
               text == "committed" { ready = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(ready, "Committed WebKit document did not load")
        XCTAssertEqual(tab.sessionAddress, destination.absoluteString)
    }
    func testRestoredTabsKeepNormalPolicyQuietBootstrapAndPendingAddresses() throws {
        let defaults = UserDefaults.standard, key = "browserSessionV2"
        let old = defaults.data(forKey: key), oldOptions = defaults.data(forKey: PreferencesStorage.key)
        defer { defaults.set(old, forKey: key); defaults.set(oldOptions, forKey: PreferencesStorage.key) }
        var options = BrowserPreferences(); options.restoreTabs = true; PreferencesStorage.save(options)
        let first = TabSnapshot(id: UUID(), address: "https://example.com/first", title: "First")
        let second = TabSnapshot(id: UUID(), address: "https://example.com/second", title: "Second")
        defaults.set(try JSONEncoder().encode(BrowserSessionSnapshot(tabs: [first, second], selected: first.id)), forKey: key)
        let browser = BrowserModel(); defer { browser.tabs.forEach { $0.close() } }
        for tab in browser.tabs {
            XCTAssertEqual(tab.webView.configuration.mediaTypesRequiringUserActionForPlayback, [])
            XCTAssertTrue(tab.webView.configuration.userContentController.userScripts.contains { $0.source == "globalThis.__webkwebStartPaused = true" })
        }
        browser.persistSession()
        let saved = try JSONDecoder().decode(BrowserSessionSnapshot.self, from: XCTUnwrap(defaults.data(forKey: key)))
        XCTAssertEqual(saved.tabs.map(\.address), [first.address, second.address])
    }
    func testIntentRouterDrainsExactlyOnceInOrder() {
        // Isolate this queue from the live BrowserView subscriber, which drains the shared router.
        let router = IntentRouter()
        router.send(.open("https://example.com")); router.send(.pause)
        let commands = router.drain()
        XCTAssertEqual(commands.count, 2)
        guard commands.count == 2 else { return }
        if case .open(let value) = commands[0] { XCTAssertEqual(value, "https://example.com") } else { XCTFail("Order changed") }
        XCTAssertTrue(router.drain().isEmpty)
    }
    func testWipeWaitsForBlankDocumentCommit() async throws {
        let tab = BrowserTab(isPrivate: true)
        defer { tab.close() }
        tab.webView.loadHTMLString("<html><body>old-player</body></html>", baseURL: nil)
        // WebKit starts the first navigation asynchronously on CI simulators.
        // Wait for the initial document before testing the blank-document commit.
        var initialReady = false
        for _ in 0..<100 {
            if let text = try? await tab.webView.evaluateJavaScript("document.body.textContent") as? String,
               text == "old-player" {
                initialReady = true
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard initialReady else { XCTFail("Initial WebKit document did not load"); return }
        try await tab.prepareForWipe()
        let text = try await tab.webView.evaluateJavaScript("document.body.textContent")
        XCTAssertEqual(text as? String, "")
        tab.finishWipe()
        XCTAssertEqual(tab.address, "")
    }
    func testSessionSnapshotExcludesPrivateTabsAndCredentialInfo() throws {
        let defaults = UserDefaults.standard, key = "browserSessionV2"
        let saved = defaults.data(forKey: key), oldOptions = defaults.data(forKey: PreferencesStorage.key)
        defer { defaults.set(saved, forKey: key); defaults.set(oldOptions, forKey: PreferencesStorage.key) }
        defaults.removeObject(forKey: key)
        let browser = BrowserModel(); browser.options.restoreTabs = true
        browser.current.address = "https://alice:secret@example.com/video"
        let privateTab = browser.addTab(isPrivate: true); privateTab.address = "https://private.example/video"
        browser.persistSession()
        let data = try XCTUnwrap(defaults.data(forKey: key))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("private.example")); XCTAssertFalse(text.contains("secret")); XCTAssertFalse(text.contains("alice"))
        let snapshot = try JSONDecoder().decode(BrowserSessionSnapshot.self, from: data)
        XCTAssertNil(snapshot.selected)
        browser.tabs.forEach { $0.close() }
    }
    func testInvalidSleepRequestsKeepExistingDeadline() {
        let defaults = UserDefaults.standard, key = "sleepPlanV2"
        let previous = defaults.data(forKey: key)
        defer { defaults.set(previous, forKey: key) }
        let browser = BrowserModel()
        defer { browser.cancelSleep(); browser.tabs.forEach { $0.close() } }
        browser.sleep(seconds: 120)
        let original = browser.sleepPlan.deadline
        XCTAssertNotNil(original)
        browser.sleep(seconds: 0)
        XCTAssertEqual(browser.sleepPlan.deadline, original)
        browser.sleep(minutes: Int.max)
        XCTAssertEqual(browser.sleepPlan.deadline, original)
        browser.sleep(videos: 2) // No active video in the new tab.
        XCTAssertEqual(browser.sleepPlan.deadline, original)
        browser.sleep(videos: 0)
        XCTAssertEqual(browser.sleepPlan.deadline, original)
    }
    func testDialogQueueRetainsBothRepliesAndCancelsClosedTab() async {
        let browser = BrowserModel()
        let first = browser.current, second = browser.addTab()
        var replies: [String] = []
        let shown = expectation(description: "First dialog shown")
        let observer = browser.$dialog.compactMap { $0 }.first().sink { _ in shown.fulfill() }
        browser.enqueue(BrowserDialog(tabID: first.id, kind: .confirm, message: "A", defaultText: "", reply: { _ in replies.append("A") }))
        browser.enqueue(BrowserDialog(tabID: second.id, kind: .prompt, message: "B", defaultText: "", reply: { _ in replies.append("B") }))
        await fulfillment(of: [shown], timeout: 2)
        browser.close(second.id)
        browser.completeDialog("true")
        XCTAssertEqual(Set(replies), ["A", "B"])
        observer.cancel(); browser.tabs.forEach { $0.close() }
    }
}

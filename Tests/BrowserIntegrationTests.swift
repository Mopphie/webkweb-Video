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
    func testIntentRouterDrainsExactlyOnceInOrder() {
        let router = IntentRouter.shared
        _ = router.drain()
        router.send(.open("https://example.com")); router.send(.pause)
        let commands = router.drain()
        XCTAssertEqual(commands.count, 2)
        if case .open(let value) = commands[0] { XCTAssertEqual(value, "https://example.com") } else { XCTFail("Order changed") }
        XCTAssertTrue(router.drain().isEmpty)
    }
    func testWipeWaitsForBlankDocumentCommit() async throws {
        let tab = BrowserTab(isPrivate: true)
        defer { tab.close() }
        tab.webView.loadHTMLString("<html><body>old-player</body></html>", baseURL: nil)
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

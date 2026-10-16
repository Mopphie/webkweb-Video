import XCTest
import WebKit
@testable import WebKWeb

@MainActor
final class WorkspacePrivacyTests: XCTestCase {
    private func withSession(_ action: (BrowserModel) throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let keys = [PreferencesStorage.key, "browserSessionV2", "sleepPlanV2", "playbackQueueV1", "nativeQueueV1"]
        var saved: [String: Any] = [:]
        for key in keys { saved[key] = defaults.object(forKey: key); defaults.removeObject(forKey: key) }
        var options = BrowserPreferences(); options.restoreTabs = false; PreferencesStorage.save(options)
        let browser = BrowserModel()
        defer {
            browser.cancelSleep(); browser.nativePlayer.close(); browser.tabs.forEach { $0.close() }
            for key in keys { defaults.set(saved[key], forKey: key) }
        }
        try action(browser)
    }
    func testSavedFavoriteDoesNotInventAHistoryVisit() {
        let favorite = SavedPage(title: "Explicit link", address: "https://example.org/", favorite: true)
        XCTAssertFalse(favorite.isHistory); XCTAssertEqual(favorite.visitedAt, .distantPast)
        let visit = SavedPage(title: "Visited", address: "https://example.org/")
        XCTAssertTrue(visit.isHistory)
    }
    func testPrivateSessionEndNeverAddsPrivateClosedTabOrSnapshot() throws {
        try withSession { browser in
            browser.options.restoreTabs = true
            let tab = browser.addTab(isPrivate: true); tab.address = "https://private.invalid/confidential"; tab.title = "Private title"
            tab.pinned = true; tab.group = "Private group"
            browser.persistSession(); browser.endPrivateSession()
            XCTAssertFalse(browser.tabs.contains(where: \.isPrivate)); XCTAssertTrue(browser.closedTabs.isEmpty)
            let text = String(decoding: try XCTUnwrap(UserDefaults.standard.data(forKey: "browserSessionV2")), as: UTF8.self)
            for value in ["private.invalid", "Private title", "Private group"] { XCTAssertFalse(text.contains(value)) }
        }
    }
    func testTabLimitAndHomeFallbackKeepActiveObjectsBoundedAndNavigationReachable() {
        withSession { browser in
            for _ in 0..<20 { browser.addTab() }
            XCTAssertEqual(browser.tabs.count, 12)
            let original = browser.current.webView
            browser.backOrHome()
            XCTAssertEqual(browser.tabs.count, 12); XCTAssertTrue(browser.current.webView === original)
            XCTAssertEqual(browser.current.address, "")
        }
    }
    func testNormalClosedTabCanBeReopenedWithoutPrivateState() {
        withSession { browser in
            let tab = browser.addTab(); tab.address = "https://example.invalid/saved"; tab.title = "Saved"; tab.pinned = true; tab.group = "Work"
            browser.close(tab.id); XCTAssertEqual(browser.closedTabs.count, 1)
            browser.reopenClosedTab(); browser.current.cancelPendingLoad()
            XCTAssertTrue(browser.current.pinned); XCTAssertEqual(browser.current.group, "Work"); XCTAssertFalse(browser.current.isPrivate)
        }
    }
    func testPrivatePopupCannotReceivePersistentStoreEvenFromMalformedCaller() {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .default()
        let tab = BrowserTab(isPrivate: true, configuration: config); defer { tab.close() }
        XCTAssertFalse(tab.webView.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(tab.webView.configuration.allowsPictureInPictureMediaPlayback)
    }
    func testProcessTerminationClearsMediaAndOffersExplicitRecovery() {
        let tab = BrowserTab(isPrivate: true); defer { tab.close() }
        tab.hasMedia = true; tab.playing = true
        tab.webViewWebContentProcessDidTerminate(tab.webView)
        XCTAssertFalse(tab.hasMedia); XCTAssertFalse(tab.playing); XCTAssertNotNil(tab.error)
    }
    func testPlatformAndEmbeddedProviderControlsAreUnavailable() {
        let tab = BrowserTab(); defer { tab.close() }
        tab.address = "https://m.youtube.com/watch?v=abcdefghijk"; XCTAssertFalse(tab.canControlMedia)
        tab.address = "https://example.org/"; XCTAssertTrue(tab.canControlMedia)
    }
}

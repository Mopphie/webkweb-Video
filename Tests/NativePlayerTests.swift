import XCTest
import AVFoundation
@testable import WebKWeb

@MainActor
final class NativePlayerTests: XCTestCase {
    func testPristineHomeDoesNotWaitForUnstartedWebContent() async throws {
        let tab = BrowserTab(); defer { tab.close() }
        XCTAssertNil(tab.webView.url)
        try await tab.pauseBeforeNativePlayback()
        XCTAssertNil(tab.webView.url)
    }
    func testFailedWebsitePausePreventsNativeAudioAndExplicitRetryRecovers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let clip = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "audible", withExtension: "mp4"))
        let library = LibraryStore(file: root.appendingPathComponent("library.json"))
        let id = try library.addFile(clip), playback = NativePlayer(); playback.library = library
        playback.beforePlay = { throw URLError(.timedOut) }
        playback.open(id)
        defer { playback.close(); try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        for _ in 0..<200 { if playback.error != nil { break }; try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertNotNil(playback.error); XCTAssertFalse(playback.playing)
        XCTAssertEqual(playback.player.rate, 0); XCTAssertEqual(playback.player.currentTime().seconds, 0, accuracy: 0.1)
        playback.beforePlay = nil; playback.retry()
        for _ in 0..<200 { if playback.time > 0.5 && playback.playing { break }; try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertNil(playback.error); XCTAssertTrue(playback.playing); XCTAssertGreaterThan(playback.time, 0.5)
    }
    func testMissingFileStopsQueueAndKeepsSamePlayerInstance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appendingPathComponent("removed.mp4"); try Data([0]).write(to: media)
        let library = LibraryStore(file: root.appendingPathComponent("library.json"))
        let id = try library.addFile(media); try FileManager.default.removeItem(at: media)
        let player = NativePlayer(); player.library = library; let original = player.player
        player.playPlaylist([id]); defer { player.close() }
        for _ in 0..<100 { if player.error != nil { break }; try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertNotNil(player.error); XCTAssertFalse(player.playing); XCTAssertEqual(player.mediaID, id)
        XCTAssertTrue(player.player === original); XCTAssertEqual(player.queueIDs, [id]); XCTAssertFalse(player.canNext)
    }
    func testOwnNativeVideoClockContinuesAcrossMiniplayerAndExplicitPauseResume() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let clip = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "audible", withExtension: "mp4"))
        let library = LibraryStore(file: root.appendingPathComponent("library.json"))
        let id = try library.addFile(clip), playback = NativePlayer(); playback.library = library
        let original = playback.player; playback.open(id)
        defer { playback.close(); try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        for _ in 0..<200 { if playback.time > 1 && playback.playing { break }; try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(playback.playing); XCTAssertGreaterThan(playback.time, 1); XCTAssertGreaterThan(playback.duration ?? 0, 59)
        let before = playback.time; playback.expanded = false
        try await Task.sleep(for: .seconds(2))
        XCTAssertTrue(playback.player === original); XCTAssertGreaterThan(playback.time, before + 0.5)
        playback.pause(); let stopped = playback.player.currentTime().seconds
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(playback.player.currentTime().seconds, stopped, accuracy: 0.1)
        playback.play()
        for _ in 0..<80 { if playback.time > stopped + 0.5 { break }; try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertGreaterThan(playback.time, stopped + 0.5); XCTAssertTrue(playback.player === original)
        // This is AVPlayer clock playback, NOT an actual app background/AirPlay/device test.
    }
    func testExplicitPauseInvalidatesInterruptionResumeButSystemPauseDoesNot() {
        let playback = NativePlayer(), revision = 0
        playback.pause(userInitiated: false); XCTAssertEqual(playback.commandRevision, revision)
        playback.pause(); XCTAssertGreaterThan(playback.commandRevision, revision)
        playback.close()
    }
    func testBackgroundPolicyAndMediaServiceResetRetireOldPlayer() {
        let playback = NativePlayer()
        XCTAssertEqual(playback.player.audiovisualBackgroundPlaybackPolicy, .continuesIfPossible)
        let first = playback.player
        playback.handleMediaServicesReset()
        XCTAssertFalse(playback.player === first); XCTAssertFalse(playback.playing)
        XCTAssertEqual(playback.player.audiovisualBackgroundPlaybackPolicy, .continuesIfPossible)
        playback.close()
    }
    func testNativeQueueDeduplicatesAndRejectsWebsiteItems() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let library = LibraryStore(file: url)
        let website = try XCTUnwrap(library.addLink(title: "Web", address: "https://example.org/"))
        let direct = try XCTUnwrap(library.addLink(title: "Own", address: "https://example.org/own.mp4", kind: .authorizedDirect))
        let player = NativePlayer(); player.library = library
        player.enqueue(website); player.enqueue(direct); player.enqueue(direct)
        XCTAssertEqual(player.queueIDs, [direct]); player.removeFromQueue(direct); XCTAssertTrue(player.queueIDs.isEmpty)
        player.close()
    }
}

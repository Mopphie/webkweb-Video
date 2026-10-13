import XCTest
@testable import WebKWeb

final class QueueTests: XCTestCase {
    private func entries(_ count: Int) -> [QueueEntry] { (0..<count).map { QueueEntry(title: "Title \($0)", address: "https://example.com/\($0)") } }
    func testShuffleVisitsWholePermutationBeforeCycleRepeats() throws {
        var queue = PlaybackQueue(); let items = entries(40)
        queue.replace(items); queue.setShuffle(true); queue.repeatMode = .all
        var visited: [UUID] = []
        for _ in items { visited.append(try XCTUnwrap(queue.next(automatic: true)).id) }
        XCTAssertEqual(Set(visited), Set(items.map(\.id)))
        XCTAssertEqual(visited.count, Set(visited).count)
        let next = try XCTUnwrap(queue.next(automatic: true))
        XCTAssertNotEqual(next.id, visited.last)
        XCTAssertEqual(Set(queue.order), Set(items.map(\.id)))
    }
    func testRepeatOneRepeatsAutomaticallyButManualNextAdvances() throws {
        var queue = PlaybackQueue(); let items = entries(3); queue.replace(items); queue.repeatMode = .one
        XCTAssertEqual(queue.next()?.id, items[0].id)
        XCTAssertEqual(queue.next(automatic: true)?.id, items[0].id)
        XCTAssertEqual(queue.next()?.id, items[1].id)
        XCTAssertEqual(queue.previous()?.id, items[0].id)
    }
    func testTurningShuffleOffRestoresOriginalFollowingEntry() {
        var queue = PlaybackQueue(); let items = entries(5); queue.replace(items)
        _ = queue.select(items[2].id); queue.setShuffle(true); queue.setShuffle(false)
        XCTAssertEqual(queue.next()?.id, items[3].id)
    }
    func testRemoveAndReorderKeepStableIdentityAndHistory() {
        var queue = PlaybackQueue(); let items = entries(5); queue.replace(items)
        _ = queue.select(items[1].id); _ = queue.next(); queue.remove(items[0].id)
        queue.move(from: IndexSet(integer: 0), to: 4)
        XCTAssertEqual(queue.currentID, items[2].id)
        XCTAssertEqual(queue.previous()?.id, items[1].id)
        XCTAssertEqual(Set(queue.order), Set(queue.entries.map(\.id)))
    }
    func testQueuePersistenceRejectsCredentialsAndDuplicateIDs() throws {
        var queue = PlaybackQueue(); let valid = entries(1)[0]
        queue.append(valid); queue.append(valid); queue.append(QueueEntry(title: "Secret", address: "https://alice:secret@example.com"))
        var restored = try JSONDecoder().decode(PlaybackQueue.self, from: JSONEncoder().encode(queue)); restored.validate()
        XCTAssertEqual(restored.entries.count, 1); XCTAssertEqual(restored.order, [valid.id])
    }
    func testRepeatNoneStopsAndSingleEntryRepeatAllWorks() {
        var queue = PlaybackQueue(); let item = entries(1)[0]; queue.append(item)
        XCTAssertEqual(queue.next()?.id, item.id); XCTAssertNil(queue.next(automatic: true))
        queue.repeatMode = .all; XCTAssertEqual(queue.next(automatic: true)?.id, item.id)
    }
}

@MainActor
final class DownloadValidationTests: XCTestCase {
    func testDownloadsRejectLoginHTMLAndStreamingManifests() throws {
        let mp4 = try XCTUnwrap(DirectMedia(source: "https://example.com/video.mp4", contentType: "video/mp4", encrypted: false))
        XCTAssertTrue(DownloadStore.supports(mp4))
        XCTAssertTrue(DownloadStore.validResponse("video/mp4", expected: mp4))
        XCTAssertTrue(DownloadStore.validResponse("application/octet-stream", expected: mp4))
        XCTAssertFalse(DownloadStore.validResponse("text/html", expected: mp4))
        XCTAssertFalse(DownloadStore.validResponse("application/vnd.apple.mpegurl", expected: mp4))
        let hls = try XCTUnwrap(DirectMedia(source: "https://example.com/master.m3u8", contentType: "application/vnd.apple.mpegurl", encrypted: false))
        XCTAssertFalse(DownloadStore.supports(hls))
        let http = try XCTUnwrap(DirectMedia(source: "http://example.com/video.mp4", contentType: "video/mp4", encrypted: false))
        XCTAssertFalse(DownloadStore.supports(http)) // Native ATS remains enforced.
    }
    func testFilenameCannotEscapeDownloadDirectory() {
        let name = DownloadStore.filename(title: "../../secret/Hello:Film", type: "video/mp4", source: URL(string: "https://example.com/path")!)
        XCTAssertFalse(name.contains("/")); XCTAssertFalse(name.contains("..")); XCTAssertTrue(name.hasSuffix(".mp4"))
    }
}

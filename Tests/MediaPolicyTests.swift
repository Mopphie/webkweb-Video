import XCTest
@testable import WebKWeb

final class MediaPolicyTests: XCTestCase {
    func testIdleLaunchAndForegroundDoNotClaimLocalAudio() {
        XCTAssertFalse(MediaPolicy.requiresAudioSession(localPlaying: false, stopped: false))
        XCTAssertTrue(MediaPolicy.requiresAudioSession(localPlaying: false, explicitPlay: true, stopped: false))
        XCTAssertFalse(MediaPolicy.requiresAudioSession(localPlaying: true, stopped: true))
    }
    func testExistingAudioWaitsForActualPauseAcknowledgement() {
        XCTAssertTrue(MediaPolicy.requiresAudioSession(localPlaying: true, stopped: true, alreadyActive: true))
        XCTAssertFalse(MediaPolicy.requiresAudioSession(localPlaying: false, stopped: true, alreadyActive: true))
    }
    func testNowPlayingRateReflectsSpeedAndPause() {
        XCTAssertEqual(MediaPolicy.nowPlayingRate(playing: true, rate: 1.5), 1.5)
        XCTAssertEqual(MediaPolicy.nowPlayingRate(playing: true, rate: 2), 2)
        XCTAssertEqual(MediaPolicy.nowPlayingRate(playing: false, rate: 2), 0)
        XCTAssertEqual(MediaPolicy.nowPlayingRate(playing: true, rate: .nan), 1)
    }
    func testBackgroundOwnerSurvivesEmptyTabWithoutOverridingSelectedPlayer() {
        let current = UUID(), background = UUID(), queue = UUID()
        let playing = PlaybackCandidate(id: background, hasMedia: true, playing: true)
        let pausedQueue = PlaybackCandidate(id: queue, hasMedia: true, playing: false)
        XCTAssertEqual(MediaPolicy.playbackOwner(currentID: current, queueID: queue, candidates: [playing, pausedQueue]), background)
        let selected = PlaybackCandidate(id: current, hasMedia: true, playing: false)
        XCTAssertEqual(MediaPolicy.playbackOwner(currentID: current, queueID: queue, candidates: [playing, selected]), current)
        XCTAssertEqual(MediaPolicy.playbackOwner(currentID: current, queueID: queue, candidates: [pausedQueue]), queue)
    }
    func testFavoritePersistenceAndDeepLinkRemoveCredentialInformation() throws {
        let raw = "https://alice:secret@example.com/video?v=1#comments"
        XCTAssertEqual(StoredAddress.clean(raw), "https://example.com/video?v=1#comments")
        XCTAssertNil(StoredAddress.clean("javascript:alert(1)"))
        let favorite = FavoriteSnapshot(id: "id", title: "Favorite", address: raw)
        let deepLink = try XCTUnwrap(favorite.deepLink)
        XCTAssertEqual(AddressResolver.deepLink(deepLink), "https://example.com/video?v=1#comments")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: FavoriteStorage.groupID)), key = FavoriteStorage.key
        let old = defaults.data(forKey: key); defer { defaults.set(old, forKey: key) }
        FavoriteStorage.write([favorite]); let encoded = try XCTUnwrap(defaults.data(forKey: key))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("secret"))
        XCTAssertEqual(FavoriteStorage.read().first?.address, "https://example.com/video?v=1#comments")
    }
}

import XCTest
#if canImport(WebKWeb)
@testable import WebKWeb
#else
@testable import DevnTubeCore
#endif

final class MediaPolicyTests: XCTestCase {
    func testDelayedTrustedInputCannotOverrideNewerNativeStop() {
        XCTAssertTrue(MediaPolicy.acceptsPlaybackInput(2000, after: 1000, now: 9000))
        XCTAssertFalse(MediaPolicy.acceptsPlaybackInput(2000, after: 5000, now: 9000))
        for input in [nil, .nan, .infinity, -1, 11001, -30001] as [Double?] {
            XCTAssertFalse(MediaPolicy.acceptsPlaybackInput(input, after: 0, now: 10000))
        }
    }
    func testIdleLaunchAndForegroundDoNotClaimLocalAudio() {
        XCTAssertFalse(MediaPolicy.requiresAudioSession(localPlaying: false, stopped: false))
        XCTAssertTrue(MediaPolicy.requiresAudioSession(localPlaying: false, explicitPlay: true, stopped: false))
        XCTAssertFalse(MediaPolicy.requiresAudioSession(localPlaying: true, stopped: true))
    }
    func testExistingAudioWaitsForActualPauseAcknowledgement() {
        XCTAssertTrue(MediaPolicy.requiresAudioSession(localPlaying: true, stopped: true, alreadyActive: true))
        XCTAssertFalse(MediaPolicy.requiresAudioSession(localPlaying: false, stopped: true, alreadyActive: true))
        XCTAssertTrue(MediaPolicy.requiresAudioSession(localPlaying: false, waiting: true, stopped: false, alreadyActive: true))
        XCTAssertFalse(MediaPolicy.requiresAudioSession(localPlaying: false, waiting: true, stopped: true))
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
    func testFavoritePersistenceAndDeepLinksRejectCredentialInformation() throws {
        let raw = "https://alice:secret@example.com/video?v=1#comments"
        XCTAssertNil(StoredAddress.clean(raw))
        XCTAssertNil(FavoriteSnapshot(id: "id", title: "Favorite", address: raw).deepLink)
        XCTAssertNil(StoredAddress.clean("javascript:alert(1)"))
        let favorite = FavoriteSnapshot(id: "id", title: "Favorite", address: "https://example.com/video?v=1#comments")
        let deepLink = try XCTUnwrap(favorite.deepLink)
        XCTAssertEqual(AddressResolver.deepLink(deepLink), favorite.address)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: FavoriteStorage.groupID)), key = FavoriteStorage.key
        let old = defaults.data(forKey: key), oldConsent = defaults.object(forKey: FavoriteStorage.consentKey); defer { defaults.set(old, forKey: key); defaults.set(oldConsent, forKey: FavoriteStorage.consentKey) }
        FavoriteStorage.write([FavoriteSnapshot(id: "bad", title: "Bad", address: raw), favorite], consent: true)
        let encoded = try XCTUnwrap(defaults.data(forKey: key))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("secret"))
        XCTAssertEqual(FavoriteStorage.read().map(\.address), [favorite.address])
        defaults.set(false, forKey: FavoriteStorage.consentKey)
        XCTAssertTrue(FavoriteStorage.read().isEmpty, "Widget/Intent must not trust old auto-exported snapshots before the app's next launch")
    }
}

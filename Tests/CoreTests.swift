import XCTest
#if canImport(WebKWeb)
@testable import WebKWeb
#else
@testable import DevnTubeCore
#endif

final class CoreTests: XCTestCase {
    func testURLAndSearchResolution() {
        XCTAssertNil(AddressResolver.resolve("  \n"))
        XCTAssertEqual(AddressResolver.resolve("youtube.com/watch?v=abcdefghijk")?.host, "youtube.com")
        XCTAssertEqual(AddressResolver.resolve("http://localhost:8080/video")?.scheme, "http")
        let query = "cats & dogs / #videos 😀"
        let result = AddressResolver.resolve(query)!
        XCTAssertEqual(result.host, "www.google.com")
        XCTAssertEqual(URLComponents(url: result, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, query)
        XCTAssertEqual(AddressResolver.resolve("javascript:alert(1)")?.host, "www.google.com")
        XCTAssertNil(AddressResolver.resolve("https://user:secret@example.com"))
        XCTAssertEqual(AddressResolver.resolve("http://intranet/video")?.host, "intranet")
        XCTAssertEqual(AddressResolver.resolve("cats", engine: .duckDuckGo)?.host, "duckduckgo.com")
    }

    func testWidgetDeepLinkRoundTrip() {
        let favorite = FavoriteSnapshot(id: "favorite", title: "Video", address: "https://example.com/watch?a=1&b=two#part")
        XCTAssertEqual(AddressResolver.deepLink(favorite.deepLink!), favorite.address)
        XCTAssertNil(AddressResolver.deepLink(URL(string: "devntube://open?url=javascript%3Aalert(1)")!))
        XCTAssertNil(AddressResolver.deepLink(URL(string: "other://open?url=https%3A%2F%2Fexample.com")!))
    }

    func testYouTubeIDValidationAndSpoofedHosts() {
        XCTAssertEqual(YouTubeAddress.videoID(in: URL(string: "https://m.youtube.com/watch?v=abcdefghijk")), "abcdefghijk")
        XCTAssertEqual(YouTubeAddress.videoID(in: URL(string: "https://www.youtube.com/shorts/abcdefghijk")), "abcdefghijk")
        XCTAssertNil(YouTubeAddress.videoID(in: URL(string: "https://youtube.com.evil.example/watch?v=abcdefghijk")))
        XCTAssertNil(YouTubeAddress.videoID(in: URL(string: "https://youtube.com/watch?v=too-short")))
        XCTAssertNil(YouTubeAddress.videoID(in: URL(string: "https://youtube.com/results?v=abcdefghijk")))
    }
    func testWatchPresentationRouteBoundaries() {
        for address in ["https://m.youtube.com/watch?v=abcdefghijk", "https://www.youtube.com/watch?t=10&v=abcde%66ghijk#comments", "http://youtube.com/watch?v=12345678901"] {
            XCTAssertTrue(YouTubeAddress.isWatchPage(URL(string: address)), address)
        }
        for address in ["https://youtube.com.evil.example/watch?v=abcdefghijk", "https://notyoutube.com/watch?v=abcdefghijk", "https://user:password@youtube.com/watch?v=abcdefghijk", "ftp://youtube.com/watch?v=abcdefghijk", "https://youtube.com/watch?v=short", "https://youtube.com/results?v=abcdefghijk", "https://youtube.com/shorts/abcdefghijk", "https://youtube.com/embed/abcdefghijk"] {
            XCTAssertFalse(YouTubeAddress.isWatchPage(URL(string: address)), address)
        }
        XCTAssertFalse(YouTubeAddress.isWatchPage(nil))
    }
    func testWatchExitPersistsForSameVideoAndAllowsDifferentWatchItem() {
        let first = URL(string: "https://m.youtube.com/watch?v=abcdefghijk")!
        var state = WatchPresentationState()
        XCTAssertTrue(state.isImmersive(at: first))
        state.dismiss(at: first)
        XCTAssertFalse(state.isImmersive(at: first))
        XCTAssertFalse(state.isImmersive(at: URL(string: "https://www.youtube.com/watch?t=20&v=abcdefghijk#comments")))
        XCTAssertFalse(state.isImmersive(at: URL(string: "https://m.youtube.com/")))
        XCTAssertTrue(state.isImmersive(at: URL(string: "https://m.youtube.com/watch?v=12345678901")))
        state.show(); XCTAssertTrue(state.isImmersive(at: first))
    }
    func testWatchExitUsesYouTubeHistoryOrSafeHomeFallback() {
        let previous = URL(string: "https://m.youtube.com/results?search_query=music")!
        XCTAssertEqual(WatchPresentationState.exitURL(previous: previous), previous)
        for value in [nil, "https://youtube.com.evil.example/watch?v=abcdefghijk", "https://example.com/", "https://user:secret@youtube.com/", "javascript:alert(1)"] as [String?] {
            XCTAssertEqual(WatchPresentationState.exitURL(previous: value.flatMap { URL(string: $0) }).absoluteString, "https://m.youtube.com/")
        }
    }

    func testPreferencesRoundTripAndCloudDefaults() throws {
        var options = BrowserPreferences()
        options.gestures = true; options.history = false; options.searchEngine = .bing
        options.blockedSites = ["example.com"]
        XCTAssertEqual(try JSONDecoder().decode(BrowserPreferences.self, from: JSONEncoder().encode(options)), options)
        XCTAssertFalse(BrowserPreferences().shareFavoritesWithSystem)
    }

    func testUpgradeIgnoresRetiredIntegrationFlagsAndSources() throws {
        let data = Data(#"{"blocking":true,"sources":[{"title":"old","address":"https://example.com/rules","enabled":true}],"cloudSync":true,"hideShorts":true,"autoPiP":true}"#.utf8)
        let restored = try JSONDecoder().decode(BrowserPreferences.self, from: data)
        let text = String(decoding: try JSONEncoder().encode(restored), as: UTF8.self)
        for retired in ["blocking", "sources", "cloudSync", "hideShorts", "autoPiP"] { XCTAssertFalse(text.contains(retired)) }
        XCTAssertFalse(restored.shareFavoritesWithSystem)
    }

    func testCurrentVideoSleepRejectsOtherMediaAndPersistsDeadline() throws {
        let tab = UUID(); var plan = SleepPlan()
        plan.arm(videos: 1, tabID: tab, mediaID: "primary")
        XCTAssertFalse(plan.ended(in: tab, eventID: "a", mediaID: "incidental"))
        XCTAssertTrue(plan.ended(in: tab, eventID: "b", mediaID: "primary"))
        plan.arm(seconds: 91, now: Date(timeIntervalSince1970: 1000))
        let restored = try JSONDecoder().decode(SleepPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(restored.deadline, plan.deadline)
        XCTAssertTrue(restored.hasExpired(at: Date(timeIntervalSince1970: 1091)))
    }

    func testSleepCountsOnlyDistinctEventsFromArmedTab() {
        let armed = UUID(), other = UUID()
        var plan = SleepPlan()
        plan.arm(videos: 2, tabID: armed)
        XCTAssertFalse(plan.ended(in: other, eventID: "a"))
        XCTAssertEqual(plan.remainingVideos, 2)
        XCTAssertFalse(plan.ended(in: armed, eventID: "a"))
        XCTAssertEqual(plan.remainingVideos, 1)
        XCTAssertFalse(plan.ended(in: armed, eventID: "a"))
        XCTAssertTrue(plan.ended(in: armed, eventID: "b"))
        plan.cancel()
        XCTAssertFalse(plan.isActive)
    }

    func testSleepUsesAbsoluteDeadlineAcrossSuspension() {
        let now = Date(timeIntervalSince1970: 1000)
        var plan = SleepPlan()
        plan.arm(minutes: 30, now: now)
        XCTAssertFalse(plan.hasExpired(at: now.addingTimeInterval(1799)))
        XCTAssertTrue(plan.hasExpired(at: now.addingTimeInterval(1800)))
        XCTAssertTrue(plan.hasExpired(at: now.addingTimeInterval(10_000)))
        plan.arm(minutes: -1, now: now)
        XCTAssertFalse(plan.isActive)
    }
}

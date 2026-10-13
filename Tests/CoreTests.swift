import XCTest
@testable import WebKWeb

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
        XCTAssertEqual(AddressResolver.resolve("https://user:secret@example.com")?.host, "www.google.com")
    }

    func testWidgetDeepLinkRoundTrip() {
        let favorite = FavoriteSnapshot(id: "favorite", title: "Video", address: "https://example.com/watch?a=1&b=two#part")
        XCTAssertEqual(AddressResolver.deepLink(favorite.deepLink!), favorite.address)
        XCTAssertNil(AddressResolver.deepLink(URL(string: "webkweb://open?url=javascript%3Aalert(1)")!))
        XCTAssertNil(AddressResolver.deepLink(URL(string: "other://open?url=https%3A%2F%2Fexample.com")!))
    }

    func testYouTubeIDValidationAndSpoofedHosts() {
        XCTAssertEqual(YouTubeAddress.videoID(in: URL(string: "https://m.youtube.com/watch?v=abcdefghijk")), "abcdefghijk")
        XCTAssertEqual(YouTubeAddress.videoID(in: URL(string: "https://www.youtube.com/shorts/abcdefghijk")), "abcdefghijk")
        XCTAssertNil(YouTubeAddress.videoID(in: URL(string: "https://youtube.com.evil.example/watch?v=abcdefghijk")))
        XCTAssertNil(YouTubeAddress.videoID(in: URL(string: "https://youtube.com/watch?v=too-short")))
        XCTAssertNil(YouTubeAddress.videoID(in: URL(string: "https://youtube.com/results?v=abcdefghijk")))
    }

    func testCastAcceptsOnlyDirectNonDRMNetworkMedia() {
        XCTAssertNotNil(DirectMedia(source: "https://cdn.example.com/video.mp4", contentType: nil, encrypted: false))
        XCTAssertNotNil(DirectMedia(source: "https://cdn.example.com/stream?id=1", contentType: "application/vnd.apple.mpegurl", encrypted: false))
        XCTAssertNil(DirectMedia(source: "blob:https://youtube.com/id", contentType: "video/mp4", encrypted: false))
        XCTAssertNil(DirectMedia(source: "https://cdn.example.com/video.mp4", contentType: nil, encrypted: true))
        XCTAssertNil(DirectMedia(source: "https://youtube.com/watch?v=abcdefghijk", contentType: nil, encrypted: false))
        XCTAssertNil(DirectMedia(source: "https://user:secret@example.com/video.mp4", contentType: nil, encrypted: false))
    }

    func testDomainConverterPreservesExceptionScopeConservatively() throws {
        let text = """
        ! test source
        ||ads.example.com^
        ||TRACKER.example.org^
        ||ads.example.com^
        @@||allowed.ads.example.com^$script
        ||script.example.net^$script
        example.com##.advert
        /unsupported-regex/
        ||-invalid.example^
        """
        let converted = try DomainFilterConverter.convert(text)
        XCTAssertEqual(converted.domainCount, 2)
        XCTAssertEqual(converted.skippedCount, 4)
        XCTAssertTrue(converted.json.contains("ads\\\\.example"))
        XCTAssertTrue(converted.json.contains("tracker"))
        XCTAssertTrue(converted.json.contains("pagead"))
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(converted.json.utf8)) as? [[String: Any]])
        XCTAssertEqual(rules.count, 5)
        let allow = try XCTUnwrap(rules.last?["action"] as? [String: String])
        XCTAssertEqual(allow["type"], "ignore-previous-rules")
        let tracker = try XCTUnwrap(rules.first { rule in
            (rule["trigger"] as? [String: String])?["url-filter"]?.contains("tracker") == true
        })
        let trigger = try XCTUnwrap(tracker["trigger"] as? [String: String])
        let regex = try NSRegularExpression(pattern: XCTUnwrap(trigger["url-filter"]))
        let matches: (String) -> Bool = { url in regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil }
        XCTAssertTrue(matches("https://sub.tracker.example.org/path"))
        XCTAssertTrue(matches("https://tracker.example.org:443/path"))
        XCTAssertFalse(matches("https://tracker.example.org.evil.test/path"))
        XCTAssertFalse(matches("https://nottracker.example.org/path"))
    }

    func testUnsupportedExceptionRejectsWholeSource() {
        XCTAssertThrowsError(try DomainFilterConverter.convert("||ads.example.com^\n@@/(unsupported(?=x))/"))
        XCTAssertThrowsError(try DomainFilterConverter.convert("example.com##.cosmetic"))
    }

    func testDNSWhitelistAnchorsWildcardsAndSimpleRegexArePreserved() throws {
        let result = try DomainFilterConverter.convert("""
        ||ads.example.com^
        @@||allowed.example.com^|
        @@|cdn.example.org^|
        @@||cdn.us*.example.net^|
        @@-ds.metric.example.io^|
        @@/\\.(gif|jpe?g|png|webp)#(\\/?.+)?(\\/(ad)s?\\/|\\/ad-)/
        """)
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.json.utf8)) as? [[String: Any]])
        XCTAssertEqual(rules.filter { ($0["action"] as? [String: String])?["type"] == "ignore-previous-rules" }.count, 8)
    }

    func testSponsorSegmentRejectsBadBoundsAndCategories() {
        XCTAssertTrue(SponsorSegment(segment: [2, 5], category: "intro").isValid)
        XCTAssertFalse(SponsorSegment(segment: [5, 2], category: "sponsor").isValid)
        XCTAssertFalse(SponsorSegment(segment: [-1, 2], category: "outro").isValid)
        XCTAssertFalse(SponsorSegment(segment: [0, .infinity], category: "selfpromo").isValid)
        XCTAssertFalse(SponsorSegment(segment: [0, 2], category: "music_offtopic").isValid)
        XCTAssertFalse(SponsorSegment(segment: [], category: "intro").isValid)
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

@MainActor
final class RuleStoreTests: XCTestCase {
    func testDisableThenEnableDuringCompilationInstallsList() async {
        let tab = BrowserTab()
        let store = RuleStore.shared
        await store.apply(to: tab.webView, tabID: tab.id, enabled: false)
        // Regression: the old implementation retained applied=false forever.
        await store.apply(to: tab.webView, tabID: tab.id, enabled: true)
        let list = await store.prepare()
        XCTAssertNotNil(list)
        XCTAssertTrue(store.hasAppliedRules(to: tab.id))
        await store.apply(to: tab.webView, tabID: tab.id, enabled: false)
        XCTAssertFalse(store.hasAppliedRules(to: tab.id))
        tab.close()
    }
}

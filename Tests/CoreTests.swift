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
        XCTAssertEqual(converted.domainCount, 6)
        XCTAssertEqual(converted.skippedCount, 3)
        XCTAssertTrue(converted.json.contains("ads\\\\.example"))
        XCTAssertTrue(converted.json.contains("tracker"))
        XCTAssertFalse(converted.json.contains("pagead"))
        XCTAssertFalse(converted.json.contains("youtube"))
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(converted.json.utf8)) as? [[String: Any]])
        XCTAssertEqual(rules.count, 7)
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
        XCTAssertEqual(rules.filter { ($0["action"] as? [String: String])?["type"] == "ignore-previous-rules" }.count, 12)
    }

    func testExceptionCannotBypassHostBlockThroughQueryString() throws {
        let report = try DomainFilterConverter.convert("||ads.example.com^\n@@||allowed.example.org^")
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(report.json.utf8)) as? [[String: Any]])
        let exception = try XCTUnwrap(rules.last?["trigger"] as? [String: Any])
        let regex = try NSRegularExpression(pattern: XCTUnwrap(exception["url-filter"] as? String))
        let url = "https://ads.example.com/ad?next=https://allowed.example.org"
        XCTAssertNil(regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)))
        let allowed = "https://sub.allowed.example.org/script.js"
        XCTAssertNotNil(regex.firstMatch(in: allowed, range: NSRange(allowed.startIndex..., in: allowed)))
        let credentialSpoof = "https://allowed.example.org:password@ads.example.com/ad"
        XCTAssertNil(regex.firstMatch(in: credentialSpoof, range: NSRange(credentialSpoof.startIndex..., in: credentialSpoof)))
    }

    func testLargeListKeepsEveryDomainAndRepeatsExceptionsAcrossChunks() throws {
        let domains = (0...40_000).map { "||a\($0).example^" }.joined(separator: "\n")
        let report = try DomainFilterConverter.convert(domains + "\n@@||allowed.example.org^")
        XCTAssertEqual(report.domainCount, 40_004)
        XCTAssertEqual(report.jsons.count, 2)
        XCTAssertTrue(report.jsons.joined().contains("doubleclick"))
        XCTAssertTrue(report.jsons.joined().contains("googlesyndication"))
        XCTAssertTrue(report.jsons.joined().contains("googleadservices"))
        for json in report.jsons {
            let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
            XCTAssertLessThan(rules.count, 50_000)
            XCTAssertEqual((rules.last?["action"] as? [String: String])?["type"], "ignore-previous-rules")
        }
    }

    func testHostsListAndScopedNetworkRules() throws {
        let report = try DomainFilterConverter.convert("0.0.0.0 ads.example.com\n127.0.0.1 localhost\n@@||allowed.example.org^$script,third-party,domain=example.net")
        XCTAssertEqual(report.domainCount, 4)
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(report.json.utf8)) as? [[String: Any]])
        let trigger = try XCTUnwrap(rules.last?["trigger"] as? [String: Any])
        XCTAssertEqual(trigger["resource-type"] as? [String], ["script"])
        XCTAssertEqual(trigger["load-type"] as? [String], ["third-party"])
        XCTAssertEqual(trigger["if-domain"] as? [String], ["example.net", "*.example.net"])
        XCTAssertThrowsError(try DomainFilterConverter.convert("@@||allowed.example.org^$domain=example.net:443"))
    }

    func testPreferencesRoundTripAndCloudDefaults() throws {
        var options = BrowserPreferences()
        options.gestures = true; options.history = false; options.searchEngine = .bing
        options.allowlist = ["example.com"]
        XCTAssertEqual(try JSONDecoder().decode(BrowserPreferences.self, from: JSONEncoder().encode(options)), options)
        XCTAssertFalse(BrowserPreferences().cloudSync)
    }

    func testUpgradeRemovesSuppliedMixedLicenseSourceButKeepsUserSources() throws {
        var options = BrowserPreferences()
        let old = FilterSource(title: "Old preset", address: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts")
        let custom = FilterSource(title: "Own list", address: "https://example.com/owned-rules.txt")
        let local = FilterSource(title: "Local import", address: old.address, localFile: "owned.txt")
        options.sources = [old, custom, local]
        let restored = try JSONDecoder().decode(BrowserPreferences.self, from: JSONEncoder().encode(options))
        XCTAssertEqual(restored.sources.map(\.id), [custom.id, local.id])
        XCTAssertEqual(restored.sources.last?.localFile, "owned.txt")
        XCTAssertFalse(FilterSource.defaults.contains { $0.address.lowercased().contains("stevenblack") })
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

import XCTest
#if canImport(WebKWeb)
@testable import WebKWeb
#else
@testable import DevnTubeCore
#endif

final class LibraryAndPolicyTests: XCTestCase {
    func testPersistenceRejectsCredentialAndSignedURLsButKeepsOrdinaryBookmarks() {
        for address in ["javascript:alert(1)", "file:///private/a.mov", "https://alice:secret@example.org/", "https://example.org/movie.mp4?token=secret", "https://example.org/?X-Amz-Signature=x", "https://example.org/?sessionid=x", "https://example.org/?code=OAuthCode", "https://example.org/#access_token=private", "https://example.org/#section?password=private"] {
            XCTAssertNil(LibraryAddress.clean(address), address)
        }
        XCTAssertEqual(LibraryAddress.clean("https://m.youtube.com/watch?v=abcdefghijk&t=30"), "https://m.youtube.com/watch?v=abcdefghijk&t=30")
    }
    func testCapabilityPolicyDoesNotGrantWebsitePremiumOrAutoQueueFunctions() {
        let website = SourceCapabilities.forSource(.website)
        XCTAssertFalse(SourceCapabilities.allowsBridgeControls(mainHost: "example.org", frameHost: "www.youtube-nocookie.com"))
        XCTAssertFalse(SourceCapabilities.allowsBridgeControls(mainHost: "YouTube.Com.", frameHost: "example.org"))
        XCTAssertFalse(SourceCapabilities.allowsBridgeControls(mainHost: "example.org", frameHost: "WWW.YOUTUBE-NOCOOKIE.COM."))
        XCTAssertFalse(SourceCapabilities.allowsBridgeControls(mainHost: "m.youtube.com", frameHost: "example.org"))
        XCTAssertTrue(SourceCapabilities.allowsBridgeControls(mainHost: "example.org", frameHost: "media.example.org"))
        XCTAssertFalse(website.nativePlayback); XCTAssertFalse(website.backgroundAudio); XCTAssertFalse(website.systemPiP); XCTAssertFalse(website.automaticAdvance); XCTAssertFalse(website.progress)
        XCTAssertTrue(SourceCapabilities.forSource(.localFile).backgroundAudio)
        XCTAssertTrue(SourceCapabilities.forSource(.authorizedDirect).systemPiP)
        XCTAssertNil(SourceCapabilities.directMediaURL("https://rr1.googlevideo.com/video.mp4"))
        XCTAssertNil(SourceCapabilities.directMediaURL("https://m.youtube.com/video.mp4"))
        XCTAssertNil(SourceCapabilities.directMediaURL("http://example.org/video.mp4"))
        XCTAssertNotNil(SourceCapabilities.directMediaURL("https://media.example.org/owned.mp4"))
        XCTAssertEqual(SourceCapabilities.directMediaURL("HTTPS://MEDIA.EXAMPLE.ORG/owned.mp4")?.host, "media.example.org")
    }
    func testNavigationRestrictionsCannotFilterEmbeddedPlatformsOrPrivateResources() {
        let sites = ["example.org"]
        XCTAssertTrue(SiteNavigationPolicy.blocks(URL(string: "https://sub.example.org/")!, mainFrame: true, privateMode: false, sites: sites))
        XCTAssertFalse(SiteNavigationPolicy.blocks(URL(string: "https://example.org/")!, mainFrame: false, privateMode: false, sites: sites))
        XCTAssertFalse(SiteNavigationPolicy.blocks(URL(string: "https://example.org/")!, mainFrame: true, privateMode: true, sites: sites))
        for domain in SourceCapabilities.platformDomains {
            XCTAssertFalse(SiteNavigationPolicy.validBlockedHost(domain))
            XCTAssertFalse(SiteNavigationPolicy.blocks(URL(string: "https://" + domain + "/embed/x")!, mainFrame: true, privateMode: false, sites: [domain]))
        }
        for domain in ["com", "com.", "youtube.com.", "*.example.org", "example.org/path", "example.org:443", "user@example.org"] { XCTAssertFalse(SiteNavigationPolicy.validBlockedHost(domain)) }
        XCTAssertFalse(SiteNavigationPolicy.blocks(URL(string: "https://example.org.evil.test/")!, mainFrame: true, privateMode: false, sites: sites))
    }
    func testLibraryValidationRejectsUnknownVersionDuplicateIDsAndInvalidProgress() throws {
        let media = LibraryMedia(title: "Mine", kind: .authorizedDirect, address: "https://example.org/movie.mp4")
        var value = LibraryDocument(); value.media = [media]; XCTAssertNoThrow(try value.validated())
        value.version = 2; XCTAssertThrowsError(try value.validated()); value.version = 1
        value.media.append(media); XCTAssertThrowsError(try value.validated()); value.media = [media]
        value.media[0].position = .infinity; XCTAssertThrowsError(try value.validated())
    }
    func testPlaylistMergeRemapsDuplicateLinksAndPreservesExistingUserWork() throws {
        let local = LibraryMedia(title: "My title", kind: .website, address: "https://example.org/video")
        let imported = LibraryMedia(title: "Other title", kind: .website, address: local.address)
        var value = LibraryDocument(); value.media = [local]
        var incoming = LibraryDocument(); incoming.media = [imported]
        incoming.playlists = [NamedPlaylist(name: "Imported", mediaIDs: [imported.id, imported.id, UUID()])]
        incoming.notes = [MediaNote(mediaID: imported.id, seconds: nil, text: "My own note")]
        try value.merge(incoming)
        XCTAssertEqual(value.media, [local]); XCTAssertEqual(value.playlists.first?.mediaIDs, [local.id]); XCTAssertEqual(value.notes.first?.mediaID, local.id)
        try value.merge(incoming); XCTAssertEqual(value.playlists.count, 1); XCTAssertEqual(value.notes.count, 1)
    }
    func testImportRejectsEmbeddedFilePermissionsAndOrphanNotes() {
        var value = LibraryDocument(); let file = LibraryMedia(title: "File", kind: .localFile, fileBookmark: Data([1, 2]))
        value.media = [file]; XCTAssertThrowsError(try value.validated(importing: true))
        value.media[0].fileBookmark = nil; value.notes = [MediaNote(mediaID: UUID(), text: "Orphan")]; XCTAssertThrowsError(try value.validated())
    }
    func testSleepRejectsOverflowAndDistinctEndsOnly() {
        var plan = SleepPlan(); plan.arm(minutes: Int.max); XCTAssertFalse(plan.isActive)
        let session = UUID(); plan.arm(videos: 2, tabID: session)
        XCTAssertFalse(plan.ended(in: session, eventID: "first", mediaID: "a"))
        XCTAssertFalse(plan.ended(in: session, eventID: "first", mediaID: "a"))
        XCTAssertTrue(plan.ended(in: session, eventID: "second", mediaID: "b"))
    }
    func testImportedSettingsValidateHostScopeAndZoom() throws {
        var settings = ExportBrowserSettings(desktop: false, zoom: 1, gestures: false, history: true, restoreTabs: true, blockedSites: ["example.org"], sitePreferences: [:])
        XCTAssertNoThrow(try settings.validate())
        settings.blockedSites = ["youtube.com"]; XCTAssertThrowsError(try settings.validate())
        settings.blockedSites = []; settings.zoom = .infinity; XCTAssertThrowsError(try settings.validate())
    }
    func testSharedInboxExpiresAndRejectsSecretLinks() throws {
        let name = "DevnTube.InboxTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name)); defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(ShareInbox.submit(SharedLink(address: "https://example.org/?token=private", action: .save), defaults: defaults))
        XCTAssertTrue(ShareInbox.submit(SharedLink(address: "https://example.org/", action: .queue, createdAt: .now.addingTimeInterval(-901)), defaults: defaults))
        XCTAssertTrue(ShareInbox.read(defaults: defaults).isEmpty)
        XCTAssertTrue(ShareInbox.submit(SharedLink(address: "https://example.org/", action: .open), defaults: defaults))
        XCTAssertEqual(ShareInbox.read(defaults: defaults).count, 1)
    }
}

#if canImport(WebKWeb)
@MainActor
final class LibraryPersistenceTests: XCTestCase {
    private func file() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json") }
    func testExportExcludesBookmarksProgressCookiesPrivateTabsAndLockState() throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url) }
        let store = LibraryStore(file: url)
        let id = try XCTUnwrap(store.addLink(title: "Owned", address: "https://example.org/own.mp4", kind: .authorizedDirect))
        store.recordProgress(id: id, seconds: 20, duration: 100, force: true)
        store.createPlaylist("Mine"); store.add(id, to: store.document.playlists[0].id); store.addNote(media: id, seconds: 20, text: "Own note")
        let data = try store.exportData(favorites: [], preferences: BrowserPreferences())
        let archive = try JSONDecoder().decode(UserDataArchive.self, from: data)
        XCTAssertNil(archive.library.media[0].fileBookmark); XCTAssertEqual(archive.library.media[0].position, 0); XCTAssertNil(archive.library.media[0].lastPlayedAt)
        let text = String(decoding: data, as: UTF8.self)
        for key in ["cookie", "password", "privateLock", "browserSession", "diagnostic", "privateTabs"] { XCTAssertFalse(text.contains(key)) }
        let restored = LibraryStore(file: url); XCTAssertEqual(restored.document.media[0].position, 20)
    }
    func testInvalidImportDoesNotMutateExistingLibrary() throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url) }
        let store = LibraryStore(file: url); _ = store.addLink(title: "Keep", address: "https://example.org/")
        let original = store.document
        XCTAssertThrowsError(try store.importData(Data("{\"version\":999}".utf8)))
        XCTAssertEqual(store.document, original)
    }
    func testUnreadableLibraryIsPreservedAndNotOverwritten() throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("not valid JSON".utf8); try original.write(to: url)
        let store = LibraryStore(file: url); XCTAssertNotNil(store.error)
        XCTAssertNil(store.addLink(title: "No overwrite", address: "https://example.org/"))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
    func testHistoryClearRemovesProgressButPreservesOwnPlaylistsAndNotes() throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url) }
        let store = LibraryStore(file: url); let id = try XCTUnwrap(store.addLink(title: "Owned", address: "https://example.org/a.mp4", kind: .authorizedDirect))
        store.createPlaylist("Mine"); store.add(id, to: store.document.playlists[0].id); store.addNote(media: id, seconds: 1, text: "Keep")
        store.recordProgress(id: id, seconds: 20, duration: 100, force: true); store.clearProgress()
        XCTAssertEqual(store.document.media[0].position, 0); XCTAssertEqual(store.document.notes.count, 1); XCTAssertEqual(store.document.playlists[0].mediaIDs, [id])
    }
}

#endif

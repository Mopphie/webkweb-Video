import XCTest
import WebKit
@testable import WebKWeb

@MainActor
final class ComplianceMigrationTests: XCTestCase {
    func testRetiredPreferencesAndOwnedWKCacheAreRemovedWithoutDeletingUserImport() async throws {
        let defaults = UserDefaults.standard
        let keys = [PreferencesStorage.key, "complianceMigration", "complianceCleanupPending", "filterUpdatedAt", "filterListIDsV3", "sponsorBlockEnabled"]
        var saved: [String: Any] = [:]; for key in keys { saved[key] = defaults.object(forKey: key) }
        let group = UserDefaults(suiteName: FavoriteStorage.groupID)
        let favoriteData = group?.data(forKey: FavoriteStorage.key), consent = group?.object(forKey: FavoriteStorage.consentKey)
        let store = try XCTUnwrap(WKContentRuleListStore.default()), id = "webkweb-upgrade-test-" + UUID().uuidString
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ImportedFilters")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let userFile = directory.appendingPathComponent(UUID().uuidString + ".txt"); try "own user file".write(to: userFile, atomically: true, encoding: .utf8)
        defer {
            for key in keys { defaults.set(saved[key], forKey: key) }
            group?.set(favoriteData, forKey: FavoriteStorage.key); group?.set(consent, forKey: FavoriteStorage.consentKey)
            try? FileManager.default.removeItem(at: userFile)
            store.removeContentRuleList(forIdentifier: id, completionHandler: { _ in })
        }
        let _: WKContentRuleList = try await withCheckedThrowingContinuation { reply in
            store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: #"[{"trigger":{"url-filter":"^https://owned-test.invalid/"},"action":{"type":"block"}}]"#) { list, error in
                if let list { reply.resume(returning: list) } else { reply.resume(throwing: error ?? URLError(.cannotCreateFile)) }
            }
        }
        defaults.set(Data(#"{"history":false,"blocking":true,"sponsorBlock":true,"sources":[],"categories":["sponsor"]}"#.utf8), forKey: PreferencesStorage.key)
        defaults.set(0, forKey: "complianceMigration"); defaults.set(true, forKey: "sponsorBlockEnabled"); defaults.set([id], forKey: "filterListIDsV3"); defaults.set(Date(), forKey: "filterUpdatedAt")
        ComplianceMigration.run()
        for _ in 0..<100 { if defaults.integer(forKey: "complianceMigration") == 4 { break }; try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(defaults.integer(forKey: "complianceMigration"), 4)
        XCTAssertNil(defaults.object(forKey: "sponsorBlockEnabled")); XCTAssertNil(defaults.object(forKey: "filterListIDsV3")); XCTAssertNil(defaults.object(forKey: "filterUpdatedAt"))
        XCTAssertFalse(PreferencesStorage.load().history)
        let cleaned = String(decoding: try XCTUnwrap(defaults.data(forKey: PreferencesStorage.key)), as: UTF8.self)
        XCTAssertFalse(cleaned.contains("sponsorBlock")); XCTAssertFalse(cleaned.contains("categories"))
        let ids: [String] = await withCheckedContinuation { reply in store.getAvailableContentRuleListIdentifiers { reply.resume(returning: $0 ?? []) } }
        XCTAssertFalse(ids.contains(id)); XCTAssertTrue(FileManager.default.fileExists(atPath: userFile.path))
        XCTAssertTrue(FavoriteStorage.read().isEmpty)
    }
}

import Foundation
import WebKit

enum ComplianceMigration {
    static func run() {
        FavoriteStorage.removeRetiredShareInbox()
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: "complianceMigration") < 4 else { return }
        for key in ["blockingEnabled", "filterUpdatedAt", "filterListIDsV2", "filterListIDsV3", "filterUpdatedAtV2", "filterUpdatedAtV3",
                    "sponsorBlockEnabled", "sponsorBlockCache", "sponsorBlockCategories", "sponsorBlockCacheV1"] {
            defaults.removeObject(forKey: key)
        }
        let fm = FileManager.default
        var fileCleanupFailed = false
        for directory in [fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
                          fm.urls(for: .cachesDirectory, in: .userDomainMask).first].compactMap({ $0 }) {
            for name in ["FilterSourceCache", "SponsorBlock", "SponsorBlockCache", "sponsorblock-cache.json"] {
                let target = directory.appendingPathComponent(name)
                if fm.fileExists(atPath: target.path) { do { try fm.removeItem(at: target) } catch { fileCleanupFailed = true } }
            }
        }
        // ImportedFilters are user files: retained, never loaded or applied.
        if let data = defaults.data(forKey: PreferencesStorage.key),
           let cleaned = try? JSONDecoder().decode(BrowserPreferences.self, from: data) {
            PreferencesStorage.save(cleaned) // Strip retired nested fields too.
        }
        if !PreferencesStorage.load().shareFavoritesWithSystem { FavoriteStorage.write([]) }
        defaults.set(3, forKey: "complianceMigration") // Retry on next launch unless every cleanup succeeds.
        let fileFailure = fileCleanupFailed
        Task { @MainActor in
            guard let store = WKContentRuleListStore.default() else {
                defaults.set(true, forKey: "complianceCleanupPending"); return
            }
            let ids: [String] = await withCheckedContinuation { reply in
                store.getAvailableContentRuleListIdentifiers { reply.resume(returning: $0 ?? []) }
            }
            var failed = fileFailure
            for id in ids where id.hasPrefix("webkweb-") {
                let removed: Bool = await withCheckedContinuation { reply in
                    store.removeContentRuleList(forIdentifier: id) { reply.resume(returning: $0 == nil) }
                }
                failed = failed || !removed
            }
            defaults.set(failed, forKey: "complianceCleanupPending")
            defaults.set(failed ? 3 : 4, forKey: "complianceMigration")
        }
    }
}

import Foundation

enum SharedLinkAction: String, Codable, CaseIterable { case open, queue, save }
struct SharedLink: Identifiable, Codable {
    var id = UUID()
    var address: String
    var action: SharedLinkAction
    var createdAt = Date()
}
enum ShareInbox {
    static let key = "explicitSharedLinksV1"
    static func submit(_ link: SharedLink, defaults: UserDefaults? = UserDefaults(suiteName: FavoriteStorage.groupID)) -> Bool {
        guard StoredAddress.clean(link.address) != nil, let defaults else { return false }
        var values = read(defaults: defaults)
        values.append(link)
        guard let data = try? JSONEncoder().encode(Array(values.suffix(20))) else { return false }
        defaults.set(data, forKey: key); return true
    }
    static func read(defaults: UserDefaults?) -> [SharedLink] {
        guard let data = defaults?.data(forKey: key), data.count <= 200_000,
              let values = try? JSONDecoder().decode([SharedLink].self, from: data) else { return [] }
        return values.filter { StoredAddress.clean($0.address) != nil && Date().timeIntervalSince($0.createdAt) >= 0 && Date().timeIntervalSince($0.createdAt) < 900 }.prefix(20).map { $0 }
    }
    static func take() -> [SharedLink] {
        let defaults = UserDefaults(suiteName: FavoriteStorage.groupID)
        let values = read(defaults: defaults); defaults?.removeObject(forKey: key); return values
    }
}

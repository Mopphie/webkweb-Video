import Foundation

struct FavoriteSnapshot: Codable, Identifiable {
    let id: String
    let title: String
    let address: String

    var deepLink: URL? {
        guard let clean = StoredAddress.clean(address) else { return nil }
        var parts = URLComponents()
        parts.scheme = "devntube"
        parts.host = "open"
        parts.queryItems = [URLQueryItem(name: "url", value: clean)]
        return parts.url
    }
}

enum FavoriteStorage {
    // Both targets must use the same provisioned App Group.
    static let groupID = "group.de.mopphie.devntube"
    static let key = "favoriteSnapshots"

    static func read() -> [FavoriteSnapshot] {
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: key),
              let favorites = try? JSONDecoder().decode([FavoriteSnapshot].self, from: data) else { return [] }
        return favorites.compactMap { favorite in StoredAddress.clean(favorite.address).map { FavoriteSnapshot(id: favorite.id, title: favorite.title, address: $0) } }
    }

    static func write(_ favorites: [FavoriteSnapshot]) {
        let clean = favorites.compactMap { favorite in StoredAddress.clean(favorite.address).map { FavoriteSnapshot(id: favorite.id, title: favorite.title, address: $0) } }
        guard let data = try? JSONEncoder().encode(clean) else { return }
        UserDefaults(suiteName: groupID)?.set(data, forKey: key)
    }
}

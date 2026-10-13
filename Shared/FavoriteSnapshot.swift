import Foundation

struct FavoriteSnapshot: Codable, Identifiable {
    let id: String
    let title: String
    let address: String

    var deepLink: URL? {
        var parts = URLComponents()
        parts.scheme = "webkweb"
        parts.host = "open"
        parts.queryItems = [URLQueryItem(name: "url", value: address)]
        return parts.url
    }
}

enum FavoriteStorage {
    // Both targets must use the same provisioned App Group.
    static let groupID = "group.de.mopphie.webkweb"
    static let key = "favoriteSnapshots"

    static func read() -> [FavoriteSnapshot] {
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: key),
              let favorites = try? JSONDecoder().decode([FavoriteSnapshot].self, from: data) else { return [] }
        return favorites
    }

    static func write(_ favorites: [FavoriteSnapshot]) {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        UserDefaults(suiteName: groupID)?.set(data, forKey: key)
    }
}

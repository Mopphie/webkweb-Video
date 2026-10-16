import Foundation

enum SearchEngine: String, Codable, CaseIterable, Identifiable {
    case google, duckDuckGo, bing
    var id: String { rawValue }
    var title: String { self == .duckDuckGo ? "DuckDuckGo" : rawValue.capitalized }
    func search(_ text: String) -> URL? {
        let base = self == .google ? "https://www.google.com/search" : self == .bing ? "https://www.bing.com/search" : "https://duckduckgo.com/"
        var parts = URLComponents(string: base)!
        parts.queryItems = [URLQueryItem(name: "q", value: text)]
        return parts.url
    }
}

struct BrowserPreferences: Codable, Equatable {
    var gestures = false
    var history = true
    var restoreTabs = true
    var desktop = false
    var zoom = 1.0
    var searchEngine = SearchEngine.google
    var appearance = AppAppearance.system
    var skipSeconds = 10
    var shareFavoritesWithSystem = false
    var privateLock = false
    var blockedSites: [String] = []
    var sitePreferences: [String: SitePreference] = [:]

    init() {}
    enum CodingKeys: String, CodingKey {
        case gestures, history, restoreTabs, desktop, zoom, searchEngine, appearance, skipSeconds, shareFavoritesWithSystem, privateLock, blockedSites, sitePreferences
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gestures = try c.decodeIfPresent(Bool.self, forKey: .gestures) ?? gestures
        history = try c.decodeIfPresent(Bool.self, forKey: .history) ?? history
        restoreTabs = try c.decodeIfPresent(Bool.self, forKey: .restoreTabs) ?? restoreTabs
        desktop = try c.decodeIfPresent(Bool.self, forKey: .desktop) ?? desktop
        zoom = min(2, max(0.5, try c.decodeIfPresent(Double.self, forKey: .zoom) ?? zoom))
        searchEngine = try c.decodeIfPresent(SearchEngine.self, forKey: .searchEngine) ?? searchEngine
        appearance = try c.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
        skipSeconds = min(60, max(5, try c.decodeIfPresent(Int.self, forKey: .skipSeconds) ?? 10))
        shareFavoritesWithSystem = try c.decodeIfPresent(Bool.self, forKey: .shareFavoritesWithSystem) ?? false
        privateLock = try c.decodeIfPresent(Bool.self, forKey: .privateLock) ?? false
        blockedSites = (try c.decodeIfPresent([String].self, forKey: .blockedSites) ?? []).filter { SiteNavigationPolicy.validBlockedHost($0) }
        sitePreferences = try c.decodeIfPresent([String: SitePreference].self, forKey: .sitePreferences) ?? [:]
    }
}

enum PreferencesStorage {
    static let key = "browserPreferencesV2"
    static func load() -> BrowserPreferences {
        if let data = UserDefaults.standard.data(forKey: key), let options = try? JSONDecoder().decode(BrowserPreferences.self, from: data) { return options }
        return BrowserPreferences()
    }
    static func save(_ options: BrowserPreferences) {
        if let data = try? JSONEncoder().encode(options) { UserDefaults.standard.set(data, forKey: key) }
    }
}

struct TabSnapshot: Codable {
    var id: UUID
    var address: String
    var title: String
    var pinned: Bool? = nil
    var group: String? = nil
}
struct BrowserSessionSnapshot: Codable {
    var tabs: [TabSnapshot]
    var selected: UUID?
}

enum ReleaseConfiguration {
    static var privacyURL: URL? { publicURL(Bundle.main.object(forInfoDictionaryKey: "WebKWebPrivacyURL") as? String ?? "") }
    static var supportURL: URL? { publicURL(Bundle.main.object(forInfoDictionaryKey: "WebKWebSupportURL") as? String ?? "") }
    static var operatorContact: String { (Bundle.main.object(forInfoDictionaryKey: "WebKWebOperatorContact") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    static func publicURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.host != nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil else { return nil }
        return url
    }
}

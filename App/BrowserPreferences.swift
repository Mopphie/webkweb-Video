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

struct FilterSource: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var address: String
    var enabled: Bool = true
    var localFile: String?
    static let defaults: [FilterSource] = [
        FilterSource(title: "AdGuard DNS", address: "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"),
        FilterSource(title: "HaGeZi Light", address: "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/light.txt", enabled: false)
    ]
    // Remove the old supplied aggregate on upgrades as well as fresh installs.
    // User-created local lists and unrelated subscriptions remain untouched.
    static func withoutRetiredSources(_ sources: [FilterSource]) -> [FilterSource] {
        sources.filter { source in
            guard source.localFile == nil,
                  let url = URL(string: source.address), let host = url.host?.lowercased() else { return true }
            let path = url.path.lowercased()
            if host == "raw.githubusercontent.com" {
                return !path.hasPrefix("/stevenblack/hosts/")
            }
            if host == "github.com" { return !path.hasPrefix("/stevenblack/hosts/") }
            return true
        }
    }
}

struct BrowserPreferences: Codable, Equatable {
    var blocking = true
    var gestures = false
    var autoPiP = false
    var hideShorts = false
    var preferOriginalAudio = false
    var history = true
    var restoreTabs = true
    var desktop = false
    var zoom = 1.0
    var searchEngine = SearchEngine.google
    var allowlist: [String] = []
    var sources = FilterSource.defaults
    var cloudSync = false

    init() {}
    enum CodingKeys: String, CodingKey {
        case blocking, gestures, autoPiP, hideShorts, preferOriginalAudio, history, restoreTabs, desktop, zoom, searchEngine,
             allowlist, sources, cloudSync
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blocking = try c.decodeIfPresent(Bool.self, forKey: .blocking) ?? blocking
        gestures = try c.decodeIfPresent(Bool.self, forKey: .gestures) ?? gestures
        autoPiP = try c.decodeIfPresent(Bool.self, forKey: .autoPiP) ?? autoPiP
        hideShorts = try c.decodeIfPresent(Bool.self, forKey: .hideShorts) ?? hideShorts
        preferOriginalAudio = try c.decodeIfPresent(Bool.self, forKey: .preferOriginalAudio) ?? preferOriginalAudio
        history = try c.decodeIfPresent(Bool.self, forKey: .history) ?? history
        restoreTabs = try c.decodeIfPresent(Bool.self, forKey: .restoreTabs) ?? restoreTabs
        desktop = try c.decodeIfPresent(Bool.self, forKey: .desktop) ?? desktop
        zoom = min(2, max(0.5, try c.decodeIfPresent(Double.self, forKey: .zoom) ?? zoom))
        searchEngine = try c.decodeIfPresent(SearchEngine.self, forKey: .searchEngine) ?? searchEngine
        allowlist = try c.decodeIfPresent([String].self, forKey: .allowlist) ?? allowlist
        sources = FilterSource.withoutRetiredSources(try c.decodeIfPresent([FilterSource].self, forKey: .sources) ?? sources)
        cloudSync = try c.decodeIfPresent(Bool.self, forKey: .cloudSync) ?? cloudSync
    }
}

enum PreferencesStorage {
    static let key = "browserPreferencesV2"
    static func load() -> BrowserPreferences {
        if let data = UserDefaults.standard.data(forKey: key), let options = try? JSONDecoder().decode(BrowserPreferences.self, from: data) { return options }
        var options = BrowserPreferences()
        options.blocking = UserDefaults.standard.object(forKey: "blockingEnabled") as? Bool ?? true
        return options
    }
    static func save(_ options: BrowserPreferences) {
        if let data = try? JSONEncoder().encode(options) { UserDefaults.standard.set(data, forKey: key) }
    }
}

struct TabSnapshot: Codable {
    var id: UUID
    var address: String
    var title: String
}
struct BrowserSessionSnapshot: Codable {
    var tabs: [TabSnapshot]
    var selected: UUID?
}

enum ReleaseConfiguration {
    static var privacyURL: URL? { publicURL(Bundle.main.object(forInfoDictionaryKey: "WebKWebPrivacyURL") as? String ?? "") }
    static var supportURL: URL? { publicURL(Bundle.main.object(forInfoDictionaryKey: "WebKWebSupportURL") as? String ?? "") }
    static var operatorContact: String { (Bundle.main.object(forInfoDictionaryKey: "WebKWebOperatorContact") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    static var cloudContainer: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "WebKWebCloudKitContainer") as? String,
              value.hasPrefix("iCloud."), !value.contains("$(") else { return nil }
        return value
    }
    static func publicURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.host != nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil else { return nil }
        return url
    }
}

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
        FilterSource(title: "HaGeZi Light", address: "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/light.txt", enabled: false),
        FilterSource(title: "StevenBlack Hosts", address: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts", enabled: false)
    ]
}

struct BrowserPreferences: Codable, Equatable {
    var blocking = true
    var sponsorBlock = false
    var gestures = false
    var autoPiP = false
    var hideShorts = false
    var preferOriginalAudio = false
    var history = true
    var restoreTabs = true
    var desktop = false
    var zoom = 1.0
    var searchEngine = SearchEngine.google
    var categories = Set(SponsorSegment.categories)
    var allowlist: [String] = []
    var sponsorAllowlist: [String] = []
    var sources = FilterSource.defaults
    var cloudSync = false
    var privacyURL = ""
    var supportURL = ""
    var operatorContact = ""

    init() {}
    enum CodingKeys: String, CodingKey {
        case blocking, sponsorBlock, gestures, autoPiP, hideShorts, preferOriginalAudio, history, restoreTabs, desktop, zoom, searchEngine,
             categories, allowlist, sponsorAllowlist, sources, cloudSync, privacyURL, supportURL, operatorContact
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blocking = try c.decodeIfPresent(Bool.self, forKey: .blocking) ?? blocking
        sponsorBlock = try c.decodeIfPresent(Bool.self, forKey: .sponsorBlock) ?? sponsorBlock
        gestures = try c.decodeIfPresent(Bool.self, forKey: .gestures) ?? gestures
        autoPiP = try c.decodeIfPresent(Bool.self, forKey: .autoPiP) ?? autoPiP
        hideShorts = try c.decodeIfPresent(Bool.self, forKey: .hideShorts) ?? hideShorts
        preferOriginalAudio = try c.decodeIfPresent(Bool.self, forKey: .preferOriginalAudio) ?? preferOriginalAudio
        history = try c.decodeIfPresent(Bool.self, forKey: .history) ?? history
        restoreTabs = try c.decodeIfPresent(Bool.self, forKey: .restoreTabs) ?? restoreTabs
        desktop = try c.decodeIfPresent(Bool.self, forKey: .desktop) ?? desktop
        zoom = min(2, max(0.5, try c.decodeIfPresent(Double.self, forKey: .zoom) ?? zoom))
        searchEngine = try c.decodeIfPresent(SearchEngine.self, forKey: .searchEngine) ?? searchEngine
        categories = (try c.decodeIfPresent(Set<String>.self, forKey: .categories) ?? categories).intersection(SponsorSegment.categories)
        allowlist = try c.decodeIfPresent([String].self, forKey: .allowlist) ?? allowlist
        sponsorAllowlist = try c.decodeIfPresent([String].self, forKey: .sponsorAllowlist) ?? sponsorAllowlist
        sources = try c.decodeIfPresent([FilterSource].self, forKey: .sources) ?? sources
        cloudSync = try c.decodeIfPresent(Bool.self, forKey: .cloudSync) ?? cloudSync
        privacyURL = try c.decodeIfPresent(String.self, forKey: .privacyURL) ?? privacyURL
        supportURL = try c.decodeIfPresent(String.self, forKey: .supportURL) ?? supportURL
        operatorContact = try c.decodeIfPresent(String.self, forKey: .operatorContact) ?? operatorContact
    }
}

enum PreferencesStorage {
    static let key = "browserPreferencesV2"
    static func load() -> BrowserPreferences {
        if let data = UserDefaults.standard.data(forKey: key), let options = try? JSONDecoder().decode(BrowserPreferences.self, from: data) { return options }
        var options = BrowserPreferences()
        options.blocking = UserDefaults.standard.object(forKey: "blockingEnabled") as? Bool ?? true
        options.sponsorBlock = UserDefaults.standard.bool(forKey: "sponsorBlockEnabled")
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

import Foundation

/// Top-level navigation only: no resource, ad, iframe, DNS or system filtering.
enum SiteNavigationPolicy {
    static func validBlockedHost(_ value: String) -> Bool {
        guard value == SourceCapabilities.canonicalHost(value), let parts = URLComponents(string: "https://" + value), parts.host == value,
              value.contains("."), !value.contains("*"), parts.user == nil, parts.password == nil,
              parts.port == nil, parts.path.isEmpty, parts.query == nil, parts.fragment == nil,
              !SourceCapabilities.isPlatform(value),
              !SourceCapabilities.platformDomains.contains(where: { $0.hasSuffix("." + value) }) else { return false }
        return true
    }
    static func blocks(_ url: URL, mainFrame: Bool, privateMode: Bool, sites: [String]) -> Bool {
        guard mainFrame, !privateMode, let host = url.host?.lowercased(), !SourceCapabilities.isPlatform(host) else { return false }
        return sites.contains { validBlockedHost($0) && (host == $0 || host.hasSuffix("." + $0)) }
    }
}

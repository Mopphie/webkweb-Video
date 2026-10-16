import Foundation

enum MediaSourceKind: String, Codable {
    case website, localFile, authorizedDirect
}

/// Permission is independent from decoder support. No platform stream extraction.
struct SourceCapabilities: Equatable {
    var nativePlayback: Bool
    var automaticAdvance: Bool
    var backgroundAudio: Bool
    var systemPiP: Bool
    var progress: Bool
    var explanation: String

    static func forSource(_ kind: MediaSourceKind) -> Self {
        switch kind {
        case .website:
            return Self(nativePlayback: false, automaticAdvance: false, backgroundAudio: false,
                        systemPiP: false, progress: false,
                        explanation: "Nutze die Bedienelemente der Website. PiP, AirPlay und Hintergrundwiedergabe richten sich nach deren Angebot und deinen Berechtigungen. Die App schaltet keine Dienstfunktionen frei.")
        case .localFile, .authorizedDirect:
            return Self(nativePlayback: true, automaticAdvance: true, backgroundAudio: true,
                        systemPiP: true, progress: true,
                        explanation: "Nativer Systemplayer für eigene oder berechtigt nutzbare Medien. Formate, PiP und AirPlay hängen zusätzlich von iOS, Gerät und Quelle ab.")
        }
    }
    static let platformDomains = ["youtube.com", "youtube-nocookie.com", "youtu.be", "googlevideo.com",
                                  "ytimg.com", "youtubei.googleapis.com", "twitch.tv", "ttvnw.net",
                                  "tiktok.com", "tiktokcdn.com", "rumble.com"]
    static func canonicalHost(_ value: String) -> String { value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
    static func isPlatform(_ host: String) -> Bool {
        let host = canonicalHost(host)
        return platformDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
    static func allowsBridgeControls(mainHost: String?, frameHost: String?) -> Bool {
        ![mainHost, frameHost].compactMap { $0 }.contains(where: isPlatform)
    }
    static func directMediaURL(_ input: String) -> URL? {
        guard let clean = LibraryAddress.clean(input), let url = URL(string: clean), url.scheme == "https",
              let host = url.host, !isPlatform(host),
              ["mp4", "m4v", "mov", "m4a", "mp3", "aac", "m3u8"].contains(url.pathExtension.lowercased()),
              LibraryAddress.clean(input) != nil else { return nil }
        return url
    }
}

enum LibraryAddress {
    /// Signed/session URLs stay in the website, never in the app's library/export.
    static func clean(_ input: String) -> String? {
        StoredAddress.clean(input)
    }
}

struct SitePreference: Codable, Equatable {
    var desktop = false
    var zoom = 1.0
}

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { self == .system ? "System" : self == .light ? "Hell" : "Dunkel" }
}

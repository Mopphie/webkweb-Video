import Foundation
import SwiftData

@Model
final class SavedPage {
    var identifier: String = ""
    var title: String = ""
    var address: String = ""
    var visitedAt: Date = Date.now
    var favorite: Bool = false
    var favoriteOrder: Double = 0
    var customTitle: Bool = false

    init(title: String, address: String, favorite: Bool = false) {
        identifier = UUID().uuidString
        self.title = title
        self.address = address
        self.favorite = favorite
        visitedAt = .now
    }
}

enum AddressResolver {
    static func directURL(_ input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = value.contains("://") ? value : "https://" + value
        guard let parts = URLComponents(string: candidate), ["http", "https"].contains(parts.scheme?.lowercased() ?? ""), parts.host != nil, parts.user == nil, parts.password == nil, !value.contains(where: { $0.isWhitespace }) else { return nil }; return parts.url
    }
    static func resolve(_ input: String, engine: SearchEngine = .google) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let candidate = text.contains("://") ? text : "https://" + text
        // Never send credential-bearing URLs to a search provider.
        if let supplied = URLComponents(string: candidate), supplied.user != nil || supplied.password != nil { return nil }
        if !text.contains(where: { $0.isWhitespace }),
           let parts = URLComponents(string: candidate),
           ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
           parts.user == nil, parts.password == nil,
           let host = parts.host, !host.isEmpty,
           text.contains("://") || host.contains(".") || host == "localhost" || host.contains(":"),
           let url = parts.url {
            return url
        }
        return engine.search(text)
    }

    static func deepLink(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == "webkweb", url.host == "open",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = parts.queryItems?.first(where: { $0.name == "url" })?.value,
              let destination = URL(string: value),
              ["http", "https"].contains(destination.scheme?.lowercased() ?? ""),
              destination.host != nil, destination.user == nil, destination.password == nil else { return nil }
        return value
    }
}

enum YouTubeAddress {
    static func videoID(in url: URL?) -> String? {
        guard let url, let host = url.host?.lowercased(),
              host == "youtube.com" || host.hasSuffix(".youtube.com"),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let path = url.path.split(separator: "/")
        let candidate: String?
        if path.first == "shorts" || path.first == "embed" || path.first == "live" {
            candidate = path.count > 1 ? String(path[1]) : nil
        } else if url.path == "/watch" {
            candidate = parts.queryItems?.first(where: { $0.name == "v" })?.value
        } else {
            candidate = nil
        }
        guard let candidate, candidate.count == 11,
              candidate.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0)
              }) else { return nil }
        return candidate
    }
}

struct DirectMedia: Equatable {
    let url: URL
    let contentType: String

    init?(source: String, contentType: String?, encrypted: Bool) {
        guard !encrypted, let parts = URLComponents(string: source),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, let url = parts.url else { return nil }
        let knownTypes = ["mp4": "video/mp4", "m4v": "video/mp4", "mov": "video/quicktime",
                          "m3u8": "application/x-mpegURL", "webm": "video/webm",
                          "mp3": "audio/mpeg", "m4a": "audio/mp4"]
        let declared = contentType?.split(separator: ";").first.map(String.init)?.lowercased()
        guard let mime = declared.flatMap({ value in
            (value.hasPrefix("video/") || value.hasPrefix("audio/") ||
             ["application/x-mpegurl", "application/vnd.apple.mpegurl"].contains(value)) ? value : nil
        }) ?? knownTypes[url.pathExtension.lowercased()] else { return nil }
        self.url = url
        self.contentType = mime
    }
}

struct SleepPlan: Codable {
    private(set) var deadline: Date?
    private(set) var remainingVideos: Int?
    private(set) var tabID: UUID?
    private var endedEvents = Set<String>()
    private(set) var targetMediaID: String?

    var isActive: Bool { deadline != nil || remainingVideos != nil }

    mutating func arm(minutes: Int, now: Date = .now) { arm(seconds: minutes * 60, now: now) }
    mutating func arm(seconds: Int, now: Date = .now) {
        cancel()
        guard seconds > 0, seconds <= 86400 else { return }
        deadline = now.addingTimeInterval(TimeInterval(seconds))
    }

    mutating func arm(videos: Int, tabID: UUID, mediaID: String? = nil) {
        cancel()
        guard videos > 0, videos <= 100 else { return }
        remainingVideos = videos
        self.tabID = tabID
        targetMediaID = mediaID
    }

    func hasExpired(at now: Date = .now) -> Bool {
        deadline.map { now >= $0 } ?? false
    }

    mutating func ended(in tabID: UUID, eventID: String, mediaID: String? = nil) -> Bool {
        if let targetMediaID, targetMediaID != mediaID { return false }
        guard self.tabID == tabID, let remaining = remainingVideos,
              !eventID.isEmpty, endedEvents.insert(eventID).inserted else { return false }
        remainingVideos = max(0, remaining - 1)
        return remaining <= 1
    }

    mutating func cancel() {
        deadline = nil
        remainingVideos = nil
        tabID = nil
        targetMediaID = nil
        endedEvents.removeAll()
    }
}

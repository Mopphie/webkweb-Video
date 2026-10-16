import Foundation

enum AddressResolver {
    static func directURL(_ input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = value.contains("://") ? value : "https://" + value
        guard let parts = URLComponents(string: candidate), ["http", "https"].contains(parts.scheme?.lowercased() ?? ""), parts.host != nil, parts.user == nil, parts.password == nil, !value.contains(where: { $0.isWhitespace }) else { return nil }; return parts.url
    }
    static func resolve(_ input: String, engine: SearchEngine = .google) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 8192 else { return nil }
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
        guard url.scheme?.lowercased() == "devntube", url.host == "open",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = parts.queryItems?.first(where: { $0.name == "url" })?.value,
              let destination = URL(string: value),
              ["http", "https"].contains(destination.scheme?.lowercased() ?? ""),
              destination.host != nil, destination.user == nil, destination.password == nil else { return nil }
        return value
    }
}

enum YouTubeAddress {
    static func isWatchPage(_ url: URL?) -> Bool {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.path == "/watch", url.user == nil, url.password == nil else { return false }
        return videoID(in: url) != nil
    }
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

/// A user's exit applies to this watch item, including its SPA/BFCache returns.
/// A different watch item may use the compact presentation again.
struct WatchPresentationState {
    private(set) var dismissedVideoID: String?
    func isImmersive(at url: URL?) -> Bool {
        YouTubeAddress.isWatchPage(url) && YouTubeAddress.videoID(in: url) != dismissedVideoID
    }
    mutating func dismiss(at url: URL?) { dismissedVideoID = YouTubeAddress.videoID(in: url) }
    mutating func show() { dismissedVideoID = nil }
    static func exitURL(previous: URL?) -> URL {
        if let previous, let host = previous.host?.lowercased(),
           ["https", "http"].contains(previous.scheme ?? ""),
           previous.user == nil, previous.password == nil,
           host == "youtube.com" || host.hasSuffix(".youtube.com") { return previous }
        return URL(string: "https://m.youtube.com/")!
    }
}

struct SleepPlan: Codable {
    private(set) var deadline: Date?
    private(set) var remainingVideos: Int?
    private(set) var tabID: UUID?
    private var endedEvents = Set<String>()
    private(set) var targetMediaID: String?

    var isActive: Bool { deadline != nil || remainingVideos != nil }

    mutating func arm(minutes: Int, now: Date = .now) { guard (1...1440).contains(minutes) else { cancel(); return }; arm(seconds: minutes * 60, now: now) }
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

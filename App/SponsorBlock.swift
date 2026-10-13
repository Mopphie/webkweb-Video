import Foundation

struct SponsorSegment: Codable, Equatable {
    let segment: [Double]
    let category: String

    var isValid: Bool {
        Self.categories.contains(category) && segment.count == 2 &&
        segment.allSatisfy(\.isFinite) && segment[0] >= 0 && segment[1] > segment[0]
    }

    static let categories = ["sponsor", "intro", "outro", "selfpromo"]
}

actor SponsorBlockService {
    static let shared = SponsorBlockService()
    private let session: URLSession
    private var cache: [String: (Date, [SponsorSegment])] = [:]

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    func segments(for videoID: String) async throws -> [SponsorSegment] {
        if let (date, segments) = cache[videoID], Date().timeIntervalSince(date) < 3600 { return segments }
        let categories = String(decoding: try JSONEncoder().encode(SponsorSegment.categories), as: UTF8.self)
        var parts = URLComponents(string: "https://sponsor.ajay.app/api/skipSegments")!
        parts.queryItems = [URLQueryItem(name: "videoID", value: videoID),
                           URLQueryItem(name: "categories", value: categories)]
        let (data, response) = try await session.data(from: parts.url!)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 404 { cache[videoID] = (.now, []); return [] }
        guard response.statusCode == 200, data.count <= 1_000_000 else { throw URLError(.badServerResponse) }
        let result = try JSONDecoder().decode([SponsorSegment].self, from: data)
            .filter(\.isValid).sorted { $0.segment[0] < $1.segment[0] }
        if cache.count > 100 { cache.removeAll() }
        cache[videoID] = (.now, result)
        return result
    }
}

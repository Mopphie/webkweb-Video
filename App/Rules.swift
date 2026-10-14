import Foundation
import WebKit

struct FilterConversion: Sendable {
    let jsons: [String]
    let domainCount: Int
    let skippedCount: Int
    var json: String { jsons.first ?? "[]" }
}
enum FilterError: LocalizedError {
    case unsupportedException, emptyList, invalidSource
    var errorDescription: String? {
        switch self {
        case .unsupportedException: return "Nicht unterstützte Ausnahme: Diese Quelle wurde nicht angewendet."
        case .emptyList: return "Keine unterstützten Netzwerkregeln."
        case .invalidSource: return "Verwende eine HTTPS-Liste ohne Zugangsdaten."
        }
    }
}

enum DomainFilterConverter {
    static let baseline = "||doubleclick.net^\n||googlesyndication.com^\n||googleadservices.com^"
    // Each WK list stays below 50k rules. Every chunk carries its exceptions,
    // since ignore-previous-rules never crosses content-rule-list boundaries.
    static let chunkSize = 40_000
    static func convert(_ text: String) throws -> FilterConversion {
        var blocks: [[String: Any]] = [], exceptions: [[String: Any]] = []
        var seen = Set<String>(), skipped = 0
        for line in (baseline + "\n" + text).components(separatedBy: .newlines) {
            var rule = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if rule.hasPrefix("#") { continue }
            let hosts = rule.split(whereSeparator: { $0.isWhitespace })
            if hosts.count >= 2, ["0.0.0.0", "127.0.0.1", "::"].contains(String(hosts[0])) {
                let host = String(hosts[1]); if !host.contains(".") { continue }; rule = "||" + host + "^"
            }
            if rule.isEmpty || rule.hasPrefix("!") || rule.hasPrefix("[") { continue }
            if !seen.insert(rule).inserted { continue }
            let allow = rule.hasPrefix("@@")
            let value = allow ? String(rule.dropFirst(2)) : rule
            if allow && value.hasPrefix("/") && value.hasSuffix("/") {
                let pattern = String(value.dropFirst().dropLast())
                let image = #"\.(gif|jpe?g|png|webp)#(\/?.+)?(\/(ad)s?\/|\/ad-)"#
                let patterns: [String]
                if pattern == image {
                    patterns = ["gif", "jpe?g", "png", "webp"].flatMap { ext in
                        ["\\/(ad)s?\\/", "\\/ad-"].map { path in "\\." + ext + "#(\\/?.+)?(" + path + ")" }
                    }
                } else {
                    guard !pattern.isEmpty, !pattern.contains("|"), !pattern.contains("(?"), !pattern.contains("{"),
                          !pattern.contains("}"), !pattern.contains("\\1"), (try? NSRegularExpression(pattern: pattern)) != nil else { throw FilterError.unsupportedException }
                    patterns = [pattern]
                }
                exceptions += patterns.map { ["trigger": ["url-filter": $0], "action": ["type": "ignore-previous-rules"]] }
                continue
            }
            guard let parsed = parse(value, allow: allow) else {
                if allow { throw FilterError.unsupportedException }
                skipped += 1; continue
            }
            let record: [String: Any] = ["trigger": parsed, "action": ["type": allow ? "ignore-previous-rules" : "block"]]
            if allow { exceptions.append(record) } else { blocks.append(record) }
        }
        // Do not partially block YouTube's own ad endpoints: the player may
        // wait for a preroll response that never arrives. Host filters remain.
        guard blocks.count > 3 || skipped == 0 else { throw FilterError.emptyList }
        guard exceptions.count < 8000 else { throw FilterError.unsupportedException }
        var jsons: [String] = []
        for start in stride(from: 0, to: blocks.count, by: chunkSize) {
            let chunk = Array(blocks[start..<min(start + chunkSize, blocks.count)]) + exceptions
            jsons.append(String(decoding: try JSONSerialization.data(withJSONObject: chunk), as: UTF8.self))
        }
        return FilterConversion(jsons: jsons, domainCount: blocks.count, skippedCount: skipped)
    }
    private static func parse(_ input: String, allow: Bool) -> [String: Any]? {
        let parts = input.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
        let pattern = String(parts[0])
        guard let caret = pattern.firstIndex(of: "^"),
              pattern[pattern.index(after: caret)...].isEmpty || pattern[pattern.index(after: caret)...] == "|" else { return nil }
        var host = String(pattern[..<caret])
        let subdomains = host.hasPrefix("||")
        if !allow && !subdomains { return nil }
        while host.hasPrefix("|") { host.removeFirst() }
        guard host.contains("."), host.utf8.count < 254, !host.contains(".."),
              host.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-*").contains($0) }) else { return nil }
        if !allow && (host.contains("*") || host.split(separator: ".").contains(where: { $0.hasPrefix("-") || $0.hasSuffix("-") })) { return nil }
        var regex = ""
        for character in host.lowercased() {
            regex += character == "." ? "\\." : character == "*" ? "[^/@:]*" : String(character)
        }
        // Unanchored DNS suffix exceptions are still restricted to the host.
        let prefix = subdomains ? "([^/@:]+\\.)?" : (host.hasPrefix("-") ? "[^/@:]*" : "")
        var trigger: [String: Any] = ["url-filter": "^https?://([^/@]*@)?" + prefix + regex + "(:[0-9]+)?/"]
        if parts.count == 2 {
            let types = ["script": "script", "image": "image", "stylesheet": "style-sheet", "font": "font", "media": "media", "document": "document", "xmlhttprequest": "raw"]
            var resources: [String] = [], included: [String] = [], excluded: [String] = []
            for option in parts[1].split(separator: ",") {
                let value = String(option)
                if let type = types[value] { resources.append(type) }
                else if value == "third-party" { trigger["load-type"] = ["third-party"] }
                else if value == "~third-party" || value == "first-party" { trigger["load-type"] = ["first-party"] }
                else if value == "important" { continue }
                else if value.hasPrefix("domain=") {
                    for entry in value.dropFirst(7).split(separator: "|") {
                        let negated = entry.hasPrefix("~"), domain = String(negated ? entry.dropFirst() : entry[...])
                        guard domain.contains("."), !domain.contains("*"),
                              let parsed = URLComponents(string: "https://" + domain), parsed.host == domain,
                              parsed.user == nil, parsed.password == nil, parsed.port == nil, parsed.path.isEmpty,
                              parsed.query == nil, parsed.fragment == nil else { return nil }
                        if negated { excluded += [domain, "*." + domain] } else { included += [domain, "*." + domain] }
                    }
                } else { return nil }
            }
            if !resources.isEmpty { trigger["resource-type"] = resources }
            if !included.isEmpty { trigger["if-domain"] = included }
            if !excluded.isEmpty { trigger["unless-domain"] = excluded }
            // WebKit cannot combine if-domain and unless-domain on one trigger.
            if !included.isEmpty && !excluded.isEmpty { return nil }
        }
        return trigger
    }
}

private enum FilterDownloader {
    static func fetch(_ source: FilterSource) async throws -> String {
        if let name = source.localFile {
            return try String(contentsOf: importDirectory.appendingPathComponent(name), encoding: .utf8)
        }
        guard let url = ReleaseConfiguration.publicURL(source.address) else { throw FilterError.invalidSource }
        let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil; config.timeoutIntervalForRequest = 25
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, response.expectedContentLength <= 12_000_000 else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 12_000_000 else { throw URLError(.dataLengthExceedsMaximum) }; data.append(byte)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
        return text
    }
    static var importDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ImportedFilters", isDirectory: true)
    }
}

@MainActor
final class RuleStore: ObservableObject {
    static let shared = RuleStore()
    @Published private(set) var status = "Basisfilter wird vorbereitet …"
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var ruleCount = 3
    @Published private(set) var refreshing = false
    @Published private(set) var sourceStatus: [UUID: String] = [:]
    private final class Client {
        weak var view: WKWebView?
        var enabled: Bool
        var revision: UUID?
        init(_ view: WKWebView, _ enabled: Bool) { self.view = view; self.enabled = enabled }
    }
    private var clients: [UUID: Client] = [:]
    private var lists: [WKContentRuleList] = []
    private var revision = UUID()
    private var initialTask: Task<[WKContentRuleList], Never>?
    private var pendingRefresh = false
    private init() { lastUpdate = UserDefaults.standard.object(forKey: "filterUpdatedAtV2") as? Date }
    func apply(to view: WKWebView, tabID: UUID, enabled: Bool) async {
        let client = clients[tabID] ?? Client(view, enabled); client.enabled = enabled; clients[tabID] = client
        if !enabled { view.configuration.userContentController.removeAllContentRuleLists(); client.revision = nil; return }
        _ = await prepare()
        guard clients[tabID] === client, client.enabled else { return }; install(on: client)
    }
    func unregister(_ id: UUID) { clients.removeValue(forKey: id) }
    func hasAppliedRules(to id: UUID) -> Bool { clients[id]?.revision != nil }
    func prepare() async -> WKContentRuleList? {
        if lists.isEmpty {
            if initialTask == nil {
                initialTask = Task { [weak self] in
                    guard let self else { return [] }
                    // V2 cached lists include the removed YouTube endpoint blocks.
                    if let ids = UserDefaults.standard.stringArray(forKey: "filterListIDsV3"), !ids.isEmpty {
                        var result: [WKContentRuleList] = []
                        for id in ids { if let list = await self.lookup(id) { result.append(list) } }
                        if result.count == ids.count { return result }
                    }
                    return (try? await self.compile(DomainFilterConverter.convert(DomainFilterConverter.baseline))) ?? []
                }
            }
            let result = await initialTask?.value ?? []
            if lists.isEmpty { lists = result; status = result.isEmpty ? "Filter konnte nicht geladen werden." : "Netzwerkfilter bereit" }
        }
        return lists.first
    }
    func refreshIfNeeded(force: Bool = false) async {
        if refreshing { pendingRefresh = pendingRefresh || force; return }
        if !force, let lastUpdate, Date().timeIntervalSince(lastUpdate) < 86400 { return }
        refreshing = true
        defer {
            refreshing = false
            if pendingRefresh { pendingRefresh = false; Task { await self.refreshIfNeeded(force: true) } }
        }
        _ = await prepare()
        let options = PreferencesStorage.load(), sources = options.sources.filter(\.enabled)
        var texts: [String] = [], errors: [String] = []
        let cacheDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FilterSourceCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        for source in sources {
            do {
                let text = try await FilterDownloader.fetch(source)
                let conversion = try await Task.detached { try DomainFilterConverter.convert(text) }.value
                texts.append(text); sourceStatus[source.id] = "\(conversion.domainCount) Regeln"
                try? text.write(to: cacheDirectory.appendingPathComponent(source.id.uuidString + ".txt"), atomically: true, encoding: .utf8)
            } catch {
                sourceStatus[source.id] = error.localizedDescription; errors.append(source.title)
                if let cached = try? String(contentsOf: cacheDirectory.appendingPathComponent(source.id.uuidString + ".txt"), encoding: .utf8), (try? DomainFilterConverter.convert(cached)) != nil {
                    texts.append(cached); sourceStatus[source.id] = "Gespeicherte Regeln; " + error.localizedDescription
                }
            }
        }
        // Preserve existing good lists if any requested source cannot be represented.
        // Compile every currently enabled source that validated. Disabled/removed
        // sources must not remain applied merely because another source failed.
        do {
            let text = texts.joined(separator: "\n")
            let report = try await Task.detached { try DomainFilterConverter.convert(text) }.value
            let compiled = try await compile(report)
            if PreferencesStorage.load().sources.filter(\.enabled) != sources {
                compiled.forEach { WKContentRuleListStore.default()?.removeContentRuleList(forIdentifier: $0.identifier, completionHandler: { _ in }) }
                pendingRefresh = true; return
            }
            let oldIDs = lists.map(\.identifier)
            lists = compiled; revision = UUID(); ruleCount = report.domainCount
            if errors.isEmpty { lastUpdate = .now }
            UserDefaults.standard.set(compiled.map(\.identifier), forKey: "filterListIDsV3")
            if errors.isEmpty { UserDefaults.standard.set(lastUpdate, forKey: "filterUpdatedAtV2") }
            status = "\(report.domainCount) Regeln in \(compiled.count) Listen; \(report.skippedCount) nicht unterstützte Blockregeln"
            if !errors.isEmpty { status += "; Quellenfehler: " + errors.joined(separator: ", ") }
            for client in clients.values where client.enabled { install(on: client) }
            clients = clients.filter { $0.value.view != nil }
            for id in oldIDs { WKContentRuleListStore.default()?.removeContentRuleList(forIdentifier: id, completionHandler: { _ in }) }
        } catch { status = "Vorheriger/Basisfilter bleibt aktiv: \(error.localizedDescription)" }
    }
    func importRules(_ text: String, title: String) throws -> FilterSource {
        guard text.utf8.count <= 12_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
        _ = try DomainFilterConverter.convert(text)
        let name = UUID().uuidString + ".txt"
        try FileManager.default.createDirectory(at: FilterDownloader.importDirectory, withIntermediateDirectories: true)
        try text.write(to: FilterDownloader.importDirectory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        return FilterSource(title: title, address: "", localFile: name)
    }
    private func install(on client: Client) {
        guard !lists.isEmpty, let view = client.view, client.revision != revision else { return }
        view.configuration.userContentController.removeAllContentRuleLists()
        lists.forEach { view.configuration.userContentController.add($0) }; client.revision = revision
    }
    private func lookup(_ id: String) async -> WKContentRuleList? {
        guard let store = WKContentRuleListStore.default() else { return nil }
        return await withCheckedContinuation { continuation in store.lookUpContentRuleList(forIdentifier: id) { list, _ in continuation.resume(returning: list) } }
    }
    private func compile(_ report: FilterConversion) async throws -> [WKContentRuleList] {
        guard let store = WKContentRuleListStore.default() else { throw URLError(.cannotCreateFile) }
        var result: [WKContentRuleList] = []
        do { for (index, json) in report.jsons.enumerated() {
            let id = "webkweb-v2-\(UUID().uuidString)-\(index)"
            let list: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
                store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) { list, error in
                    if let list { continuation.resume(returning: list) } else { continuation.resume(throwing: error ?? URLError(.cannotParseResponse)) }
                }
            }
            result.append(list)
        } } catch {
            result.forEach { store.removeContentRuleList(forIdentifier: $0.identifier, completionHandler: { _ in }) }; throw error
        }
        return result
    }
}

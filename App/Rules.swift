import Foundation
import WebKit

struct FilterConversion: Sendable {
    let json: String
    let domainCount: Int
    let skippedCount: Int
}

// Non-actor async work runs off the UI executor. Even a large downloaded list
// must not freeze page navigation while it is parsed and converted.
private enum FilterDownloader {
    static func fetch() async throws -> FilterConversion {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt")!
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.expectedContentLength <= 8_000_000 else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 8_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
        return try DomainFilterConverter.convert(text)
    }
}

enum FilterError: LocalizedError {
    case unsupportedException
    case emptyList

    var errorDescription: String? {
        switch self {
        case .unsupportedException: return "Die Liste enthält Ausnahmen, die WebKWeb nicht sicher abbilden kann."
        case .emptyList: return "Die Liste enthält keine unterstützten Domainregeln."
        }
    }
}

/// Converts a conservative network-only subset of AdGuard / EasyList syntax.
/// Cosmetic filters, scriptlets, regexes, redirects and option-bearing block
/// rules are never reinterpreted. Whitelist suffixes are intentionally broader
/// than their source scope. Any unparseable exception rejects the source.
enum DomainFilterConverter {
    static let baseline = "||doubleclick.net^\n||googlesyndication.com^\n||googleadservices.com^"

    static func convert(_ text: String) throws -> FilterConversion {
        var blocks = Set<String>()
        var exceptionFilters = Set<String>()
        var skipped = 0
        for line in text.components(separatedBy: .newlines) {
            let rule = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if rule.isEmpty || rule.hasPrefix("!") || rule.hasPrefix("[") { continue }
            if rule.hasPrefix("@@") {
                exceptionFilters.formUnion(try exceptionFiltersForRule(String(rule.dropFirst(2))))
                continue
            }
            guard rule.hasPrefix("||"), rule.hasSuffix("^"),
                  let domain = normalizedDomain(String(rule.dropFirst(2).dropLast())) else {
                skipped += 1
                continue
            }
            blocks.insert(domain)
        }
        let domains = blocks.sorted()
        guard !domains.isEmpty else { throw FilterError.emptyList }
        // Reserve room for the specific YouTube endpoints below.
        let selected = Array(domains.prefix(15_000))
        var rules: [[String: Any]] = selected.map { domain in
            ["trigger": ["url-filter": "^https?://([^/:]+\\.)?" + domain.replacingOccurrences(of: ".", with: "\\.") + "[:/]"],
             "action": ["type": "block"]]
        }
        // WebKit's regex grammar has no disjunction: use individual rules.
        for endpoint in ["pagead/", "api/stats/ads"] {
            rules.append(["trigger": ["url-filter": "^https?://([^/:]+\\.)?youtube\\.com/" + endpoint],
                          "action": ["type": "block"]])
        }
        // Allow actions are last. Narrow resource/domain options from the source
        // are omitted only in this direction, expanding rather than losing an exemption.
        for filter in exceptionFilters.sorted() {
            rules.append(["trigger": ["url-filter": filter], "action": ["type": "ignore-previous-rules"]])
        }
        let json = String(decoding: try JSONSerialization.data(withJSONObject: rules), as: UTF8.self)
        return FilterConversion(json: json, domainCount: selected.count,
                                skippedCount: skipped + max(0, domains.count - selected.count))
    }

    private static func exceptionFiltersForRule(_ exception: String) throws -> [String] {
        if exception.hasPrefix("/"), exception.hasSuffix("/"), exception.count <= 1000 {
            let pattern = String(exception.dropFirst().dropLast())
            // The current AdGuard DNS export includes this image exception.
            // Widen it to four extension matches instead of discarding it or
            // feeding unsupported alternation into WebKit's compiler.
            let imageException = #"\.(gif|jpe?g|png|webp)#(\/?.+)?(\/(ad)s?\/|\/ad-)"#
            if pattern == imageException { return ["\\.gif", "\\.jpe?g", "\\.png", "\\.webp"] }
            // WebKit supports a limited regex grammar. More advanced constructs
            // reject the source; compilation also validates the final grammar.
            guard !pattern.isEmpty, !pattern.contains("|"), !pattern.contains("(?"), !pattern.contains("{"),
                  !pattern.contains("}"), !pattern.contains("\\1"),
                  (try? NSRegularExpression(pattern: pattern)) != nil else { throw FilterError.unsupportedException }
            return [pattern]
        }
        let value = exception.components(separatedBy: "$").first ?? exception
        guard let caret = value.firstIndex(of: "^"),
              value[value.index(after: caret)...].isEmpty || value[value.index(after: caret)...] == "|" else {
            throw FilterError.unsupportedException
        }
        var pattern = String(value[..<caret])
        while pattern.hasPrefix("|") { pattern.removeFirst() }
        guard pattern.unicodeScalars.allSatisfy({
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-*").contains($0)
        }) else { throw FilterError.unsupportedException }
        // A fixed DNS suffix also covers single-anchor and wildcard whitelist
        // entries. Match it anywhere in the URL to conservatively widen scope.
        if let star = pattern.lastIndex(of: "*") { pattern = String(pattern[pattern.index(after: star)...]) }
        while pattern.hasPrefix(".") { pattern.removeFirst() }
        if normalizedDomain(pattern) == nil, let dot = pattern.firstIndex(of: ".") {
            pattern = String(pattern[pattern.index(after: dot)...])
        }
        guard let suffix = normalizedDomain(pattern) else { throw FilterError.unsupportedException }
        return [suffix.replacingOccurrences(of: ".", with: "\\.")]
    }

    private static func normalizedDomain(_ value: String) -> String? {
        let domain = value.lowercased()
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard domain.utf8.count <= 253, labels.count >= 2,
              labels.allSatisfy({ label in
                  !label.isEmpty && label.utf8.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-") &&
                  label.unicodeScalars.allSatisfy({
                      CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-").contains($0)
                  })
              }) else { return nil }
        return domain
    }
}

@MainActor
final class RuleStore: ObservableObject {
    static let shared = RuleStore()
    @Published private(set) var status = "Basisfilter wird vorbereitet …"
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var ruleCount = 3
    @Published private(set) var refreshing = false

    private final class Client {
        weak var view: WKWebView?
        var enabled: Bool
        var appliedIdentifier: String?
        init(view: WKWebView, enabled: Bool) { self.view = view; self.enabled = enabled }
    }
    private var clients: [UUID: Client] = [:]
    private var currentList: WKContentRuleList?
    private var initialTask: Task<WKContentRuleList?, Never>?
    private let identifier = "webkweb-domain-filter-v1"
    private let updatedKey = "filterUpdatedAt"

    private init() {
        lastUpdate = UserDefaults.standard.object(forKey: updatedKey) as? Date
    }

    func apply(to view: WKWebView, tabID: UUID, enabled: Bool) async {
        let client = clients[tabID] ?? Client(view: view, enabled: enabled)
        client.enabled = enabled
        clients[tabID] = client
        if !enabled {
            view.configuration.userContentController.removeAllContentRuleLists()
            client.appliedIdentifier = nil
            return
        }
        _ = await prepare()
        // Re-read desired state after suspension: a later disable must win,
        // while a later re-enable remains eligible for the compiled list.
        guard clients[tabID] === client, client.enabled, let list = currentList else { return }
        install(list, on: client)
    }

    func unregister(_ tabID: UUID) { clients.removeValue(forKey: tabID) }

    func hasAppliedRules(to tabID: UUID) -> Bool {
        clients[tabID]?.appliedIdentifier != nil
    }

    func prepare() async -> WKContentRuleList? {
        if let currentList { return currentList }
        if initialTask == nil {
            initialTask = Task { [weak self] in
                guard let self else { return nil }
                if let cached = await self.lookup() { return cached }
                guard let report = try? DomainFilterConverter.convert(DomainFilterConverter.baseline) else { return nil }
                return await self.compile(report.json)
            }
        }
        let result = await initialTask?.value
        if currentList == nil {
            currentList = result
            status = result == nil ? "Filter konnte nicht geladen werden." : "Netzwerkfilter aktiv"
        }
        return currentList
    }

    func refreshIfNeeded(force: Bool = false) async {
        guard !refreshing else { return }
        if !force, let lastUpdate, Date().timeIntervalSince(lastUpdate) < 24 * 3600 { return }
        refreshing = true
        defer { refreshing = false }
        _ = await prepare()
        do {
            let report = try await FilterDownloader.fetch()
            guard let list = await compile(report.json) else { throw URLError(.cannotParseResponse) }
            currentList = list
            ruleCount = report.domainCount
            lastUpdate = .now
            UserDefaults.standard.set(lastUpdate, forKey: updatedKey)
            status = "\(report.domainCount) Domainregeln; \(report.skippedCount) Einträge ausgelassen"
            // A refresh uses the same stable WebKit identifier but a new object.
            for client in clients.values where client.enabled {
                client.appliedIdentifier = nil
                install(list, on: client)
            }
            clients = clients.filter { $0.value.view != nil }
        } catch {
            status = "Gespeicherter/Basisfilter aktiv. Update fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func install(_ list: WKContentRuleList, on client: Client) {
        guard let view = client.view, client.appliedIdentifier != list.identifier else { return }
        view.configuration.userContentController.removeAllContentRuleLists()
        view.configuration.userContentController.add(list)
        client.appliedIdentifier = list.identifier
    }

    private func lookup() async -> WKContentRuleList? {
        guard let store = WKContentRuleListStore.default() else { return nil }
        return await withCheckedContinuation { continuation in
            store.lookUpContentRuleList(forIdentifier: identifier) { list, _ in continuation.resume(returning: list) }
        }
    }

    private func compile(_ json: String) async -> WKContentRuleList? {
        guard let store = WKContentRuleListStore.default() else { return nil }
        return await withCheckedContinuation { continuation in
            store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { list, _ in
                continuation.resume(returning: list)
            }
        }
    }
}

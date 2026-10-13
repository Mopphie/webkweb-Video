import SwiftUI
import WebKit
import Combine

@MainActor
private final class WeakPlaybackHandler: NSObject, WKScriptMessageHandler {
    weak var tab: BrowserTab?
    init(_ tab: BrowserTab) { self.tab = tab }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        tab?.receive(message)
    }
}

@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    static let world = WKContentWorld.world(name: "WebKWebPlayback")
    let id = UUID()
    let webView: WKWebView
    weak var browser: BrowserModel?
    @Published var title = "Neuer Tab"
    @Published var address = ""
    @Published var loading = false
    @Published var progress = 0.0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var error: String?
    @Published var hasMedia = false
    @Published var playing = false
    @Published var playbackTime = 0.0
    @Published var duration: Double?
    @Published var directMedia: DirectMedia?
    @Published var sponsorStatus = ""

    private var observations: [NSKeyValueObservation] = []
    private var frames: [String: WKFrameInfo] = [:]
    private struct MediaState {
        let frame: WKFrameInfo
        let playing: Bool
        let time: Double
        let duration: Double?
        let directMedia: DirectMedia?
    }
    private var frameMedia: [String: MediaState] = [:]
    private var activeMediaFrame: WKFrameInfo?
    private var sponsorTask: Task<Void, Never>?
    private var sponsorID: String?
    private var openTask: Task<Void, Never>?
    private var visitWork: DispatchWorkItem?
    private var alive = true

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        if let url = Bundle.main.url(forResource: "Playback", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            config.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd,
                forMainFrameOnly: false, in: Self.world))
        }
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        config.userContentController.add(WeakPlaybackHandler(self), contentWorld: Self.world, name: "playback")
        observations = [
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.loading = view.isLoading }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.progress = view.estimatedProgress }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoForward = view.canGoForward }
            },
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.address = view.url?.absoluteString ?? ""
                    self.refreshSponsorBlock()
                }
            }
        ]
    }

    func load(_ url: URL) {
        error = nil
        openTask?.cancel()
        openTask = Task { [weak self] in
            guard let self else { return }
            await RuleStore.shared.apply(to: self.webView, tabID: self.id, enabled: self.browser?.blockingEnabled ?? true)
            guard !Task.isCancelled, self.alive else { return }
            self.webView.load(URLRequest(url: url))
        }
    }

    func run(_ script: String, allFrames: Bool = false) {
        guard alive else { return }
        webView.evaluateJavaScript(script, in: nil, in: Self.world, completionHandler: nil)
        if allFrames {
            for frame in frames.values where !frame.isMainFrame {
                webView.evaluateJavaScript(script, in: frame, in: Self.world, completionHandler: nil)
            }
        }
    }

    func runMedia(_ script: String) {
        guard alive else { return }
        webView.evaluateJavaScript(script, in: activeMediaFrame, in: Self.world, completionHandler: nil)
    }

    func close() {
        run("globalThis.__webkweb?.pause(true)", allFrames: true)
        alive = false
        openTask?.cancel()
        sponsorTask?.cancel()
        visitWork?.cancel()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "playback", contentWorld: Self.world)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        observations.removeAll()
        frames.removeAll()
        frameMedia.removeAll()
        activeMediaFrame = nil
        RuleStore.shared.unregister(id)
    }

    func setSponsorBlock(_ enabled: Bool) {
        run("globalThis.__webkweb?.setSponsorBlock(\(enabled ? "true" : "false"))")
        sponsorID = nil
        refreshSponsorBlock()
    }

    private func refreshSponsorBlock() {
        let id = YouTubeAddress.videoID(in: webView.url)
        guard browser?.sponsorBlockEnabled == true, let id else {
            sponsorTask?.cancel()
            sponsorID = nil
            sponsorStatus = ""
            run("globalThis.__webkweb?.setSponsorBlock(false)")
            return
        }
        guard sponsorID != id else { return }
        sponsorID = id
        sponsorTask?.cancel()
        sponsorStatus = "SponsorBlock lädt …"
        run("globalThis.__webkweb?.setSponsorBlock(true)")
        sponsorTask = Task { [weak self] in
            do {
                let segments = try await SponsorBlockService.shared.segments(for: id)
                guard let self, !Task.isCancelled, self.alive, self.browser?.sponsorBlockEnabled == true,
                      self.sponsorID == id, YouTubeAddress.videoID(in: self.webView.url) == id else { return }
                let json = String(decoding: try JSONEncoder().encode(segments), as: UTF8.self)
                // Native parsing restricts id to 11 ASCII URL-safe characters.
                self.run("globalThis.__webkweb?.setSegments('\(id)', \(json))")
                self.sponsorStatus = segments.isEmpty ? "Keine Skip-Segmente" : "\(segments.count) Skip-Segmente"
            } catch {
                guard let self, !Task.isCancelled, self.sponsorID == id else { return }
                self.sponsorStatus = "SponsorBlock nicht erreichbar"
            }
        }
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard alive, message.name == "playback", let body = message.body as? [String: Any],
              let kind = body["kind"] as? String else { return }
        switch kind {
        case "ready":
            // Retain frame info only for this document; it permits pause/seek on
            // cross-origin embedded players without modifying their page world.
            let key = frameKey(message.frameInfo)
            if frames[key] != nil || frames.count < 32 { frames[key] = message.frameInfo }
            webView.evaluateJavaScript("globalThis.__webkweb?.setSponsorBlock(false)",
                in: message.frameInfo, in: Self.world, completionHandler: nil)
            if browser?.playbackStopped == true {
                webView.evaluateJavaScript("globalThis.__webkweb?.pause(true)",
                    in: message.frameInfo, in: Self.world, completionHandler: nil)
            }
        case "navigation":
            guard message.frameInfo.isMainFrame,
                  let value = body["address"] as? String, value.utf8.count < 16_384,
                  let url = URL(string: value), ["http", "https"].contains(url.scheme ?? ""),
                  url.host == message.frameInfo.securityOrigin.host else { return }
            address = value
            sponsorID = nil
            refreshSponsorBlock()
            scheduleVisit()
        case "state":
            let key = frameKey(message.frameInfo)
            let frameHasMedia = body["hasMedia"] as? Bool ?? false
            let framePlaying = body["playing"] as? Bool ?? false
            if frameHasMedia && (frameMedia[key] != nil || frameMedia.count < 32) {
                frameMedia[key] = MediaState(frame: message.frameInfo, playing: framePlaying,
                    time: (body["time"] as? Double).flatMap { $0.isFinite ? $0 : nil } ?? 0,
                    duration: (body["duration"] as? Double).flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
                    directMedia: DirectMedia(source: body["source"] as? String ?? "",
                        contentType: body["contentType"] as? String, encrypted: body["encrypted"] as? Bool ?? false))
            } else if !frameHasMedia {
                frameMedia.removeValue(forKey: key)
            }
            let active = frameMedia.values.first { $0.playing } ?? frameMedia["main"] ?? frameMedia.values.first
            hasMedia = active != nil
            playing = active?.playing ?? false
            playbackTime = active?.time ?? 0
            duration = active?.duration
            directMedia = active?.directMedia
            activeMediaFrame = active?.frame
            if message.frameInfo.isMainFrame, let title = body["title"] as? String, !title.isEmpty {
                self.title = String(title.prefix(300))
            }
        case "ended":
            guard let eventID = body["eventID"] as? String, eventID.count < 200 else { return }
            browser?.ended(in: id, eventID: eventID)
        case "notice":
            if let text = body["text"] as? String { browser?.notice = String(text.prefix(300)) }
        default: break
        }
    }

    private func frameKey(_ frame: WKFrameInfo) -> String {
        frame.isMainFrame ? "main" : (frame.request.url?.absoluteString ?? frame.securityOrigin.host)
    }

    private func scheduleVisit() {
        visitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.browser?.recordVisit(self) }
        }
        visitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        frames.removeAll()
        frameMedia.removeAll()
        activeMediaFrame = nil
        sponsorTask?.cancel()
        sponsorID = nil
        hasMedia = false
        playing = false
        directMedia = nil
        error = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        title = webView.title ?? webView.url?.host ?? "Video"
        address = webView.url?.absoluteString ?? ""
        sponsorID = nil
        refreshSponsorBlock()
        if browser?.playbackStopped == true { run("globalThis.__webkweb?.pause(true)", allFrames: true) }
        browser?.recordVisit(self)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error) }
    private func report(_ error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { self.error = error.localizedDescription }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        error = "Die Webseite wurde von iOS beendet. Lade sie erneut."
        hasMedia = false
        playing = false
        directMedia = nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        if ["http", "https", "about"].contains(scheme) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            // External apps open only after an explicit tap, never from a script.
            if action.navigationType == .linkActivated, ["mailto", "tel"].contains(scheme),
               UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard action.targetFrame == nil, let url = action.request.url,
              ["http", "https"].contains(url.scheme ?? ""), let browser else { return nil }
        let tab = browser.addTab()
        tab.load(url)
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        browser?.notice = String(message.prefix(500))
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        browser?.confirm = BrowserConfirmation(message: String(message.prefix(500)), completion: completionHandler)
    }
}

struct BrowserConfirmation {
    let message: String
    let completion: (Bool) -> Void
}

@MainActor
final class BrowserModel: ObservableObject {
    @Published private(set) var tabs: [BrowserTab]
    @Published var selectedID: UUID
    @Published var notice: String?
    @Published var confirm: BrowserConfirmation?
    @Published private(set) var sleepPlan = SleepPlan()
    @Published private(set) var playbackStopped = false
    @Published var gesturesEnabled = false
    @Published var sponsorBlockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(sponsorBlockEnabled, forKey: "sponsorBlockEnabled")
            tabs.forEach { $0.setSponsorBlock(sponsorBlockEnabled) }
        }
    }
    @Published var blockingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(blockingEnabled, forKey: "blockingEnabled")
            for tab in tabs {
                Task { await RuleStore.shared.apply(to: tab.webView, tabID: tab.id, enabled: blockingEnabled) }
            }
        }
    }
    var onVisit: ((String, String) -> Void)?
    private var timer: Timer?

    init() {
        let tab = BrowserTab()
        tabs = [tab]
        selectedID = tab.id
        sponsorBlockEnabled = UserDefaults.standard.bool(forKey: "sponsorBlockEnabled")
        blockingEnabled = UserDefaults.standard.object(forKey: "blockingEnabled") as? Bool ?? true
        tab.browser = self
    }

    var current: BrowserTab { tabs.first { $0.id == selectedID } ?? tabs[0] }

    func open(_ input: String) {
        guard let url = AddressResolver.resolve(input) else { return }
        guard UIApplication.shared.canOpenURL(url) else {
            current.error = "Diese Adresse kann nicht geöffnet werden."
            return
        }
        playbackStopped = false
        current.load(url)
    }

    @discardableResult
    func addTab() -> BrowserTab {
        let tab = BrowserTab()
        tab.browser = self
        tabs.append(tab)
        selectedID = tab.id
        return tab
    }

    func close(_ id: UUID) {
        tabs.first { $0.id == id }?.close()
        tabs.removeAll { $0.id == id }
        if sleepPlan.tabID == id { cancelSleep() }
        if tabs.isEmpty { addTab() }
        if !tabs.contains(where: { $0.id == selectedID }) { selectedID = tabs[0].id }
    }

    func togglePlayback() {
        playbackStopped = false
        current.runMedia("globalThis.__webkweb?.toggle()")
    }

    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        current.runMedia("globalThis.__webkweb?.seek(\(max(-120, min(120, seconds))))")
    }

    func pauseAll(blockAutoplay: Bool = false) {
        playbackStopped = blockAutoplay
        tabs.forEach { $0.run("globalThis.__webkweb?.pause(\(blockAutoplay ? "true" : "false"))", allFrames: true) }
        CastService.shared.pause()
    }

    func sleep(minutes: Int) {
        cancelSleep()
        sleepPlan.arm(minutes: minutes)
        startTimer()
    }

    func sleep(videos: Int) {
        cancelSleep()
        sleepPlan.arm(videos: videos, tabID: current.id)
    }

    func cancelSleep() {
        timer?.invalidate()
        timer = nil
        sleepPlan.cancel()
    }

    func enforceSleepDeadline() {
        if sleepPlan.hasExpired() { finishSleep() }
    }

    func ended(in tabID: UUID, eventID: String) {
        if sleepPlan.ended(in: tabID, eventID: eventID) { finishSleep() }
    }

    private func finishSleep() {
        pauseAll(blockAutoplay: true)
        cancelSleep()
        notice = "Sleep-Timer: Wiedergabe pausiert."
    }

    private func startTimer() {
        let value = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.enforceSleepDeadline() }
        }
        RunLoop.main.add(value, forMode: .common)
        timer = value
    }

    func recordVisit(_ tab: BrowserTab) {
        guard let url = URL(string: tab.address), ["http", "https"].contains(url.scheme ?? ""),
              url.host != nil else { return }
        onVisit?(tab.title, tab.address)
    }
}

import SwiftUI
import WebKit
import Combine

@MainActor
private final class WeakPlaybackHandler: NSObject, WKScriptMessageHandler {
    weak var tab: BrowserTab?
    init(_ tab: BrowserTab) { self.tab = tab }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) { tab?.receive(message) }
}

struct BrowserDialog: Identifiable {
    enum Kind { case alert, confirm, prompt }
    let id = UUID()
    let tabID: UUID
    let kind: Kind
    let message: String
    let defaultText: String
    let reply: (String?) -> Void
}

@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    static let world = WKContentWorld.world(name: "WebKWebPlayback")
    let id: UUID
    let isPrivate: Bool
    private(set) var webView: WKWebView
    weak var browser: BrowserModel?
    @Published var title = "Neuer Tab"
    @Published var address = ""
    @Published var loading = false
    @Published var progress = 0.0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var error: String?
    @Published private(set) var watchPresentation = WatchPresentationState()
    @Published var hasMedia = false
    @Published var playing = false
    @Published private(set) var hasActivePlayback = false
    @Published var playbackTime = 0.0
    @Published var duration: Double?
    @Published var captions: [MediaTrack] = []
    @Published var audioTracks: [MediaTrack] = []
    @Published var playbackRate = 1.0
    @Published var resolution = ""
    @Published var waiting = false
    @Published var muted = false
    @Published var mediaError = ""
    @Published private(set) var activeMediaID = ""
    @Published private(set) var activeMediaKind = ""
    private var observations: [NSKeyValueObservation] = []
    private final class Frame {
        let id: String
        var info: WKFrameInfo
        var url: URL?
        var lastSeen: Date = .now
        var hasMedia = false, playing = false, anyPlaying = false
        var time = 0.0, priority = 0.0, interaction = 0.0
        var duration: Double?
        var mediaID = "", kind = ""
        var captions: [MediaTrack] = [], audioTracks: [MediaTrack] = []
        var rate = 1.0, resolution = "", waiting = false, muted = false, error = ""
        var queueManaged = false
        init(id: String, info: WKFrameInfo, url: URL?) { self.id = id; self.info = info; self.url = url }
    }
    private var frames: [String: Frame] = [:]
    private var activeFrameID: String?
    private var openTask: Task<Void, Never>?
    private var visitWork: DispatchWorkItem?
    private var lastRequestedURL: URL?
    private var alive = true
    private var wiping = false
    private var wipeContinuation: CheckedContinuation<Void, Error>?
    private var wipeNavigation: WKNavigation?
    private var requestedAutoplay = false, committedAutoplay = false
    private var autoplayNavigation: WKNavigation?
    private var backgroundOpening: Bool
    var sessionAddress: String { lastRequestedURL?.absoluteString ?? address }
    var presentsWatchImmersively: Bool { watchPresentation.isImmersive(at: URL(string: address)) }

    init(id: UUID = UUID(), isPrivate: Bool = false, configuration: WKWebViewConfiguration? = nil, background: Bool = false) {
        self.id = id; self.isPrivate = isPrivate; backgroundOpening = background
        let config = configuration ?? WKWebViewConfiguration()
        // Keep WebKit's popup configuration/opener, but not the opener's handler.
        config.userContentController = WKUserContentController()
        if configuration == nil { config.websiteDataStore = isPrivate ? .nonPersistent() : .default() }
        config.defaultWebpagePreferences.preferredContentMode = PreferencesStorage.load().desktop ? .desktop : .mobile
        config.allowsInlineMediaPlayback = true
        // A tab's initial background/restore state must not permanently change
        // WebKit's playback policy after the user selects or navigates that tab.
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        Self.installScripts(in: config.userContentController, startPaused: background)
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self; webView.uiDelegate = self
        config.userContentController.add(WeakPlaybackHandler(self), contentWorld: Self.world, name: "playback")
        if background { webView.setAllMediaPlaybackSuspended(true, completionHandler: nil) }
        applyAppearance()
        observations = [
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] view, _ in Task { @MainActor in self?.loading = view.isLoading } },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] view, _ in Task { @MainActor in self?.progress = view.estimatedProgress } },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in Task { @MainActor in self?.canGoBack = view.canGoBack } },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] view, _ in Task { @MainActor in self?.canGoForward = view.canGoForward } },
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in Task { @MainActor in
                guard let self, !self.wiping else { return }
                self.address = view.url?.scheme == "about" ? "" : (view.url?.absoluteString ?? "")
                self.syncWatchPresentation()
            } }
        ]
    }
    private static func installScripts(in controller: WKUserContentController, startPaused: Bool) {
        controller.removeAllUserScripts()
        if startPaused {
            controller.addUserScript(WKUserScript(source: "globalThis.__webkwebStartPaused = true", injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world))
        }
        for (name, mainOnly) in [("Playback", false), ("WatchPresentation", true)] {
            if let url = Bundle.main.url(forResource: name, withExtension: "js"), let source = try? String(contentsOf: url, encoding: .utf8) {
                controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: mainOnly, in: world))
            }
        }
    }
    func prepareForPlayback() {
        guard backgroundOpening else { return }
        backgroundOpening = false
        // Only future documents lose the bootstrap. The current paused document
        // still needs a real website Play gesture or the explicit native Play.
        Self.installScripts(in: webView.configuration.userContentController, startPaused: false)
        webView.setAllMediaPlaybackSuspended(false, completionHandler: nil)
    }
    func applyAppearance() {
        // WebKit supplies the real current engine, OS and device identity.
        // Desktop/mobile preference is applied to each navigation below.
        webView.customUserAgent = nil
        webView.pageZoom = browser?.options.zoom ?? PreferencesStorage.load().zoom
    }
    func applyPlaybackOptions() {
        guard let browser else { return }
        run("globalThis.__webkweb?.setOptions({autoPiP:\(browser.options.autoPiP ? "true" : "false"),hideShorts:\(browser.options.hideShorts ? "true" : "false"),preferOriginal:\(browser.options.preferOriginalAudio ? "true" : "false")})", allFrames: true)
        run("globalThis.__webkweb?.setBackground(\(browser.selectedID == id ? "false" : "true"))", allFrames: true)
        if backgroundOpening {
            run("globalThis.__webkweb?.pause(true)", allFrames: true)
        }
    }
    func attemptAutoPiP() { guard browser?.options.autoPiP == true, browser?.playbackStopped == false, playing else { return }; runMedia("globalThis.__webkweb?.autoPiP()") }
    func cancelAutoplay() { requestedAutoplay = false; committedAutoplay = false; autoplayNavigation = nil }
    private func attemptAutoplay() {
        guard committedAutoplay, hasMedia else { return }
        cancelAutoplay()
        guard browser?.playbackStopped == false else { return }
        runMedia("globalThis.__webkweb?.resume()")
    }
    func load(_ url: URL, autoplay: Bool = false, userInitiated: Bool = false) {
        guard !wiping, browser?.wipingData != true else { return }
        if autoplay || userInitiated { prepareForPlayback() }
        requestedAutoplay = autoplay; committedAutoplay = false; autoplayNavigation = nil
        run("globalThis.__webkweb?.pause(true)", allFrames: true)
        lastRequestedURL = url; error = nil; openTask?.cancel()
        openTask = Task { [weak self] in
            guard let self else { return }
            await RuleStore.shared.apply(to: self.webView, tabID: self.id, enabled: self.browser?.shouldBlock(url) ?? true)
            guard !Task.isCancelled, self.alive, !self.wiping else { return }
            let navigation = self.webView.load(URLRequest(url: url))
            self.autoplayNavigation = self.requestedAutoplay ? navigation : nil
        }
    }
    func reload() { if let url = lastRequestedURL ?? webView.url { load(url, userInitiated: true) } }
    func showNormalWebsite() {
        watchPresentation.dismiss(at: URL(string: address))
        syncWatchPresentation()
    }
    func showWatchPresentation() { watchPresentation.show(); syncWatchPresentation() }
    private func syncWatchPresentation() {
        run("globalThis.__webkwebWatch?.setImmersive(\(presentsWatchImmersively ? "true" : "false"))")
    }
    func leaveWatch() {
        guard browser?.wipingData != true else { return }
        showNormalWebsite()
        browser?.commandRevision += 1
        if browser?.queueTabID == id { browser?.detachQueue() }
        let previous = webView.backForwardList.backItem?.url
        let destination = WatchPresentationState.exitURL(previous: previous)
        if let previous, previous == destination, webView.canGoBack { webView.goBack() }
        else { load(destination, userInitiated: true) }
    }
    func reloadWithoutFilter() {
        guard let url = lastRequestedURL ?? webView.url, let host = url.host?.lowercased(), let browser else { return }
        if !browser.options.allowlist.contains(host) { browser.options.allowlist.append(host) }
        reload()
    }
    func run(_ script: String, allFrames: Bool = false) {
        guard alive else { return }
        if allFrames {
            for frame in frames.values { evaluate(script, frame: frame) }
        } else if let main = frames.values.first(where: { $0.info.isMainFrame }) { evaluate(script, frame: main) }
    }
    func runMedia(_ script: String) {
        if let id = activeFrameID, let frame = frames[id] { evaluate(script, frame: frame) }
        else { run(script) }
    }
    private func evaluate(_ script: String, frame: Frame) {
        webView.evaluateJavaScript(script, in: frame.info, in: Self.world) { [weak self] result in
            guard case .failure(let error) = result, (error as? WKError)?.code == .javaScriptInvalidFrameTarget else { return }
            Task { @MainActor in self?.removeFrame(frame.id) }
        }
    }
    func close() {
        run("globalThis.__webkweb?.pause(true)", allFrames: true)
        alive = false; openTask?.cancel(); visitWork?.cancel(); clearFrames(); finishBlank(URLError(.cancelled))
        webView.stopLoading(); webView.configuration.userContentController.removeScriptMessageHandler(forName: "playback", contentWorld: Self.world)
        webView.navigationDelegate = nil; webView.uiDelegate = nil; observations.removeAll()
        RuleStore.shared.unregister(id); browser?.cancelDialogs(for: id)
    }
    func cancelPendingLoad() { openTask?.cancel(); openTask = nil; visitWork?.cancel(); webView.stopLoading() }
    func prepareForWipe() async throws {
        wiping = true; openTask?.cancel(); openTask = nil; visitWork?.cancel()
        run("globalThis.__webkweb?.pause(true)", allFrames: true)
        clearFrames(); webView.stopLoading(); browser?.cancelDialogs(for: id)
        try await withCheckedThrowingContinuation { continuation in
            wipeContinuation = continuation
            wipeNavigation = webView.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: nil)
            if wipeNavigation == nil { finishBlank(URLError(.cannotLoadFromNetwork)) }
            let expectedNavigation = wipeNavigation
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, self.wipeContinuation != nil, self.wipeNavigation === expectedNavigation else { return }
                self.webView.stopLoading(); self.finishBlank(URLError(.timedOut))
            }
        }
    }
    private func finishBlank(_ error: Error? = nil) {
        guard let continuation = wipeContinuation else { return }
        wipeContinuation = nil; wipeNavigation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
    func finishWipe() {
        wiping = false; address = ""; title = isPrivate ? "Privater Tab" : "Neuer Tab"; lastRequestedURL = nil; error = nil
    }
    fileprivate func receive(_ message: WKScriptMessage) {
        guard alive, !wiping, message.name == "playback", let body = message.body as? [String: Any],
              let kind = body["kind"] as? String, let documentID = body["documentID"] as? String,
              !documentID.isEmpty, documentID.count < 100 else { return }
        let value = body["address"] as? String ?? ""
        let url = URL(string: value)
        if let url, url.scheme != "about", url.host != message.frameInfo.securityOrigin.host { return }
        if kind == "ready" {
            if frames[documentID] == nil { frames[documentID] = Frame(id: documentID, info: message.frameInfo, url: url) }
            if browser?.playbackStopped == true { evaluate("globalThis.__webkweb?.pause(true)", frame: frames[documentID]!) }
            applyPlaybackOptions()
            syncWatchPresentation()
        }
        guard let frame = frames[documentID] else { return }
        frame.lastSeen = .now; frame.info = message.frameInfo
        switch kind {
        case "ready": break
        case "dispose": removeFrame(documentID)
        case "navigation":
            frame.url = url
            if message.frameInfo.isMainFrame, let url, ["https", "http"].contains(url.scheme ?? "") {
                address = url.absoluteString; lastRequestedURL = url; syncWatchPresentation(); scheduleVisit()
            }
        case "userplay":
            guard let mediaID = body["mediaID"] as? String, mediaID.hasPrefix(documentID + ":") else { return }
            browser?.didStartFromWebsite(in: id)
        case "state":
            frame.url = url; frame.hasMedia = body["hasMedia"] as? Bool ?? false
            frame.playing = body["playing"] as? Bool ?? false
            frame.anyPlaying = body["anyPlaying"] as? Bool ?? frame.playing
            frame.time = finite(body["time"]) ?? 0; frame.duration = finite(body["duration"])
            frame.priority = finite(body["priority"]) ?? 0; frame.interaction = finite(body["interactionAt"]) ?? 0
            frame.mediaID = body["mediaID"] as? String ?? ""; frame.kind = body["mediaKind"] as? String ?? ""
            frame.captions = (body["captions"] as? [[String: Any]] ?? []).compactMap(MediaTrack.init)
            frame.audioTracks = (body["audioTracks"] as? [[String: Any]] ?? []).compactMap(MediaTrack.init)
            frame.rate = finite(body["rate"]) ?? 1; frame.waiting = body["waiting"] as? Bool ?? false
            frame.muted = body["muted"] as? Bool ?? false; frame.error = String((body["mediaError"] as? String ?? "").prefix(100))
            if let w = finite(body["width"]), let h = finite(body["height"]), w > 0, h > 0, w <= 65535, h <= 65535 { frame.resolution = "\(Int(w)) × \(Int(h))" } else { frame.resolution = "" }
            if message.frameInfo.isMainFrame, let title = body["title"] as? String, !title.isEmpty { self.title = String(title.prefix(300)) }
            updateMedia(); attemptAutoplay()
        case "ended":
            guard body["primary"] as? Bool == true, body["mediaKind"] as? String == "video",
                  activeFrameID == documentID, let mediaID = body["mediaID"] as? String, mediaID == activeMediaID,
                  let eventID = body["eventID"] as? String, eventID.count < 200 else { return }
            browser?.ended(in: id, eventID: eventID, mediaID: mediaID)
        case "queueended":
            guard body["primary"] as? Bool == true, activeFrameID == documentID,
                  let mediaID = body["mediaID"] as? String, mediaID == activeMediaID,
                  let eventID = body["eventID"] as? String, eventID.count < 200 else { return }
            let encodedID = String(decoding: (try? JSONEncoder().encode(mediaID)) ?? Data("null".utf8), as: UTF8.self)
            browser?.queueEnded(in: id, eventID: eventID, repeatPlayback: { [weak self] in self?.evaluate("globalThis.__webkweb?.restart(\(encodedID))", frame: frame) })
        case "notice": if let text = body["text"] as? String { browser?.notice = String(text.prefix(300)) }
        default: break
        }
    }
    private func finite(_ value: Any?) -> Double? { (value as? Double).flatMap { $0.isFinite ? $0 : nil } }
    private func updateMedia() {
        let recent = frames.values.filter { $0.hasMedia && Date().timeIntervalSince($0.lastSeen) < 15 }
        let active = recent.sorted { a,b in
            if a.interaction != b.interaction { return a.interaction > b.interaction }
            if a.priority != b.priority { return a.priority > b.priority }
            return a.playing && !b.playing
        }.first
        activeFrameID = active?.id; hasMedia = active != nil; playing = active?.playing ?? false
        hasActivePlayback = frames.values.contains { $0.anyPlaying }
        for frame in frames.values {
            let managed = browser?.queueTabID == id && frame.id == activeFrameID
            if frame.queueManaged != managed { frame.queueManaged = managed; evaluate("globalThis.__webkweb?.setQueueManaged(\(managed ? "true" : "false"))", frame: frame) }
        }
        playbackTime = active?.time ?? 0; duration = active?.duration
        activeMediaID = active?.mediaID ?? ""; activeMediaKind = active?.kind ?? ""
        captions = active?.captions ?? []; audioTracks = active?.audioTracks ?? []; playbackRate = active?.rate ?? 1
        resolution = active?.resolution ?? ""; waiting = active?.waiting ?? false; muted = active?.muted ?? false; mediaError = active?.error ?? ""
        browser?.publishNowPlaying()
    }
    private func removeFrame(_ id: String) { frames.removeValue(forKey: id); updateMedia() }
    private func clearFrames() { frames.removeAll(); updateMedia() }
    private func scheduleVisit() {
        visitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in Task { @MainActor in if let self, !self.wiping { self.browser?.recordVisit(self) } } }
        visitWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    func webView(_ view: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { clearFrames(); error = nil }
    func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
        if wiping { if navigation === wipeNavigation { finishBlank() }; return }
        guard view.url?.scheme != "about" else { return }
        title = view.title ?? view.url?.host ?? "Video"; address = view.url?.absoluteString ?? ""
        syncWatchPresentation()
        lastRequestedURL = view.url
        if browser?.playbackStopped == true { run("globalThis.__webkweb?.pause(true)", allFrames: true) }
        browser?.recordVisit(self)
        if let expected = autoplayNavigation, expected === navigation { committedAutoplay = requestedAutoplay; attemptAutoplay() }
    }
    func webView(_ view: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if wiping { if navigation === wipeNavigation { finishBlank(error) } } else { report(error) }
    }
    func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if wiping { if navigation === wipeNavigation { finishBlank(error) } } else { report(error) }
    }
    private func report(_ error: Error) { if (error as NSError).code != NSURLErrorCancelled { self.error = error.localizedDescription } }
    func webViewWebContentProcessDidTerminate(_ view: WKWebView) { clearFrames(); if wiping { finishBlank() } else { error = "Die Webseite wurde beendet. Lade sie erneut." } }
    func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        preferences.preferredContentMode = (browser?.options.desktop ?? PreferencesStorage.load().desktop) ? .desktop : .mobile
        webView(view, decidePolicyFor: action) { decisionHandler($0, preferences) }
    }
    func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, (!(wiping || browser?.wipingData == true) || url.scheme == "about") else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        if action.targetFrame?.isMainFrame == true, [.linkActivated, .backForward].contains(action.navigationType) { browser?.commandRevision += 1 }
        if action.targetFrame?.isMainFrame == true, [.linkActivated, .backForward].contains(action.navigationType), browser?.queueTabID == id { browser?.detachQueue() }
        if browser?.blocksShorts(url) == true {
            decisionHandler(.cancel)
            if action.targetFrame?.isMainFrame == true { browser?.notice = "Shorts sind ausgeschaltet." }
            return
        }
        if ["http", "https", "about"].contains(scheme) {
            if action.targetFrame?.isMainFrame == true, scheme != "about" {
                lastRequestedURL = url
                Task { [weak self] in
                    guard let self else { decisionHandler(.cancel); return }
                    await RuleStore.shared.apply(to: view, tabID: self.id, enabled: self.browser?.shouldBlock(url) ?? true)
                    decisionHandler(self.alive && !self.wiping && self.browser?.wipingData != true ? .allow : .cancel)
                }
            } else { decisionHandler(.allow) }
        } else {
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated, ["mailto", "tel"].contains(scheme), UIApplication.shared.canOpenURL(url) { UIApplication.shared.open(url) }
        }
    }
    func webView(_ view: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard action.targetFrame == nil, let browser, !browser.wipingData else { return nil }
        if let url = action.request.url, !["http", "https", "about"].contains(url.scheme ?? "") { return nil }
        return browser.addTab(isPrivate: isPrivate, configuration: configuration).webView
    }
    func webViewDidClose(_ webView: WKWebView) { browser?.close(id) }
    func webView(_ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo, completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
        guard let url = elementInfo.linkURL, AddressResolver.directURL(url.absoluteString) != nil else { completionHandler(nil); return }
        completionHandler(UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] suggested in
            var actions: [UIMenuElement] = suggested
            actions.append(UIAction(title: "Im Hintergrund öffnen", image: UIImage(systemName: "square.on.square")) { _ in
                Task { @MainActor in self?.browser?.openBackground(url.absoluteString, isPrivate: self?.isPrivate) }
            })
            if self?.isPrivate == false {
                actions.append(UIAction(title: "Zur Queue", image: UIImage(systemName: "text.badge.plus")) { _ in
                    Task { @MainActor in self?.browser?.enqueue(address: url.absoluteString, title: url.host ?? "Link") }
                })
            }
            return UIMenu(children: actions)
        })
    }
    func webView(_ view: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        browser?.enqueue(BrowserDialog(tabID: id, kind: .alert, message: String(message.prefix(500)), defaultText: "", reply: { _ in completionHandler() }))
    }
    func webView(_ view: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        browser?.enqueue(BrowserDialog(tabID: id, kind: .confirm, message: String(message.prefix(500)), defaultText: "", reply: { completionHandler($0 != nil) }))
    }
    func webView(_ view: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        browser?.enqueue(BrowserDialog(tabID: id, kind: .prompt, message: String(prompt.prefix(500)), defaultText: defaultText ?? "", reply: completionHandler))
    }
}

@MainActor
final class BrowserModel: ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published var selectedID = UUID() {
        didSet {
            // @Published's wrapped setter can run during session restoration.
            // Only a later, explicit selection may release quiet playback.
            if !initializingSession && selectedID != oldValue { tabs.first { $0.id == selectedID }?.prepareForPlayback() }
            persistSession(); tabs.forEach { $0.applyPlaybackOptions() }; publishNowPlaying()
        }
    }
    @Published var notice: String?
    @Published private(set) var dialog: BrowserDialog?
    @Published private(set) var sleepPlan = SleepPlan()
    @Published private(set) var playbackStopped = false
    @Published private(set) var wipingData = false
    @Published var queue = PlaybackQueue() { didSet { persistQueue(); publishNowPlaying() } }
    @Published private(set) var queueTabID: UUID? { didSet { tabs.forEach { $0.applyPlaybackOptions() }; publishNowPlaying() } }
    private var queueEvents = Set<String>()
    @Published var options: BrowserPreferences {
        didSet {
            PreferencesStorage.save(options)
            tabs.forEach { tab in
                if options.desktop != oldValue.desktop || options.zoom != oldValue.zoom { tab.applyAppearance() }
                if options.autoPiP != oldValue.autoPiP || options.hideShorts != oldValue.hideShorts || options.preferOriginalAudio != oldValue.preferOriginalAudio { tab.applyPlaybackOptions() }
                Task { await RuleStore.shared.apply(to: tab.webView, tabID: tab.id, enabled: shouldBlock(tab.webView.url)) }
            }
            if options.sources != oldValue.sources { Task { await RuleStore.shared.refreshIfNeeded(force: true) } }
            else if options.blocking && !oldValue.blocking { Task { await RuleStore.shared.refreshIfNeeded() } }
            if !options.restoreTabs { UserDefaults.standard.removeObject(forKey: "browserSessionV2") }
            if options.cloudSync != oldValue.cloudSync { notice = "iCloud-Einstellung wird beim nächsten App-Start angewendet." }
        }
    }
    var blockingEnabled: Bool { get { options.blocking } set { options.blocking = newValue } }
    var gesturesEnabled: Bool { get { options.gestures } set { options.gestures = newValue } }
    var onVisit: ((String, String) -> Void)?
    var commandRevision = 0
    private var initializingSession = true
    private var timer: Timer?
    private var dialogQueue: [BrowserDialog] = []
    private var dialogPumpScheduled = false
    init() {
        options = PreferencesStorage.load()
        #if DEBUG
        let uiFixture = ProcessInfo.processInfo.arguments.contains("--ui-test-browser")
        if uiFixture {
            options = BrowserPreferences()
            options.restoreTabs = false; options.history = false; options.blocking = false; options.sources = []
            for key in ["sleepPlanV2", "playbackQueueV1"] { UserDefaults.standard.removeObject(forKey: key) }
        }
        #endif
        if options.restoreTabs, let data = UserDefaults.standard.data(forKey: "browserSessionV2"),
           let snapshot = try? JSONDecoder().decode(BrowserSessionSnapshot.self, from: data) {
            for saved in snapshot.tabs {
                let tab = BrowserTab(id: saved.id, background: true); tab.browser = self; tab.title = saved.title
                tabs.append(tab)
                if let url = URL(string: saved.address), ["http", "https"].contains(url.scheme ?? ""), URLComponents(url: url, resolvingAgainstBaseURL: false)?.user == nil { tab.load(url) }
            }
            selectedID = snapshot.selected ?? tabs.first?.id ?? UUID()
        }
        if tabs.isEmpty { addTab() }
        if !tabs.contains(where: { $0.id == selectedID }) { selectedID = tabs[0].id }
        if let data = UserDefaults.standard.data(forKey: "playbackQueueV1"), let saved = try? JSONDecoder().decode(PlaybackQueue.self, from: data) { queue = saved; queue.validate() }
        if let data = UserDefaults.standard.data(forKey: "sleepPlanV2"), let restored = try? JSONDecoder().decode(SleepPlan.self, from: data),
           restored.tabID == nil || tabs.contains(where: { $0.id == restored.tabID }) {
            if restored.targetMediaID != nil { notice = "Timer für das damalige Video wurde verworfen: der Player wurde neu geladen."; UserDefaults.standard.removeObject(forKey: "sleepPlanV2") }
            else { sleepPlan = restored; if restored.deadline != nil { startTimer() } }
        }
        initializingSession = false
        AudioController.shared.attach(self)
        #if DEBUG
        if uiFixture { loadUITestFixture() }
        #endif
    }
    #if DEBUG
    private func loadUITestFixture() {
        // Only the explicit Debug UI-test launch uses the test runner's own
        // generated H.264/AAC signal. Release contains no fixture launch path.
        let encoded = ProcessInfo.processInfo.environment["WEBKWEB_UI_TEST_MEDIA"] ?? ""
        guard let data = Data(base64Encoded: encoded), !data.isEmpty else { return }
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body style="margin:0;background:black;color:white"><div style="position:relative;width:320px;height:180px">
        <video id="player" controls playsinline muted autoplay loop style="width:320px;height:180px"
        src="data:video/mp4;base64,\(data.base64EncodedString())"></video>
        <button aria-label="Videostart" style="position:absolute;top:40px;left:40px;width:140px;height:64px"
        onclick="document.getElementById('player').play()">Start</button></div>
        <p id="state" role="status">Video pausiert</p><p>Lokale UI-Testfixture</p>
        <script>let n=0;setInterval(()=>{document.title='Fixture '+(++n);const s=document.getElementById('state'),next=document.getElementById('player').paused?'Video pausiert':'Video läuft';if(s.textContent!==next)s.textContent=next;},1000);</script>
        </body></html>
        """
        current.webView.loadHTMLString(html, baseURL: URL(string: "https://m.youtube.com/watch?v=abcdefghijk"))
    }
    #endif
    var current: BrowserTab { tabs.first { $0.id == selectedID } ?? tabs[0] }
    var playbackTab: BrowserTab {
        let id = MediaPolicy.playbackOwner(currentID: current.id, queueID: queueTabID, candidates: tabs.map { PlaybackCandidate(id: $0.id, hasMedia: $0.hasMedia, playing: $0.playing) })
        return tabs.first { $0.id == id } ?? current
    }
    func shouldBlock(_ url: URL?) -> Bool {
        guard options.blocking else { return false }
        guard let host = url?.host?.lowercased() else { return true }
        return !options.allowlist.contains { host == $0 || host.hasSuffix("." + $0) }
    }
    func blocksShorts(_ url: URL) -> Bool {
        guard options.hideShorts, let host = url.host?.lowercased() else { return false }
        return (host == "youtube.com" || host.hasSuffix(".youtube.com")) && url.path.hasPrefix("/shorts/")
    }
    func open(_ input: String) {
        guard !wipingData else { return }
        guard let url = AddressResolver.resolve(input, engine: options.searchEngine) else { notice = "Ungültige Adresse. URLs mit Zugangsdaten werden weder geladen noch gesucht."; return }
        guard !blocksShorts(url) else { notice = "Shorts sind ausgeschaltet."; return }
        guard UIApplication.shared.canOpenURL(url) else { current.error = "Diese Adresse kann nicht geöffnet werden."; return }
        commandRevision += 1
        if current.id == queueTabID { queueTabID = nil }
        clearPlaybackStop(); current.load(url, userInitiated: true)
    }
    @discardableResult func addTab(isPrivate: Bool = false, configuration: WKWebViewConfiguration? = nil, background: Bool = false) -> BrowserTab {
        if wipingData, !tabs.isEmpty { return current }
        let tab = BrowserTab(isPrivate: isPrivate, configuration: configuration, background: background); tab.browser = self; tab.title = isPrivate ? "Privater Tab" : "Neuer Tab"
        tabs.append(tab); if !background { selectedID = tab.id }; persistSession(); return tab
    }
    func close(_ id: UUID) {
        guard !wipingData else { return }
        tabs.first { $0.id == id }?.close(); tabs.removeAll { $0.id == id }
        if queueTabID == id { queueTabID = nil }
        if sleepPlan.tabID == id { cancelSleep() }
        if tabs.isEmpty { addTab() }
        if !tabs.contains(where: { $0.id == selectedID }) { selectedID = tabs[0].id }
        persistSession()
    }
    func play() {
        commandRevision += 1; clearPlaybackStop()
        playbackTab.prepareForPlayback()
        if playbackTab.hasMedia { AudioController.shared.activateForPlayback() }
        playbackTab.runMedia("globalThis.__webkweb?.resume()")
    }
    func togglePlayback() {
        if playbackTab.playing { pauseAll(blockAutoplay: true) }
        else { play() }
    }
    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        playbackTab.runMedia("globalThis.__webkweb?.seek(\(max(-120, min(120, seconds))))")
    }
    func pauseAll(blockAutoplay: Bool = true) {
        commandRevision += 1; playbackStopped = blockAutoplay
        tabs.forEach { $0.cancelAutoplay(); $0.run("globalThis.__webkweb?.pause(\(blockAutoplay ? "true" : "false"))", allFrames: true) }
        publishNowPlaying()
    }
    private func clearPlaybackStop() { playbackStopped = false; tabs.forEach { $0.run("globalThis.__webkweb?.clearStop()", allFrames: true) } }
    func didStartFromWebsite(in tabID: UUID) {
        guard !wipingData, tabs.contains(where: { $0.id == tabID }) else { return }
        // The isolated bridge only sends this after trusted input on a player.
        // Playback already started; do not issue a second play command.
        commandRevision += 1
        clearPlaybackStop()
        publishNowPlaying()
    }
    func sleep(minutes: Int) {
        guard (1...1440).contains(minutes) else { notice = "Timer benötigt 1 bis 1440 Minuten."; return }
        sleep(seconds: minutes * 60)
    }
    func sleep(seconds: Int) {
        guard (1...86400).contains(seconds) else { notice = "Timer benötigt 1 bis 86400 Sekunden."; return }
        cancelSleep(); sleepPlan.arm(seconds: seconds); persistSleep(); if sleepPlan.isActive { startTimer() }
    }
    func sleep(videos: Int, currentVideoOnly: Bool = false) {
        guard (1...100).contains(videos),
              current.activeMediaKind == "video", (!currentVideoOnly || !current.activeMediaID.isEmpty) else {
            notice = "Videozählung benötigt 1 bis 100 Videos und einen Webseiten-Videoplayer."
            return
        }
        cancelSleep()
        sleepPlan.arm(videos: videos, tabID: current.id, mediaID: currentVideoOnly ? current.activeMediaID : nil); persistSleep()
    }
    func cancelSleep() { timer?.invalidate(); timer = nil; sleepPlan.cancel(); persistSleep(); clearPlaybackStop() }
    func enforceSleepDeadline() { if sleepPlan.hasExpired() { finishSleep() } }
    func ended(in tabID: UUID, eventID: String, mediaID: String) {
        if sleepPlan.ended(in: tabID, eventID: eventID, mediaID: mediaID) { finishSleep() } else { persistSleep() }
    }
    func openBackground(_ address: String, isPrivate: Bool? = nil) {
        guard !wipingData, let url = AddressResolver.directURL(address), !blocksShorts(url) else { return }
        let tab = addTab(isPrivate: isPrivate ?? current.isPrivate, background: true)
        tab.load(url)
    }
    func enqueueCurrent() {
        guard !current.isPrivate, let url = AddressResolver.directURL(current.address) else { notice = "Private Tabs werden nicht in die Queue übernommen."; return }
        enqueue(address: url.absoluteString, title: current.title)
    }
    func enqueue(address: String, title: String) {
        guard let url = AddressResolver.directURL(address), !blocksShorts(url) else { notice = "Die Queue benötigt eine gültige HTTP(S)-Adresse."; return }
        queue.append(QueueEntry(title: String(title.prefix(300)), address: url.absoluteString))
    }
    func startQueue(_ id: UUID) {
        guard !wipingData, let item = queue.select(id) else { return }
        playQueue(item)
    }
    func nextQueue() {
        guard queueTabID != nil, let item = queue.next() else { return }; playQueue(item, selectTab: false)
    }
    func previousQueue() {
        guard queueTabID != nil, let item = queue.previous() else { return }; playQueue(item, selectTab: false)
    }
    func removeQueueEntry(_ id: UUID) {
        if queue.currentID == id { tabs.first { $0.id == queueTabID }?.run("globalThis.__webkweb?.pause(true)", allFrames: true); queueTabID = nil }
        queue.remove(id)
    }
    func detachQueue() { queueTabID = nil }
    func queueEnded(in tabID: UUID, eventID: String, repeatPlayback: (() -> Void)? = nil) {
        guard queueTabID == tabID, !playbackStopped, queueEvents.insert(eventID).inserted else { return }
        if queueEvents.count > 1000 { queueEvents = [eventID] }
        let old = queue.currentID
        guard let item = queue.next(automatic: true) else { return }
        if item.id == old { repeatPlayback?() }
        else { playQueue(item, selectTab: false) }
    }
    private func playQueue(_ item: QueueEntry, selectTab: Bool = true) {
        guard let url = AddressResolver.directURL(item.address), !blocksShorts(url) else { notice = "Queue-Adresse ist ungültig oder Shorts sind gesperrt."; return }
        commandRevision += 1; clearPlaybackStop()
        let tab = tabs.first { $0.id == queueTabID } ?? addTab()
        queueTabID = tab.id; if selectTab { selectedID = tab.id }; tab.load(url, autoplay: true)
    }
    private func persistQueue() {
        if let data = try? JSONEncoder().encode(queue) { UserDefaults.standard.set(data, forKey: "playbackQueueV1") }
    }
    private func finishSleep() {
        timer?.invalidate(); timer = nil; sleepPlan.cancel(); persistSleep()
        pauseAll(blockAutoplay: true); notice = "Sleep-Timer: Wiedergabe pausiert."
    }
    private func startTimer() {
        let value = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.enforceSleepDeadline() } }
        RunLoop.main.add(value, forMode: .common); timer = value
    }
    private func persistSleep() {
        if sleepPlan.tabID.flatMap({ id in tabs.first { $0.id == id }?.isPrivate }) == true { UserDefaults.standard.removeObject(forKey: "sleepPlanV2"); return }
        if let data = try? JSONEncoder().encode(sleepPlan) { UserDefaults.standard.set(data, forKey: "sleepPlanV2") }
    }
    func persistSession() {
        guard options.restoreTabs, !tabs.isEmpty else { return }
        let saved = tabs.filter { !$0.isPrivate }.map { tab -> TabSnapshot in
            var parts = URLComponents(string: tab.sessionAddress); parts?.user = nil; parts?.password = nil
            return TabSnapshot(id: tab.id, address: parts?.url?.absoluteString ?? "", title: tab.title)
        }
        let selected = current.isPrivate ? nil : selectedID
        if let data = try? JSONEncoder().encode(BrowserSessionSnapshot(tabs: saved, selected: selected)) { UserDefaults.standard.set(data, forKey: "browserSessionV2") }
    }
    func recordVisit(_ tab: BrowserTab) {
        persistSession()
        guard !wipingData, !tab.isPrivate, options.history, let url = URL(string: tab.address), ["http", "https"].contains(url.scheme ?? "") else { return }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false); parts?.user = nil; parts?.password = nil
        if let sanitized = parts?.url?.absoluteString { onVisit?(tab.title, sanitized) }
    }
    func wipeWebsiteData() async {
        guard !wipingData else { return }; wipingData = true; pauseAll(blockAutoplay: true)
        queueTabID = nil
        let snapshot = tabs
        for tab in snapshot { tab.cancelPendingLoad() }
        let stores = snapshot.map { $0.webView.configuration.websiteDataStore }
        do { for tab in snapshot { try await tab.prepareForWipe() } } catch {
            tabs.forEach { $0.finishWipe() }; wipingData = false; notice = "Löschen abgebrochen: Seiten konnten nicht geschlossen werden. \(error.localizedDescription)"; return
        }
        for store in stores { await withCheckedContinuation { continuation in store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { continuation.resume() } } }
        tabs.forEach { $0.finishWipe() }; wipingData = false; clearPlaybackStop(); cancelSleep(); persistSession()
        notice = "Website-Daten gelöscht; aktive Seiten wurden geschlossen."
    }
    func enqueue(_ next: BrowserDialog) {
        guard !wipingData, tabs.contains(where: { $0.id == next.tabID }) else { next.reply(nil); return }
        dialogQueue.append(next); scheduleDialogPump()
    }
    private func scheduleDialogPump() {
        guard dialog == nil, !dialogQueue.isEmpty, !dialogPumpScheduled else { return }
        dialogPumpScheduled = true
        DispatchQueue.main.async {
            self.dialogPumpScheduled = false
            guard self.dialog == nil else { return }
            while !self.dialogQueue.isEmpty {
                let next = self.dialogQueue.removeFirst()
                if !self.wipingData, self.tabs.contains(where: { $0.id == next.tabID }) { self.dialog = next; return }
                next.reply(nil)
            }
        }
    }
    func completeDialog(_ reply: String?) {
        guard let current = dialog else { return }; dialog = nil; current.reply(reply); scheduleDialogPump()
    }
    func cancelDialogs(for tabID: UUID) {
        let removed = dialogQueue.filter { $0.tabID == tabID }; dialogQueue.removeAll { $0.tabID == tabID }; removed.forEach { $0.reply(nil) }
        if dialog?.tabID == tabID { completeDialog(nil) }
    }
    func publishNowPlaying() { if !tabs.isEmpty { AudioController.shared.update(tab: playbackTab) } }
    func foreground() async {
        enforceSleepDeadline(); AudioController.shared.updateDemand()
        if options.blocking { await RuleStore.shared.refreshIfNeeded() }
    }
}

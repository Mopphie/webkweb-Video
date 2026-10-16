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

enum PlaybackPauseReason: String { case user, remotePause, remoteStop, sleepTimer, routeChange, dataWipe, shortcut }

@MainActor
private final class WebPlaybackPause {
    var continuation: CheckedContinuation<Void, Error>?
    var timeout: Task<Void, Never>?
    func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil; timeout?.cancel(); timeout = nil
        continuation.resume(with: result)
    }
}

@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    static let world = WKContentWorld.world(name: "WebKWebPlayback")
    let id: UUID
    let isPrivate: Bool
    @Published var pinned = false
    @Published var group = ""
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
        var diagnostics: [String: Any] = [:]
        var diagnosticSignature = ""
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
    private(set) var playbackStopLatched: Bool
    private var playbackEvents: [[String: String]] = []
    private var playbackControlEvents: [[String: String]] = []
    var sessionAddress: String { lastRequestedURL?.absoluteString ?? address }
    var canControlMedia: Bool {
        SourceCapabilities.allowsBridgeControls(mainHost: URL(string: address)?.host,
            frameHost: activeFrameID.flatMap { frames[$0]?.url?.host })
    }
    var presentsWatchImmersively: Bool { watchPresentation.isImmersive(at: URL(string: address)) }

    func notePlaybackEvent(_ event: String, stateOnly: Bool = false) {
        guard !isPrivate else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let value = ["at": formatter.string(from: Date()), "event": String(event.prefix(120))]
        playbackEvents.append(value)
        if playbackEvents.count > 40 { playbackEvents.removeFirst(playbackEvents.count - 40) }
        // Metadata/loading updates from other frames must not erase the actual
        // pause commands and audio events needed to diagnose an interruption.
        if !stateOnly {
            playbackControlEvents.append(value)
            if playbackControlEvents.count > 40 { playbackControlEvents.removeFirst(playbackControlEvents.count - 40) }
        }
    }
    func mediaDiagnosticReport() -> String {
        guard !isPrivate else { return "{\"private\":true,\"diagnostics\":\"disabled\"}" }
        let value: [String: Any] = [
            "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "app_build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            "site": isPrivate ? "private" : (URL(string: address)?.host ?? ""),
            "native": ["playing": playing, "waiting": waiting, "has_media": hasMedia,
                       "media_id": activeMediaID,
                       "time": playbackTime, "stop_latched": browser?.playbackStopped ?? false,
                       "duration": duration ?? 0,
                       "restore_suspended": backgroundOpening,
                       "tab_stop_latched": playbackStopLatched,
                       "filter_enabled": browser?.shouldBlock(URL(string: address)) ?? false] as [String: Any],
            "web": activeFrameID.flatMap { frames[$0]?.diagnostics } ?? [:],
            "events": playbackEvents,
            "control_events": playbackControlEvents
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else { return "Diagnose nicht verfügbar" }
        return String(decoding: data, as: UTF8.self)
    }

    init(id: UUID = UUID(), isPrivate: Bool = false, configuration: WKWebViewConfiguration? = nil, background: Bool = false) {
        self.id = id; self.isPrivate = isPrivate; backgroundOpening = background; playbackStopLatched = background
        let config = configuration ?? WKWebViewConfiguration()
        // Keep WebKit's popup configuration/opener, but not the opener's handler.
        config.userContentController = WKUserContentController()
        if configuration == nil { config.websiteDataStore = isPrivate ? .nonPersistent() : .default() }
        if isPrivate && config.websiteDataStore.isPersistent { config.websiteDataStore = .nonPersistent() }
        config.defaultWebpagePreferences.preferredContentMode = !isPrivate && PreferencesStorage.load().desktop ? .desktop : .mobile
        config.allowsInlineMediaPlayback = true
        // Permit the website's own public Fullscreen API. WebKit defaults this
        // to false; this is not a forced player, PiP or background-play request.
        config.preferences.isElementFullscreenEnabled = true
        // A tab's initial background/restore state must not permanently change
        // WebKit's playback policy after the user selects or navigates that tab.
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = !isPrivate
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
        for (name, mainOnly) in [("Playback", false)] {
            if let url = Bundle.main.url(forResource: name, withExtension: "js"), let source = try? String(contentsOf: url, encoding: .utf8) {
                controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: mainOnly, in: world))
            }
        }
    }
    func prepareForPlayback() {
        guard backgroundOpening else { return }
        backgroundOpening = false
        // Selecting a quiet tab lifts WK suspension, not its autoplay stop.
        // Current and future documents still need an explicit Play.
        Self.installScripts(in: webView.configuration.userContentController, startPaused: playbackStopLatched)
        webView.setAllMediaPlaybackSuspended(false, completionHandler: nil)
    }
    func pausePlayback(blockAutoplay: Bool = true, reason: String) {
        if playbackStopLatched != blockAutoplay {
            playbackStopLatched = blockAutoplay
            Self.installScripts(in: webView.configuration.userContentController, startPaused: backgroundOpening || blockAutoplay)
        }
        notePlaybackEvent("app.pause.\(reason) latch=\(blockAutoplay)")
        run("globalThis.__webkweb?.pause(\(blockAutoplay ? "true" : "false"))", allFrames: true)
    }
    func releasePlaybackStop() {
        if playbackStopLatched {
            playbackStopLatched = false
            Self.installScripts(in: webView.configuration.userContentController, startPaused: backgroundOpening)
        }
        run("globalThis.__webkweb?.clearStop()", allFrames: true)
    }
    func applyAppearance() {
        // WebKit supplies the real current engine, OS and device identity.
        // Desktop/mobile preference is applied to each navigation below.
        webView.customUserAgent = nil
        webView.pageZoom = isPrivate ? 1 : (browser?.sitePreference(for: URL(string: address)).zoom ?? PreferencesStorage.load().zoom)
    }
    func applyPlaybackOptions() {
        guard let browser else { return }
        run("globalThis.__webkweb?.setBackground(\(browser.selectedID == id ? "false" : "true"))", allFrames: true)
        if backgroundOpening || playbackStopLatched { run("globalThis.__webkweb?.pause(true)", allFrames: true) }
    }
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
            self.webView.configuration.userContentController.removeAllContentRuleLists()
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
        // Native chrome changes only; leave the website DOM and its controls intact.
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
    func pauseForPrivacy() {
        guard isPrivate else { return }
        AudioController.shared.clearPrivateMetadata()
        pausePlayback(reason: "privacy")
        webView.pauseAllMediaPlayback { [weak self] in
            Task { @MainActor in
                self?.run("if(globalThis.navigator?.mediaSession) globalThis.navigator.mediaSession.metadata = null", allFrames: true)
                AudioController.shared.clearPrivateMetadata()
            }
        }
    }
    func pauseBeforeNativePlayback() async throws {
        // An untouched Home tab has never had a document or media. Asking its
        // unstarted WebContent process for an acknowledgement can stall AVPlayer.
        guard lastRequestedURL != nil || webView.url != nil || !address.isEmpty ||
                loading || hasMedia || !frames.isEmpty || wiping else { return }
        pausePlayback(reason: "native-player")
        try await withCheckedThrowingContinuation { continuation in
            let request = WebPlaybackPause(); request.continuation = continuation
            request.timeout = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                request.finish(.failure(URLError(.timedOut)))
            }
            webView.pauseAllMediaPlayback {
                Task { @MainActor in request.finish(.success(())) }
            }
        }
    }
    func close() {
        if isPrivate { pauseForPrivacy(); webView.setAllMediaPlaybackSuspended(true, completionHandler: nil) }
        run("globalThis.__webkweb?.pause(true)", allFrames: true)
        alive = false; openTask?.cancel(); visitWork?.cancel(); clearFrames(); finishBlank(URLError(.cancelled))
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.stopLoading(); webView.configuration.userContentController.removeScriptMessageHandler(forName: "playback", contentWorld: Self.world)
        webView.navigationDelegate = nil; webView.uiDelegate = nil; observations.removeAll()
        browser?.cancelDialogs(for: id)
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
        let allowedKinds: Set<String> = ["ready", "dispose", "navigation", "userplay", "state", "ended", "queueended", "notice", "started", "mediaevent"]
        guard allowedKinds.contains(kind), value.utf8.count <= 8192, body.count <= 40 else { return }
        if let url, url.scheme != "about" {
            let origin = message.frameInfo.securityOrigin
            guard ["http", "https"].contains(url.scheme ?? ""), url.user == nil, url.password == nil,
                  url.host?.lowercased() == origin.host.lowercased(), url.scheme == origin.protocol else { return }
            let port = url.port ?? (url.scheme == "https" ? 443 : 80)
            guard origin.port == 0 || origin.port == port else { return }
        }
        if kind == "state", let mediaID = body["mediaID"] as? String, !mediaID.isEmpty,
           (!mediaID.hasPrefix(documentID + ":") || mediaID.count > 200) { return }
        if kind == "ready" {
            guard frames[documentID] != nil || frames.count < 32 else { return }
            if frames[documentID] == nil { frames[documentID] = Frame(id: documentID, info: message.frameInfo, url: url) }
            if playbackStopLatched || browser?.playbackStopped == true { evaluate("globalThis.__webkweb?.pause(true)", frame: frames[documentID]!) }
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
        case "started", "userplay":
            guard let mediaID = body["mediaID"] as? String, mediaID.hasPrefix(documentID + ":") else { return }
            browser?.didStartFromWebsite(in: id, userInitiated: kind == "userplay")
        case "mediaevent":
            let allowed = ["play", "pause", "waiting", "playing", "emptied", "error", "hidden", "visible", "input", "stop-rejected"]
            guard let event = body["event"] as? String, allowed.contains(event) else { return }
            let latched = body["stopLatched"] as? Bool ?? false
            notePlaybackEvent("observed.\(event) frame=\(message.frameInfo.isMainFrame ? "main" : "child") latch=\(latched)")
        case "state":
            let keys = ["paused", "ended", "stopLatched", "readyState", "networkState", "waiting", "muted", "hidden"]
            frame.diagnostics = isPrivate ? [:] : body.filter { (keys + ["decodedFrames"]).contains($0.key) && $0.value is NSNumber }
            if !isPrivate, let source = body["sourceKind"] as? String, ["http", "https", "blob", "data", "none"].contains(source) {
                frame.diagnostics["source_kind"] = source
            }
            if !isPrivate, let mode = body["presentationMode"] as? String, ["inline", "fullscreen", "picture-in-picture", "unknown"].contains(mode) {
                frame.diagnostics["presentation_mode"] = mode
            }
            let signature = keys.map { "\($0)=\(frame.diagnostics[$0] ?? "?")" }.joined(separator: " ")
            if signature != frame.diagnosticSignature { frame.diagnosticSignature = signature; notePlaybackEvent("web " + signature, stateOnly: true) }
            frame.url = url; frame.hasMedia = body["hasMedia"] as? Bool ?? false
            frame.playing = body["playing"] as? Bool ?? false
            frame.anyPlaying = body["anyPlaying"] as? Bool ?? frame.playing
            frame.time = max(0, finite(body["time"]) ?? 0); frame.duration = finite(body["duration"]).flatMap { $0 > 0 ? $0 : nil }
            frame.priority = finite(body["priority"]) ?? 0; frame.interaction = finite(body["interactionAt"]) ?? 0
            frame.mediaID = body["mediaID"] as? String ?? ""; frame.kind = body["mediaKind"] as? String ?? ""
            frame.captions = Array((body["captions"] as? [[String: Any]] ?? []).prefix(100)).compactMap(MediaTrack.init)
            frame.audioTracks = Array((body["audioTracks"] as? [[String: Any]] ?? []).prefix(100)).compactMap(MediaTrack.init)
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
        case "queueended": break // Website links never auto-advance.
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
            let managed = false // Automatic website queue transitions are not enabled.
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
        if playbackStopLatched || browser?.playbackStopped == true { run("globalThis.__webkweb?.pause(true)", allFrames: true) }
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
        preferences.preferredContentMode = !isPrivate && (browser?.sitePreference(for: action.request.url).desktop ?? PreferencesStorage.load().desktop) ? .desktop : .mobile
        webView(view, decidePolicyFor: action) { decisionHandler($0, preferences) }
    }
    func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, (!(wiping || browser?.wipingData == true) || url.scheme == "about") else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        if action.targetFrame?.isMainFrame == true, [.linkActivated, .backForward].contains(action.navigationType) { browser?.commandRevision += 1 }
        if action.targetFrame?.isMainFrame == true, [.linkActivated, .backForward].contains(action.navigationType), browser?.queueTabID == id { browser?.detachQueue() }
        if SiteNavigationPolicy.blocks(url, mainFrame: action.targetFrame?.isMainFrame == true, privateMode: isPrivate, sites: browser?.options.blockedSites ?? []) {
            decisionHandler(.cancel); browser?.notice = "Diese Website ist in deiner Sperrliste. Du kannst sie in den Einstellungen freigeben."; return
        }
        if ["http", "https"].contains(scheme), (url.user != nil || url.password != nil) { decisionHandler(.cancel); return }
        if ["http", "https", "about"].contains(scheme) {
            if action.targetFrame?.isMainFrame == true, scheme != "about" {
                lastRequestedURL = url
                Task { [weak self] in
                    guard let self else { decisionHandler(.cancel); return }
                    view.configuration.userContentController.removeAllContentRuleLists()
                    decisionHandler(self.alive && !self.wiping && self.browser?.wipingData != true ? .allow : .cancel)
                }
            } else { decisionHandler(.allow) }
        } else {
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated, ["mailto", "tel"].contains(scheme), UIApplication.shared.canOpenURL(url) {
                browser?.enqueue(BrowserDialog(tabID: id, kind: .confirm, message: "Externe App für \(scheme) öffnen?", defaultText: "", reply: { result in
                    if result != nil { UIApplication.shared.open(url) }
                }))
            }
        }
    }
    func webView(_ view: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard action.targetFrame == nil, let browser, browser.tabs.count < 12, !browser.wipingData else { return nil }
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
    let library: LibraryStore
    let nativePlayer = NativePlayer()
    @Published private(set) var closedTabs: [TabSnapshot] = []
    @Published private(set) var sleepAfterNativeQueue = false
    @Published var privacyLocked = false
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

            }
            if !options.restoreTabs { UserDefaults.standard.removeObject(forKey: "browserSessionV2") }
        }
    }
    var gesturesEnabled: Bool { get { options.gestures } set { options.gestures = newValue } }
    var onVisit: ((String, String) -> Void)?
    var commandRevision = 0
    private var initializingSession = true
    private var timer: Timer?
    private var dialogQueue: [BrowserDialog] = []
    private var dialogPumpScheduled = false
    init() {
        #if DEBUG
        let testMode = ProcessInfo.processInfo.arguments.contains("--ui-test-browser") || ProcessInfo.processInfo.arguments.contains("--ui-test-native")
        let fixtureStore = FileManager.default.temporaryDirectory.appendingPathComponent("DevnTube-UI-Library.json")
        if testMode { try? FileManager.default.removeItem(at: fixtureStore) }
        library = LibraryStore(file: testMode ? fixtureStore : nil)
        #else
        library = LibraryStore()
        #endif
        ComplianceMigration.run()
        options = PreferencesStorage.load()
        privacyLocked = options.privateLock
        #if DEBUG
        let uiFixture = testMode
        if uiFixture {
            options = BrowserPreferences()
            options.restoreTabs = false; options.history = false
            for key in ["sleepPlanV2", "playbackQueueV1"] { UserDefaults.standard.removeObject(forKey: key) }
        }
        #endif
        if options.restoreTabs, let data = UserDefaults.standard.data(forKey: "browserSessionV2"),
           let snapshot = try? JSONDecoder().decode(BrowserSessionSnapshot.self, from: data) {
            for saved in snapshot.tabs.prefix(12) {
                let tab = BrowserTab(id: saved.id, background: true); tab.browser = self; tab.title = saved.title; tab.pinned = saved.pinned ?? false; tab.group = saved.group ?? ""
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
        nativePlayer.didActivateAudio = { AudioController.shared.didActivateNativeSession() }
        nativePlayer.library = library
        nativePlayer.restoreQueue()
        nativePlayer.beforePlay = { [weak self] in
            guard let self else { return }
            self.tabs.forEach { $0.pausePlayback(reason: "native-player") }
            self.playbackStopped = false
            // Await WebKit's actual pause acknowledgement before starting AVPlayer.
            for tab in self.tabs {
                try await tab.pauseBeforeNativePlayback()
            }
        }
        nativePlayer.onState = { [weak self] in self?.enforceSleepDeadline(); self?.publishNowPlaying() }
        nativePlayer.onEnded = { [weak self] id, queueFinished in
            guard let self else { return false }
            if self.sleepAfterNativeQueue && queueFinished { self.finishSleep(); return true }
            if self.sleepPlan.ended(in: self.nativePlayer.sessionID, eventID: UUID().uuidString, mediaID: id.uuidString) { self.finishSleep(); return true }
            self.persistSleep(); return false
        }
        AudioController.shared.attach(self)
        #if DEBUG
        if uiFixture { if ProcessInfo.processInfo.arguments.contains("--ui-test-native") { loadNativeUITestFixture() } else { loadUITestFixture() } }
        #endif
    }
    #if DEBUG
    private func loadNativeUITestFixture() {
        let value = ProcessInfo.processInfo.environment["WEBKWEB_UI_TEST_MEDIA"] ?? ""
        guard let data = Data(base64Encoded: value), data.count < 1_000_000 else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let first = FileManager.default.temporaryDirectory.appendingPathComponent("Own-UI-First.mp4")
                let second = FileManager.default.temporaryDirectory.appendingPathComponent("Own-UI-Second.mp4")
                try await NativePlayer.prepareLongUITestMedia(data, first: first, second: second)
                let a = try library.addFile(first), b = try library.addFile(second)
                nativePlayer.playPlaylist([a, b])
            } catch { notice = "Lokale Testfixture konnte nicht geöffnet werden." }
        }
    }
    private func loadUITestFixture() {
        // Only the explicit Debug UI-test launch uses the test runner's own
        // generated H.264/AAC signal. Release contains no fixture launch path.
        let encoded = ProcessInfo.processInfo.environment["WEBKWEB_UI_TEST_MEDIA"] ?? ""
        let audible = ProcessInfo.processInfo.environment["WEBKWEB_UI_TEST_AUDIBLE"] == "1"
        let scrolled = ProcessInfo.processInfo.environment["WEBKWEB_UI_TEST_SCROLLED"] == "1"
        guard let data = Data(base64Encoded: encoded), !data.isEmpty else { return }
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body style="margin:0;background:black;color:white"><header style="height:\(scrolled ? 260 : 0)px"></header>
        <div id="container" style="position:relative;width:320px;height:180px">
        <video id="player" controls playsinline \(audible ? "" : "muted autoplay") loop style="width:320px;height:180px"
        src="data:video/mp4;base64,\(data.base64EncodedString())"></video>
        <button aria-label="Videostart" style="position:absolute;top:40px;left:40px;width:140px;height:64px"
        onclick="document.getElementById('player').play()">Start</button>
        <button id="fullscreen-exit" aria-label="Website-Vollbild verlassen" style="display:none;position:absolute;top:0;left:0"
        onclick="document.exitFullscreen()">Zurück</button></div>
        <button aria-label="Website-Vollbild" onclick="document.getElementById('container').requestFullscreen().catch(error=>{document.getElementById('fullscreen-capability').textContent='Element-Vollbild Fehler: '+error.name;})">Vollbild</button>
        <button aria-label="Website-Systemplayer" onclick="document.getElementById('player').webkitEnterFullscreen()">Systemplayer</button>
        <p id="state" role="status">Video pausiert</p><p>Lokale UI-Testfixture</p><p>\(audible ? "Ton aktiv" : "Stumm")</p>
        <p id="fullscreen-capability"></p>
        <script>let lastTime=0,lastFrames=0;document.title='Lokale Medienfixture';setInterval(()=>{const s=document.getElementById('state'),v=document.getElementById('player'),frames=v.getVideoPlaybackQuality?.().totalVideoFrames||0,progress=frames>lastFrames||Math.abs(v.currentTime-lastTime)>0.05,next=v.paused?'Video pausiert':progress?'Video läuft':'Video puffert';lastTime=v.currentTime;lastFrames=frames;if(s.textContent!==next)s.textContent=next;},1000);</script>
        <script>document.addEventListener('fullscreenchange',()=>{document.getElementById('fullscreen-exit').style.display=document.fullscreenElement?'block':'none';});</script>
        <script>document.getElementById('fullscreen-capability').textContent=document.fullscreenEnabled&&typeof document.getElementById('container').requestFullscreen==='function'?'Element-Vollbild unterstützt':'Element-Vollbild nicht unterstützt';</script>
        <div style="height:1400px">Testkommentare</div>
        <script>\(scrolled ? "window.scrollTo(0,160);" : "")</script>
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
    func shouldBlock(_ url: URL?) -> Bool { false }
    func blocksShorts(_ url: URL) -> Bool { false }
    func sitePreference(for url: URL?) -> SitePreference {
        return url?.host.flatMap { options.sitePreferences[$0.lowercased()] } ?? SitePreference(desktop: options.desktop, zoom: options.zoom)
    }
    func setSitePreference(desktop: Bool, zoom: Double) {
        guard !current.isPrivate, let host = URL(string: current.address)?.host?.lowercased() else { return }
        options.sitePreferences[host] = SitePreference(desktop: desktop, zoom: min(2, max(0.5, zoom)))
        current.applyAppearance() // Reload remains an explicit separate action.
    }
    func backOrHome() { if current.canGoBack { current.webView.goBack() } else { home() } }
    func home() {
        if tabs.count < 12 { addTab() }
        else { current.cancelPendingLoad(); current.webView.loadHTMLString("<!doctype html><html></html>", baseURL: nil); current.address = ""; current.title = "Startseite" }
    }
    func clearRecentNavigation() { closedTabs = []; library.clearProgress() }
    func endPrivateSession() {
        for id in tabs.filter(\.isPrivate).map(\.id) { close(id) }
        publishNowPlaying()
    }
    func reopenClosedTab() {
        guard tabs.count < 12, let saved = closedTabs.popLast() else { return }
        let tab = addTab(); tab.pinned = saved.pinned ?? false; tab.group = saved.group ?? ""
        if let url = AddressResolver.directURL(saved.address) { tab.load(url, userInitiated: true) }
    }
    func open(_ input: String) {
        guard !privacyLocked, !wipingData else { return }
        guard let url = AddressResolver.resolve(input, engine: options.searchEngine) else { notice = "Ungültige Adresse. URLs mit Zugangsdaten werden weder geladen noch gesucht."; return }
        guard !blocksShorts(url) else { notice = "Shorts sind ausgeschaltet."; return }
        guard UIApplication.shared.canOpenURL(url) else { current.error = "Diese Adresse kann nicht geöffnet werden."; return }
        commandRevision += 1
        if current.id == queueTabID { queueTabID = nil }
        clearPlaybackStop(in: current); current.load(url, userInitiated: true)
    }
    @discardableResult func addTab(isPrivate: Bool = false, configuration: WKWebViewConfiguration? = nil, background: Bool = false) -> BrowserTab {
        if wipingData, !tabs.isEmpty { return current }
        guard tabs.count < 12 else { notice = "Maximal 12 offene Tabs. Schließe einen Tab; aktive Wiedergabe bleibt erhalten."; return current }
        let tab = BrowserTab(isPrivate: isPrivate, configuration: configuration, background: background); tab.browser = self; tab.title = isPrivate ? "Privater Tab" : "Neuer Tab"
        tabs.append(tab); if !background { selectedID = tab.id }; persistSession(); return tab
    }
    func close(_ id: UUID) {
        guard !wipingData else { return }
        if let tab = tabs.first(where: { $0.id == id }), !tab.isPrivate,
           let address = LibraryAddress.clean(tab.sessionAddress) {
            closedTabs.append(TabSnapshot(id: tab.id, address: address, title: tab.title, pinned: tab.pinned, group: tab.group))
            if closedTabs.count > 20 { closedTabs.removeFirst(closedTabs.count - 20) }
        }
        tabs.first { $0.id == id }?.close(); tabs.removeAll { $0.id == id }
        if queueTabID == id { queueTabID = nil }
        if sleepPlan.tabID == id { cancelSleep() }
        if tabs.isEmpty { addTab() }
        if !tabs.contains(where: { $0.id == selectedID }) { selectedID = tabs[0].id }
        persistSession()
    }
    func play() {
        if nativePlayer.isOpen { nativePlayer.play(); return }
        guard playbackTab.canControlMedia else { notice = "Bitte die Bedienelemente der Website verwenden."; return }
        playbackTab.notePlaybackEvent("native.play")
        commandRevision += 1; clearPlaybackStop(in: playbackTab)
        playbackTab.prepareForPlayback()
        if playbackTab.hasMedia { AudioController.shared.activateForPlayback() }
        playbackTab.runMedia("globalThis.__webkweb?.resume()")
    }
    func togglePlayback() {
        if nativePlayer.isOpen { nativePlayer.toggle(); return }
        if playbackTab.playing { pauseAll(blockAutoplay: true) }
        else { play() }
    }
    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        if nativePlayer.isOpen { nativePlayer.skip(seconds); return }
        guard playbackTab.canControlMedia else { return }
        playbackTab.runMedia("globalThis.__webkweb?.seek(\(max(-120, min(120, seconds))))")
    }
    func pauseAll(blockAutoplay: Bool = true, reason: PlaybackPauseReason = .user) {
        nativePlayer.pause()
        tabs.forEach { $0.notePlaybackEvent("native.pause.\(reason.rawValue) latch=\(blockAutoplay)") }
        commandRevision += 1; playbackStopped = blockAutoplay
        tabs.forEach { $0.cancelAutoplay(); $0.pausePlayback(blockAutoplay: blockAutoplay, reason: reason.rawValue) }
        publishNowPlaying()
    }
    private func clearPlaybackStop(in tab: BrowserTab) { playbackStopped = false; tab.releasePlaybackStop() }
    func didStartFromWebsite(in tabID: UUID, userInitiated: Bool = false) {
        guard !wipingData, let tab = tabs.first(where: { $0.id == tabID }) else { return }
        // A delayed acknowledgement of an earlier real input cannot reopen a
        // private playback session after the scene was hidden or locked.
        if tab.isPrivate && (privacyLocked || UIApplication.shared.applicationState != .active) {
            tab.pauseForPrivacy(); return
        }
        // A queued play event or new frame in a stopped tab cannot steal audio
        // ownership. Only real website input may release that tab's own latch.
        if (tab.playbackStopLatched || playbackStopped) && !userInitiated {
            tab.pausePlayback(reason: "blocked-autoplay"); return
        }
        if nativePlayer.isOpen { nativePlayer.close() }
        tabs.filter { $0.id != tabID && !$0.playbackStopLatched }.forEach { $0.pausePlayback(reason: "other-tab") }
        // Playback already started; do not issue a second play command or
        // release the stop latches of any other tab.
        commandRevision += 1
        clearPlaybackStop(in: tab)
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
        if let id = nativePlayer.mediaID, nativePlayer.duration != nil, (1...100).contains(videos) {
            cancelSleep(); sleepPlan.arm(videos: videos, tabID: nativePlayer.sessionID, mediaID: currentVideoOnly ? id.uuidString : nil); persistSleep(); return
        }
        guard (1...100).contains(videos),
              current.canControlMedia, current.duration != nil, current.activeMediaKind == "video", (!currentVideoOnly || !current.activeMediaID.isEmpty) else {
            notice = "Videozählung benötigt 1 bis 100 Videos und einen Webseiten-Videoplayer."
            return
        }
        cancelSleep()
        sleepPlan.arm(videos: videos, tabID: current.id, mediaID: currentVideoOnly ? current.activeMediaID : nil); persistSleep()
    }
    func cancelSleep() { timer?.invalidate(); timer = nil; sleepAfterNativeQueue = false; sleepPlan.cancel(); persistSleep() }
    func extendSleep() { if let deadline = sleepPlan.deadline { sleep(seconds: min(86400, max(1, Int(deadline.timeIntervalSinceNow)) + 600)) } }
    func sleepAfterQueue() { guard nativePlayer.isOpen else { notice = "Nach Queue ist nur für native Medien verfügbar."; return }; cancelSleep(); sleepAfterNativeQueue = true }
    func enforceSleepDeadline() { if sleepPlan.hasExpired() { finishSleep() } }
    func ended(in tabID: UUID, eventID: String, mediaID: String) {
        if sleepPlan.ended(in: tabID, eventID: eventID, mediaID: mediaID) { finishSleep() } else { persistSleep() }
    }
    func openBackground(_ address: String, isPrivate: Bool? = nil) {
        guard !wipingData, tabs.count < 12, let url = AddressResolver.directURL(address), !blocksShorts(url) else { return }
        let tab = addTab(isPrivate: isPrivate ?? current.isPrivate, background: true)
        tab.load(url)
    }
    func enqueueCurrent() {
        guard !current.isPrivate, let url = AddressResolver.directURL(current.address) else { notice = "Private Tabs werden nicht in die Queue übernommen."; return }
        enqueue(address: url.absoluteString, title: current.title)
    }
    func enqueue(address: String, title: String) {
        guard let clean = LibraryAddress.clean(address), let url = AddressResolver.directURL(clean) else { notice = "Die Queue benötigt einen Link ohne Zugangsdaten oder signierte Tokens."; return }
        queue.append(QueueEntry(title: String(title.prefix(300)), address: url.absoluteString))
    }
    func startQueue(_ id: UUID) {
        guard !wipingData, let item = queue.select(id) else { return }
        playQueue(item)
    }
    func nextPlaybackItem() { if nativePlayer.isOpen { nativePlayer.next() } else { nextQueue() } }
    func previousPlaybackItem() { if nativePlayer.isOpen { nativePlayer.previous() } else { previousQueue() } }
    func nextQueue() {
        guard queueTabID != nil, let item = queue.next() else { return }; playQueue(item, selectTab: false)
    }
    func previousQueue() {
        guard queueTabID != nil, let item = queue.previous() else { return }; playQueue(item, selectTab: false)
    }
    func removeQueueEntry(_ id: UUID) {
        if queue.currentID == id { tabs.first { $0.id == queueTabID }?.pausePlayback(reason: "queue-removed"); queueTabID = nil }
        queue.remove(id)
    }
    func detachQueue() { queueTabID = nil }
    private func playQueue(_ item: QueueEntry, selectTab: Bool = true) {
        guard let url = AddressResolver.directURL(item.address), !blocksShorts(url) else { notice = "Queue-Adresse ist ungültig oder Shorts sind gesperrt."; return }
        commandRevision += 1
        let tab = tabs.first { $0.id == queueTabID } ?? addTab()
        clearPlaybackStop(in: tab)
        queueTabID = tab.id; if selectTab { selectedID = tab.id }; tab.load(url, autoplay: false)
    }
    private func persistQueue() {
        if let data = try? JSONEncoder().encode(queue) { UserDefaults.standard.set(data, forKey: "playbackQueueV1") }
    }
    private func finishSleep() {
        timer?.invalidate(); timer = nil; sleepAfterNativeQueue = false; sleepPlan.cancel(); persistSleep()
        pauseAll(blockAutoplay: true, reason: .sleepTimer); notice = "Sleep-Timer: Wiedergabe pausiert."
    }
    private func startTimer() {
        let value = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.enforceSleepDeadline() } }
        RunLoop.main.add(value, forMode: .common); timer = value
    }
    private func persistSleep() {
        if !tabs.isEmpty && current.isPrivate { UserDefaults.standard.removeObject(forKey: "sleepPlanV2"); return }
        if sleepPlan.tabID.flatMap({ id in tabs.first { $0.id == id }?.isPrivate }) == true { UserDefaults.standard.removeObject(forKey: "sleepPlanV2"); return }
        if let data = try? JSONEncoder().encode(sleepPlan) { UserDefaults.standard.set(data, forKey: "sleepPlanV2") }
    }
    func persistSession() {
        guard options.restoreTabs, !tabs.isEmpty else { return }
        let saved = tabs.filter { !$0.isPrivate }.map { tab -> TabSnapshot in
            return TabSnapshot(id: tab.id, address: LibraryAddress.clean(tab.sessionAddress) ?? "", title: LibraryAddress.clean(tab.sessionAddress) == nil ? "Neuer Tab" : tab.title, pinned: tab.pinned, group: tab.group)
        }
        let selected = current.isPrivate ? nil : selectedID
        if let data = try? JSONEncoder().encode(BrowserSessionSnapshot(tabs: saved, selected: selected)) { UserDefaults.standard.set(data, forKey: "browserSessionV2") }
    }
    func recordVisit(_ tab: BrowserTab) {
        persistSession()
        guard !wipingData, !tab.isPrivate, options.history, let url = URL(string: tab.address), ["http", "https"].contains(url.scheme ?? "") else { return }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false); parts?.user = nil; parts?.password = nil
        if let sanitized = parts?.url?.absoluteString, LibraryAddress.clean(sanitized) != nil { onVisit?(tab.title, sanitized) }
    }
    func wipeWebsiteData() async {
        guard !wipingData else { return }; wipingData = true; pauseAll(blockAutoplay: true, reason: .dataWipe)
        queueTabID = nil
        let snapshot = tabs
        for tab in snapshot { tab.cancelPendingLoad() }
        let stores = snapshot.map { $0.webView.configuration.websiteDataStore }
        do { for tab in snapshot { try await tab.prepareForWipe() } } catch {
            tabs.forEach { $0.finishWipe() }; wipingData = false; notice = "Löschen abgebrochen: Seiten konnten nicht geschlossen werden. \(error.localizedDescription)"; return
        }
        for store in stores { await withCheckedContinuation { continuation in store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { continuation.resume() } } }
        tabs.forEach { $0.finishWipe(); $0.releasePlaybackStop() }; wipingData = false; playbackStopped = false; cancelSleep(); persistSession()
        notice = "Website-Daten gelöscht; aktive Seiten wurden geschlossen."
    }
    func enqueue(_ next: BrowserDialog) {
        guard !wipingData, dialogQueue.count < 32, tabs.contains(where: { $0.id == next.tabID }) else { next.reply(nil); return }
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
        if UserDefaults.standard.bool(forKey: "complianceCleanupPending") {
            ComplianceMigration.run(); notice = "Alte Integrationscaches konnten nicht vollständig gelöscht werden. Bereinigung wird erneut versucht; alte Filter sind nicht aktiv."
        }
    }
}

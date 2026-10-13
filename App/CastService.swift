import SwiftUI
#if canImport(GoogleCast)
import GoogleCast
#endif

@MainActor
final class CastService: NSObject, ObservableObject {
    static let shared = CastService()
    weak var browser: BrowserModel?
    @Published private(set) var status = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed = 0.0
    @Published private(set) var duration: Double?
    @Published private(set) var mediaTitle = "Cast"
    @Published private(set) var isControllingMedia = false
    #if canImport(GoogleCast)
    private var client: GCKRemoteMediaClient?
    private var pending: GCKRequest?
    private weak var pendingTab: BrowserTab?
    private var wasLocalPlaying = false
    private var loadRevision = 0
    private var loadDeadline: Date?
    private var progressTimer: Timer?
    #endif
    static var isAvailable: Bool {
        #if canImport(GoogleCast)
        return true
        #else
        return false
        #endif
    }
    private override init() { super.init() }
    func configure() {
        #if canImport(GoogleCast)
        guard !GCKCastContext.isSharedInstanceInitialized() else { return }
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        GCKCastContext.setSharedInstanceWith(GCKCastOptions(discoveryCriteria: criteria))
        GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = true
        GCKCastContext.sharedInstance().sessionManager.add(self)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in
            if let self, let client = self.client, let mediaStatus = client.mediaStatus { self.update(client, mediaStatus) }
        } }; RunLoop.main.add(timer, forMode: .common); progressTimer = timer
        bindClient()
        #endif
    }
    func load(_ media: DirectMedia, title: String, at time: Double) -> Bool {
        #if canImport(GoogleCast)
        bindClient()
        guard let client else { status = "Wähle zuerst ein Cast-Gerät."; return false }
        let metadata = GCKMediaMetadata(metadataType: .generic); metadata.setString(title, forKey: kGCKMetadataKeyTitle)
        let builder = GCKMediaInformationBuilder(contentURL: media.url)
        builder.contentType = media.contentType; builder.streamType = .buffered; builder.metadata = metadata
        let load = GCKMediaLoadRequestDataBuilder(); load.mediaInformation = builder.build(); load.autoplay = true; load.startTime = max(0, time)
        pendingTab = browser?.current; wasLocalPlaying = pendingTab?.playing ?? false
        loadRevision = browser?.commandRevision ?? 0; loadDeadline = browser?.sleepPlan.deadline
        pending = client.loadMedia(with: load.build()); pending?.delegate = self
        status = "Cast lädt …"; return true
        #else
        status = "Google Cast benötigt den SDK-Build über CocoaPods."; return false
        #endif
    }
    func play() {
        #if canImport(GoogleCast)
        client?.play()
        #endif
    }
    func toggle() { isPlaying ? pause() : play() }
    func pause() {
        #if canImport(GoogleCast)
        client?.pause()
        #endif
    }
    func seek(_ seconds: Double) {
        #if canImport(GoogleCast)
        let options = GCKMediaSeekOptions(); options.interval = max(0, min((duration ?? Double.greatestFiniteMagnitude), elapsed + seconds))
        client?.seek(with: options)
        #endif
    }
    func showControls() {
        #if canImport(GoogleCast)
        GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls()
        #endif
    }
    func disconnect() {
        #if canImport(GoogleCast)
        GCKCastContext.sharedInstance().sessionManager.endSessionAndStopCasting(true)
        #endif
    }
    #if canImport(GoogleCast)
    private func bindClient() {
        let next = GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient
        if client !== next { client?.remove(self); client = next; client?.add(self) }
        if let client, let mediaStatus = client.mediaStatus { update(client, mediaStatus) }
        else { isControllingMedia = false; isPlaying = false; duration = nil; browser?.publishNowPlaying() }
    }
    private func update(_ client: GCKRemoteMediaClient, _ mediaStatus: GCKMediaStatus) {
        isControllingMedia = mediaStatus.mediaInformation != nil && mediaStatus.playerState != .idle
        if mediaStatus.idleReason == .error {
            let message = "Der Cast-Empfänger konnte die Quelle nicht abspielen."
            if status != message { status = message; browser?.notice = message }
        }
        isPlaying = mediaStatus.playerState == .playing
        elapsed = client.approximateStreamPosition()
        let value = mediaStatus.mediaInformation?.streamDuration ?? 0; duration = value > 0 && value.isFinite ? value : nil
        mediaTitle = mediaStatus.mediaInformation?.metadata?.string(forKey: kGCKMetadataKeyTitle) ?? "Cast"
        browser?.publishNowPlaying()
    }
    #endif
}

#if canImport(GoogleCast)
extension CastService: GCKSessionManagerListener, GCKRemoteMediaClientListener, GCKRequestDelegate {
    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) { bindClient() }
    func sessionManager(_ sessionManager: GCKSessionManager, didResumeSession session: GCKSession) { bindClient() }
    func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) { bindClient(); status = error?.localizedDescription ?? "Cast getrennt" }
    func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
        if let mediaStatus { update(client, mediaStatus) }
        else { isControllingMedia = false; isPlaying = false; duration = nil; browser?.publishNowPlaying() }
    }
    func requestDidComplete(_ request: GCKRequest) {
        guard request === pending else { return }
        browser?.enforceSleepDeadline()
        let expired = loadDeadline.map { Date() >= $0 } ?? false
        if browser?.playbackStopped == true || expired || browser?.commandRevision != loadRevision { client?.pause() }
        pendingTab?.run("globalThis.__webkweb?.pause(\(browser?.playbackStopped == true ? "true" : "false"))", allFrames: true)
        pending = nil; pendingTab = nil; status = "Cast verbunden"
    }
    func request(_ request: GCKRequest, didAbortWithReason reason: GCKRequestAbortReason) {
        guard request === pending else { return }; pending = nil; pendingTab = nil; status = "Cast-Anfrage abgebrochen"
    }
    func request(_ request: GCKRequest, didFailWithError error: GCKError) {
        guard request === pending else { return }
        let expired = loadDeadline.map { Date() >= $0 } ?? false
        if let tab = pendingTab, wasLocalPlaying, !expired, browser?.playbackStopped == false, browser?.commandRevision == loadRevision, browser?.tabs.contains(where: { $0 === tab }) == true { tab.runMedia("globalThis.__webkweb?.resume()") }
        pending = nil; pendingTab = nil; status = "Cast fehlgeschlagen: \(error.localizedDescription)"
        browser?.notice = status
    }
}
struct CastDeviceButton: UIViewRepresentable {
    func makeUIView(context: Context) -> GCKUICastButton { let button = GCKUICastButton(frame: .zero); button.tintColor = .label; return button }
    func updateUIView(_ view: GCKUICastButton, context: Context) {}
}
#endif

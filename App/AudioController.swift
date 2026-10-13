import Foundation
import AVFoundation
import MediaPlayer

@MainActor
final class AudioController {
    static let shared = AudioController()
    private weak var browser: BrowserModel?
    private var tokens: [Any] = []
    private var resumeAfterInterruption = false
    private var interruptionRevision = 0
    private var interruptionDeadline: Date?
    private init() {}
    func attach(_ browser: BrowserModel) {
        self.browser = browser
        guard tokens.isEmpty else { return }
        activate()
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.browser?.play() }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.browser?.pauseAll(blockAutoplay: true) }; return .success }
        // Clock's Stop Playing action can arrive through the system stop/pause
        // route. Delivery to a WKWebView still depends on iOS; no polling/private API.
        center.stopCommand.addTarget { [weak self] _ in Task { @MainActor in self?.browser?.pauseAll(blockAutoplay: true) }; return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.browser?.togglePlayback() }; return .success }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.browser?.seek(10) }; return .success }
        center.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.browser?.seek(-10) }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.browser?.nextQueue() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.browser?.previousQueue() }; return .success }
        tokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.interrupted(note) }
        })
        tokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.activate() } })
        tokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                if (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.browser?.pauseAll() }
            }
        })
    }
    func activate() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { browser?.notice = "Audio-Sitzung konnte nicht aktiviert werden: \(error.localizedDescription)" }
    }
    func update(tab: BrowserTab) {
        let cast = CastService.shared, hasContent = tab.hasMedia || cast.isControllingMedia
        let center = MPRemoteCommandCenter.shared()
        [center.playCommand, center.pauseCommand, center.stopCommand, center.togglePlayPauseCommand, center.skipForwardCommand, center.skipBackwardCommand].forEach { $0.isEnabled = hasContent }
        center.nextTrackCommand.isEnabled = !cast.isControllingMedia && browser?.queueTabID != nil && browser?.queue.canNext == true
        center.previousTrackCommand.isEnabled = !cast.isControllingMedia && browser?.queueTabID != nil && browser?.queue.canPrevious == true
        guard hasContent else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        let playing = cast.isControllingMedia ? cast.isPlaying : tab.playing
        var data: [String: Any] = [MPMediaItemPropertyTitle: tab.isPrivate ? "Privater Player" : (cast.isControllingMedia ? cast.mediaTitle : tab.title),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: cast.isControllingMedia ? cast.elapsed : tab.playbackTime,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0]
        if let duration = cast.isControllingMedia ? cast.duration : tab.duration, duration.isFinite { data[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = data
    }
    private func interrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, let type = AVAudioSession.InterruptionType(rawValue: raw), let browser else { return }
        if type == .began {
            resumeAfterInterruption = browser.playbackTab.playing || CastService.shared.isPlaying
            interruptionDeadline = browser.sleepPlan.deadline
            browser.pauseAll(blockAutoplay: true); interruptionRevision = browser.commandRevision
        } else {
            activate(); browser.enforceSleepDeadline()
            let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            let timerExpired = interruptionDeadline.map { Date() >= $0 } ?? false
            if options.contains(.shouldResume), resumeAfterInterruption, !timerExpired, browser.commandRevision == interruptionRevision { browser.play() }
            resumeAfterInterruption = false
        }
    }
}

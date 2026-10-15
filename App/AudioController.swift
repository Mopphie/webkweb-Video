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
    private var ownsActiveSession = false
    private var interruptedTabID: UUID?
    private var interruptedMediaID = ""
    private init() {}
    func attach(_ browser: BrowserModel) {
        self.browser = browser
        guard tokens.isEmpty else { return }
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
        tokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.ownsActiveSession = false; self?.updateDemand() } })
        tokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                if (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.browser?.pauseAll() }
            }
        })
    }
    func activateForPlayback() { updateDemand(explicitPlay: true) }
    func updateDemand(explicitPlay: Bool = false) {
        guard let browser else { return }
        let required = MediaPolicy.requiresAudioSession(localPlaying: browser.tabs.contains(where: \.hasActivePlayback), explicitPlay: explicitPlay, stopped: browser.playbackStopped, alreadyActive: ownsActiveSession)
        guard required != ownsActiveSession else { return }
        do {
            if required { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback); try AVAudioSession.sharedInstance().setActive(true) }
            else { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
            ownsActiveSession = required
        } catch { browser.notice = "Audio-Sitzung konnte nicht geändert werden: \(error.localizedDescription)" }
    }
    func update(tab: BrowserTab) {
        updateDemand()
        let hasContent = tab.hasMedia
        let center = MPRemoteCommandCenter.shared()
        [center.playCommand, center.pauseCommand, center.stopCommand, center.togglePlayPauseCommand, center.skipForwardCommand, center.skipBackwardCommand].forEach { $0.isEnabled = hasContent }
        center.nextTrackCommand.isEnabled = browser?.queueTabID != nil && browser?.queue.canNext == true
        center.previousTrackCommand.isEnabled = browser?.queueTabID != nil && browser?.queue.canPrevious == true
        guard hasContent else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        let playing = tab.playing
        var data: [String: Any] = [MPMediaItemPropertyTitle: tab.isPrivate ? "Privater Player" : tab.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: tab.playbackTime,
            MPNowPlayingInfoPropertyPlaybackRate: MediaPolicy.nowPlayingRate(playing: playing, rate: tab.playbackRate)]
        if let duration = tab.duration, duration.isFinite { data[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = data
    }
    private func interrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, let type = AVAudioSession.InterruptionType(rawValue: raw), let browser else { return }
        if type == .began {
            resumeAfterInterruption = browser.playbackTab.playing
            interruptedTabID = browser.playbackTab.id; interruptedMediaID = browser.playbackTab.activeMediaID
            interruptionDeadline = browser.sleepPlan.deadline
            ownsActiveSession = false
            browser.pauseAll(blockAutoplay: true); interruptionRevision = browser.commandRevision
        } else {
            browser.enforceSleepDeadline()
            let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            let timerExpired = interruptionDeadline.map { Date() >= $0 } ?? false
            if options.contains(.shouldResume), resumeAfterInterruption, !timerExpired, browser.commandRevision == interruptionRevision,
               browser.playbackTab.id == interruptedTabID, browser.playbackTab.activeMediaID == interruptedMediaID { browser.play() }
            resumeAfterInterruption = false
        }
    }
}

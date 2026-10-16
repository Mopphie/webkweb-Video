import AVFoundation
import AVKit
import Combine
import SwiftUI

struct NativeMediaOption: Identifiable { let id: Int; let title: String }
struct NativeChapter: Identifiable { let id: Int; let title: String; let seconds: Double }

@MainActor
final class NativePlayer: ObservableObject {
    @Published private(set) var player = AVPlayer()
    let sessionID = UUID()
    private(set) var commandRevision = 0
    var sceneActive = true
    var restoringPiP = false
    @Published private(set) var mediaID: UUID?
    @Published private(set) var title = ""
    @Published private(set) var playing = false
    @Published private(set) var waiting = false
    @Published private(set) var time = 0.0
    @Published private(set) var duration: Double?
    @Published private(set) var error: String?
    @Published var expanded = true
    @Published var focus = false
    @Published var rate: Float = 1 { didSet { if playing { player.rate = rate } } }
    @Published var repeatOne = false
    @Published var loopA: Double?
    @Published var loopB: Double?
    @Published private(set) var queueIDs: [UUID] = [] {
        didSet { if let data = try? JSONEncoder().encode(queueIDs) { UserDefaults.standard.set(data, forKey: "nativeQueueV1") } }
    }
    @Published private(set) var unavailable: [UUID: String] = [:]
    @Published private(set) var chapters: [NativeChapter] = []
    @Published private(set) var captions: [NativeMediaOption] = []
    @Published private(set) var audioOptions: [NativeMediaOption] = []
    @Published private(set) var captionID = -1
    @Published private(set) var audioID = -1
    var beforePlay: (@MainActor () async -> Void)?
    var didActivateAudio: (() -> Void)?
    var onState: (() -> Void)?
    var onEnded: ((UUID, Bool) -> Bool)? // true means the sleep timer stopped playback
    weak var library: LibraryStore?
    private var generation = UUID()
    private var loadingTask: Task<Void, Never>?
    private var playTask: Task<Void, Never>?
    private var playRequest = UUID()
    private var cleanupPlayer: AVPlayer? // Stored reference: deinit must not call an actor-isolated @Published getter.
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var securityURL: URL?
    private var captionGroup: AVMediaSelectionGroup?
    private var audioGroup: AVMediaSelectionGroup?
    private var seekingLoop = false
    private var naturalEndHandled = false
    private var loadingAsset: AVURLAsset?
    var isOpen: Bool { mediaID != nil }
    var live: Bool { isOpen && duration == nil }
    var canNext: Bool { guard let id = mediaID, let i = queueIDs.firstIndex(of: id) else { return false }; return i + 1 < queueIDs.count }
    var canPrevious: Bool { guard let id = mediaID, let i = queueIDs.firstIndex(of: id) else { return false }; return i > 0 }

    init() { configurePlayer() }
    private func configurePlayer() {
        cleanupPlayer = player
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        player.allowsExternalPlayback = true
        player.automaticallyWaitsToMinimizeStalling = true
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.updateState() }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    deinit {
        loadingTask?.cancel(); playTask?.cancel()
        if let timeObserver { cleanupPlayer?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        securityURL?.stopAccessingSecurityScopedResource()
    }
    func handleMediaServicesReset() {
        savePosition(); loadingTask?.cancel(); playTask?.cancel(); generation = UUID(); playRequest = UUID()
        let position = time
        releaseItem()
        if let timeObserver { player.removeTimeObserver(timeObserver) }; timeObserver = nil
        statusObservation = nil
        player = AVPlayer(); configurePlayer(); time = position
        if isOpen { error = "Das Audiosystem wurde zurückgesetzt. Wiedergabe bewusst erneut versuchen." }
        onState?()
    }
    func restoreQueue() {
        guard let data = UserDefaults.standard.data(forKey: "nativeQueueV1"), data.count < 1_000_000,
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return }
        var seen = Set<UUID>(); queueIDs = Array(ids.filter { id in seen.insert(id).inserted && library?.document.media.contains(where: { $0.id == id && $0.kind != .website }) == true }.prefix(10_000))
    }
    func enqueue(_ id: UUID) { if queueIDs.count < 10_000, !queueIDs.contains(id), library?.document.media.contains(where: { $0.id == id && $0.kind != .website }) == true { queueIDs.append(id) } }
    func removeFromQueue(_ id: UUID) { queueIDs.removeAll { $0 == id }; unavailable.removeValue(forKey: id) }
    func moveQueue(from offsets: IndexSet, to destination: Int) {
        let valid = offsets.filter { queueIDs.indices.contains($0) }, values = offsets.sorted().filter { queueIDs.indices.contains($0) }.map { queueIDs[$0] }
        for index in valid.sorted(by: >) { queueIDs.remove(at: index) }
        queueIDs.insert(contentsOf: values, at: min(queueIDs.count, max(0, destination - valid.filter { $0 < destination }.count)))
    }
    func playPlaylist(_ ids: [UUID]) { var seen = Set<UUID>(); queueIDs = ids.filter { seen.insert($0).inserted }; if let first = queueIDs.first { open(first) } }
    func open(_ id: UUID, seekTo: Double? = nil) {
        commandRevision &+= 1
        guard let library, let media = library.document.media.first(where: { $0.id == id }), media.kind != .website else { error = "Website-Links bitte im Browser öffnen."; return }
        savePosition(); loadingTask?.cancel(); releaseItem()
        let revision = UUID(); generation = revision; mediaID = id; title = media.title; error = nil
        naturalEndHandled = false
        time = 0; duration = nil; chapters = []; captions = []; audioOptions = []; captionGroup = nil; audioGroup = nil
        captionID = -1; audioID = -1; loopA = nil; loopB = nil; repeatOne = false; expanded = true
        loadingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url: URL
                if media.kind == .localFile {
                    url = try library.resolveFile(id)
                    if url.startAccessingSecurityScopedResource() { self.securityURL = url }
                } else {
                    guard let direct = SourceCapabilities.directMediaURL(media.address) else { throw LibraryError.invalid("Nicht autorisierte oder ungültige Direktquelle.") }; url = direct
                }
                let asset = AVURLAsset(url: url); self.loadingAsset = asset
                guard try await asset.load(.isPlayable) else { throw LibraryError.invalid("Dieses Format wird vom System nicht unterstützt.") }
                guard !Task.isCancelled, self.generation == revision else { return }
                let item = AVPlayerItem(asset: asset)
                self.player.replaceCurrentItem(with: item)
                self.itemObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
                    Task { @MainActor in
                        guard let self, self.generation == revision, let item else { return }
                        if item.status == .failed { self.fail("Medienquelle nicht verfügbar. Datei erneut wählen oder Verbindung prüfen.", id: id) }
                    }
                }
                self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.ended(revision: revision) }
                }
                let total = try await asset.load(.duration).seconds
                guard !Task.isCancelled, self.generation == revision else { return }
                self.duration = total.isFinite && total > 0 ? total : nil
                if let total = self.duration {
                    let resume = seekTo ?? (media.completed ? 0 : media.position)
                    if resume.isFinite, resume > 0 { await self.player.seek(to: CMTime(seconds: min(resume, max(0, total - 0.1)), preferredTimescale: 600)) }
                }
                guard !Task.isCancelled, self.generation == revision else { return }
                self.play()
                await self.loadTracks(asset, revision: revision)
            } catch {
                guard !Task.isCancelled, self.generation == revision else { return }
                self.fail("Quelle konnte nicht geöffnet werden. Datei, Format und Netzwerk prüfen.", id: id)
            }
        }
    }
    private func loadTracks(_ asset: AVAsset, revision: UUID) async {
        let text = try? await asset.loadMediaSelectionGroup(for: .legible)
        let audio = try? await asset.loadMediaSelectionGroup(for: .audible)
        let groups = (try? await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: Locale.preferredLanguages)) ?? []
        var values: [NativeChapter] = []
        for (index, group) in groups.enumerated() {
            let title = try? await group.items.first(where: { $0.commonKey == .commonKeyTitle })?.load(.stringValue)
            let seconds = group.timeRange.start.seconds
            if seconds.isFinite, seconds >= 0 { values.append(NativeChapter(id: index, title: title ?? "Kapitel \(index + 1)", seconds: seconds)) }
        }
        guard generation == revision else { return }
        captionGroup = text; audioGroup = audio
        captions = (text?.options ?? []).enumerated().map { NativeMediaOption(id: $0.offset, title: $0.element.displayName) }
        audioOptions = (audio?.options ?? []).enumerated().map { NativeMediaOption(id: $0.offset, title: $0.element.displayName) }
        if let audio, let selected = player.currentItem?.currentMediaSelection.selectedMediaOption(in: audio) { audioID = audio.options.firstIndex(of: selected) ?? -1 }
        if let text, let selected = player.currentItem?.currentMediaSelection.selectedMediaOption(in: text) { captionID = text.options.firstIndex(of: selected) ?? -1 }
        chapters = values
    }
    func selectCaption(_ id: Int) {
        guard let group = captionGroup, id == -1 || group.options.indices.contains(id) else { return }
        player.currentItem?.select(id == -1 ? nil : group.options[id], in: group); captionID = id
    }
    func selectAudio(_ id: Int) {
        guard let group = audioGroup, group.options.indices.contains(id) else { return }
        player.currentItem?.select(group.options[id], in: group); audioID = id
    }
    func play() {
        commandRevision &+= 1
        guard isOpen, player.currentItem != nil, error == nil, !playing else { return }
        playTask?.cancel(); let request = UUID(); playRequest = request
        let revision = generation
        playTask = Task { [weak self] in
            guard let self else { return }
            await self.beforePlay?()
            guard !Task.isCancelled, self.generation == revision, self.playRequest == request, self.isOpen, self.error == nil else { return }
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try AVAudioSession.sharedInstance().setActive(true)
                self.didActivateAudio?()
                if let duration = self.duration, self.time >= duration - 0.05 { self.seek(to: 0) }
                if let id = self.mediaID { self.unavailable.removeValue(forKey: id) }
                self.player.playImmediately(atRate: min(3, max(0.25, self.rate)))
            } catch { self.error = "Audio konnte nicht aktiviert werden." }
            self.updateState()
        }
    }
    func pause(userInitiated: Bool = true) { if userInitiated { commandRevision &+= 1 }; playRequest = UUID(); playTask?.cancel(); player.pause(); savePosition(); updateState() }
    func toggle() { playing ? pause() : play() }
    func seek(to seconds: Double) {
        guard let duration, seconds.isFinite else { return }
        player.seek(to: CMTime(seconds: min(duration, max(0, seconds)), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func skip(_ seconds: Double) { seek(to: time + seconds) }
    func setLoopStart() { guard duration != nil else { return }; loopA = time; loopB = nil }
    func setLoopEnd() { guard let a = loopA, duration != nil, time > a + 0.5 else { return }; loopB = time }
    func clearLoop() { loopA = nil; loopB = nil }
    func next() { guard let id = mediaID, let i = queueIDs.firstIndex(of: id), i + 1 < queueIDs.count else { return }; open(queueIDs[i + 1]) }
    func previous() { guard let id = mediaID, let i = queueIDs.firstIndex(of: id), i > 0 else { return }; open(queueIDs[i - 1]) }
    func retry() { if let id = mediaID { open(id, seekTo: time) } }
    func close() {
        commandRevision &+= 1
        savePosition(); loadingTask?.cancel(); playTask?.cancel(); playRequest = UUID(); generation = UUID(); releaseItem()
        mediaID = nil; title = ""; error = nil; time = 0; duration = nil; playing = false; waiting = false; onState?()
    }
    private func releaseItem() {
        loadingAsset?.cancelLoading(); loadingAsset = nil
        player.pause(); player.replaceCurrentItem(with: nil); itemObservation = nil
        playing = false; waiting = false
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }; endObserver = nil
        securityURL?.stopAccessingSecurityScopedResource(); securityURL = nil
    }
    private func fail(_ message: String, id: UUID) { player.pause(); error = message; unavailable[id] = message; updateState() }
    private func updateState() { playing = player.timeControlStatus == .playing; waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate && error == nil; onState?() }
    private func tick() {
        let current = player.currentTime().seconds
        time = current.isFinite ? max(0, current) : 0
        if let duration, time < duration - 0.5 { naturalEndHandled = false }
        if let a = loopA, let b = loopB, time >= b, playing, !seekingLoop {
            seekingLoop = true
            player.seek(to: CMTime(seconds: a, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in Task { @MainActor in self?.seekingLoop = false } }
        }
        if let id = mediaID { library?.recordProgress(id: id, seconds: time, duration: duration) }
        onState?()
    }
    private func savePosition() { if let id = mediaID { library?.recordProgress(id: id, seconds: time, duration: duration, force: true) } }
    private func ended(revision: UUID) {
        guard generation == revision, !naturalEndHandled, let id = mediaID else { return }
        naturalEndHandled = true
        time = duration ?? time; savePosition(); updateState()
        if onEnded?(id, !canNext) == true { return }
        if repeatOne { seek(to: 0); play() }
        else if canNext { next() }
    }
}

/// Same AVPlayer across large/small presentation, PiP and fullscreen. Never clones an item.
@MainActor
struct NativePlayerSurface: UIViewControllerRepresentable {
    @ObservedObject var playback: NativePlayer
    func makeCoordinator() -> Coordinator { Coordinator(playback) }
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let view = AVPlayerViewController(); view.player = playback.player
        view.allowsPictureInPicturePlayback = true
        view.canStartPictureInPictureAutomaticallyFromInline = true
        view.delegate = context.coordinator
        return view
    }
    func updateUIViewController(_ view: AVPlayerViewController, context: Context) { if view.player !== playback.player { view.player = playback.player } }
    @MainActor
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        weak var playback: NativePlayer?
        init(_ playback: NativePlayer) { self.playback = playback }
        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            guard let playback else { return }
            if !playback.sceneActive && !playback.restoringPiP { playback.pause() }
            playback.restoringPiP = false
        }
        func playerViewController(_ playerViewController: AVPlayerViewController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
            playback?.restoringPiP = true; playback?.expanded = true; completionHandler(playback?.isOpen == true)
        }
    }
}

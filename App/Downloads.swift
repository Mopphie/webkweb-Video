import Foundation
import Combine

// The same Release product for every user omits unlicensed direct downloads.
#if !WEBKWEB_NO_DOWNLOADS

struct DownloadedFile: Identifiable {
    var id: String { url.lastPathComponent }
    let url: URL
    let title: String
    let bytes: Int64
}
struct DownloadJob: Identifiable {
    enum State { case running, cancelled, failed, finished }
    let id: UUID
    let media: DirectMedia // Memory only: source URL is never persisted.
    let title: String
    var progress = 0.0
    var state = State.running
    var error = ""
}

@MainActor
final class DownloadStore: ObservableObject {
    static let shared = DownloadStore()
    @Published private(set) var jobs: [DownloadJob] = []
    @Published private(set) var files: [DownloadedFile] = []
    @Published var error: String?
    private var tasks: [UUID: URLSessionDownloadTask] = [:]
    private var attempts: [UUID: UUID] = [:]
    private var observations: [UUID: NSKeyValueObservation] = [:]
    private let folder: URL
    private let session: URLSession
    private init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads", isDirectory: true)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 3600
        session = URLSession(configuration: config)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var localFolder = folder; try? localFolder.setResourceValues(values)
        // Interrupted foreground downloads are not resumable after process loss.
        let stage = folder.appendingPathComponent("Staging", isDirectory: true)
        try? FileManager.default.removeItem(at: stage)
        try? FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        reloadFiles()
    }
    static func supports(_ media: DirectMedia) -> Bool {
        guard media.url.scheme?.lowercased() == "https" else { return false }
        let type = media.contentType.lowercased()
        return (type.hasPrefix("video/") || type.hasPrefix("audio/")) && !type.contains("mpegurl") && !type.contains("dash")
    }
    func start(_ media: DirectMedia, title: String) {
        guard Self.supports(media) else { error = "Nur direkte HTTPS-Audio-/Videodateien. HLS-/DASH-Playlists werden nicht als Offlinevideo gespeichert."; return }
        let job = DownloadJob(id: UUID(), media: media, title: String(title.prefix(100)))
        jobs.insert(job, at: 0); begin(job)
    }
    func retry(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state == .failed || jobs[index].state == .cancelled else { return }
        jobs[index].state = .running; jobs[index].error = ""; jobs[index].progress = 0
        begin(jobs[index])
    }
    private func begin(_ job: DownloadJob) {
        let attempt = UUID(), stage = folder.appendingPathComponent("Staging").appendingPathComponent(attempt.uuidString)
        attempts[job.id] = attempt
        let task = session.downloadTask(with: job.media.url) { [weak self] temporary, response, failure in
            var moveFailure: Error? = failure
            if let temporary, failure == nil {
                // Move synchronously: URLSession deletes its temporary file after
                // this callback. The stage name belongs to this attempt only.
                do { try FileManager.default.moveItem(at: temporary, to: stage) } catch { moveFailure = error }
            }
            let capturedError = moveFailure
            Task { @MainActor [weak self] in
                guard let self else { try? FileManager.default.removeItem(at: stage); return }
                self.finish(job, attempt: attempt, stage: stage, response: response, failure: capturedError)
            }
        }
        tasks[job.id] = task
        observations[job.id] = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                guard let self, self.attempts[job.id] == attempt, let index = self.jobs.firstIndex(where: { $0.id == job.id }), self.jobs[index].state == .running else { return }
                self.jobs[index].progress = max(0, min(1, fraction))
            }
        }
        task.resume()
    }
    private func finish(_ job: DownloadJob, attempt: UUID, stage: URL, response: URLResponse?, failure: Error?) {
        defer { try? FileManager.default.removeItem(at: stage) }
        guard attempts[job.id] == attempt, let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        tasks.removeValue(forKey: job.id); observations.removeValue(forKey: job.id)
        do {
            if let failure { throw failure }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let type = http.mimeType?.lowercased(), Self.validResponse(type, expected: job.media) else { throw URLError(.cannotDecodeContentData) }
            let size = Int64(try stage.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            guard size > 0 else { throw URLError(.zeroByteResource) }
            let name = Self.filename(title: job.title, type: type, source: job.media.url)
            try FileManager.default.moveItem(at: stage, to: folder.appendingPathComponent(job.id.uuidString + "_" + name))
            jobs[index].state = .finished; jobs[index].progress = 1; reloadFiles()
        } catch { jobs[index].state = .failed; jobs[index].error = "Download fehlgeschlagen: \(error.localizedDescription)" }
    }
    static func validResponse(_ type: String, expected: DirectMedia) -> Bool {
        if type.contains("mpegurl") || type.contains("dash") { return false }
        if type.hasPrefix("video/") || type.hasPrefix("audio/") { return true }
        return type == "application/octet-stream" && ["mp4", "m4v", "mov", "webm", "mp3", "m4a", "aac", "wav", "ogg"].contains(expected.url.pathExtension.lowercased())
    }
    static func filename(title: String, type: String, source: URL) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        var safe = String.UnicodeScalarView()
        safe.append(contentsOf: title.unicodeScalars.filter { allowed.contains($0) }.prefix(70))
        let name = String(safe).trimmingCharacters(in: .whitespaces)
        let types = ["video/mp4": "mp4", "video/webm": "webm", "video/quicktime": "mov", "audio/mpeg": "mp3", "audio/mp4": "m4a", "audio/aac": "aac", "audio/wav": "wav", "audio/ogg": "ogg"]
        let validExtensions = ["mp4", "m4v", "mov", "webm", "mp3", "m4a", "aac", "wav", "ogg"]
        let ext = types[type] ?? (validExtensions.contains(source.pathExtension.lowercased()) ? source.pathExtension.lowercased() : "media")
        return (name.isEmpty ? "Medium" : name) + "." + ext
    }
    func cancel(_ id: UUID) {
        attempts[id] = UUID(); tasks.removeValue(forKey: id)?.cancel(); observations.removeValue(forKey: id)
        if let index = jobs.firstIndex(where: { $0.id == id }) { jobs[index].state = .cancelled }
    }
    func dismissJob(_ id: UUID) { cancel(id); jobs.removeAll { $0.id == id }; attempts.removeValue(forKey: id) }
    func delete(_ file: DownloadedFile) {
        do { try FileManager.default.removeItem(at: file.url); reloadFiles() } catch { self.error = error.localizedDescription }
    }
    private func reloadFiles() {
        files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])) ?? []).compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true else { return nil }
            let name = url.lastPathComponent, title = name.count > 37 ? String(name.dropFirst(37)) : name
            return DownloadedFile(url: url, title: title, bytes: Int64(values.fileSize ?? 0))
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
#endif

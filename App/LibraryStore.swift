import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var document = LibraryDocument()
    @Published var error: String?
    private let file: URL
    private var writable = true
    private var committed = LibraryDocument()
    private var lastProgressSave = Date.distantPast
    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Library-v1.json")
        do {
            if FileManager.default.fileExists(atPath: self.file.path) {
                let data = try Data(contentsOf: self.file)
                guard data.count <= 20_000_000 else { throw LibraryError.invalid("Mediathek ist zu groß.") }
                document = try JSONDecoder().decode(LibraryDocument.self, from: data).validated()
            }
        } catch { self.error = "Mediathek konnte nicht gelesen werden; Original bleibt erhalten. \(error.localizedDescription)"; writable = false }
        committed = document
    }
    @discardableResult private func save() -> Bool {
        guard writable else { document = committed; error = "Mediathek ist schreibgeschützt, bis der Lesefehler geklärt ist."; return false }
        do {
            let data = try JSONEncoder().encode(document.validated())
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            committed = document; error = nil; return true
        } catch { document = committed; self.error = "Änderung nicht gespeichert: " + error.localizedDescription; return false }
    }
    @discardableResult func addLink(title: String, address: String, kind: MediaSourceKind = .website) -> UUID? {
        guard writable, let address = LibraryAddress.clean(address), kind != .localFile,
              kind != .authorizedDirect || SourceCapabilities.directMediaURL(address) != nil else { error = "Dieser Link kann nicht dauerhaft gespeichert werden."; return nil }
        if let item = document.media.first(where: { $0.address == address && $0.kind == kind }) { return item.id }
        let item = LibraryMedia(title: String(title.prefix(500)), kind: kind, address: address)
        document.media.append(item); guard save() else { return nil }; return item.id
    }
    @discardableResult func addFile(_ url: URL) throws -> UUID {
        guard writable, url.isFileURL else { throw LibraryError.invalid("Lokale Datei erforderlich.") }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let item = LibraryMedia(title: url.deletingPathExtension().lastPathComponent, kind: .localFile, fileBookmark: bookmark)
        document.media.append(item); guard save() else { throw LibraryError.invalid(error ?? "Datei nicht gespeichert.") }; return item.id
    }
    func relinkFile(_ id: UUID, to url: URL) throws {
        guard writable, url.isFileURL, let i = document.media.firstIndex(where: { $0.id == id && $0.kind == .localFile }) else { throw LibraryError.invalid("Dateieintrag nicht verfügbar.") }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        document.media[i].fileBookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        guard save() else { throw LibraryError.invalid(error ?? "Dateiverknüpfung nicht gespeichert.") }
    }
    func resolveFile(_ id: UUID) throws -> URL {
        guard let index = document.media.firstIndex(where: { $0.id == id }), let data = document.media[index].fileBookmark else { throw LibraryError.invalid("Datei bitte erneut über die Dateien-App auswählen.") }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        guard url.isFileURL else { throw LibraryError.invalid("Ungültige Dateiberechtigung.") }
        if stale {
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            document.media[index].fileBookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil); save()
        }
        return url
    }
    func recordProgress(id: UUID, seconds: Double, duration: Double?, force: Bool = false) {
        guard writable, seconds.isFinite, seconds >= 0, let duration, duration.isFinite, duration > 0,
              let index = document.media.firstIndex(where: { $0.id == id }), document.media[index].kind != .website else { return }
        document.media[index].position = min(seconds, duration)
        document.media[index].duration = duration; document.media[index].completed = seconds >= max(duration * 0.95, duration - 5)
        document.media[index].lastPlayedAt = .now
        if force || Date().timeIntervalSince(lastProgressSave) >= 10 { lastProgressSave = .now; save() }
    }
    func clearProgress() {
        for i in document.media.indices { document.media[i].position = 0; document.media[i].duration = nil; document.media[i].lastPlayedAt = nil; document.media[i].completed = false }; save()
    }
    func toggleFavorite(_ id: UUID) { guard let i = document.media.firstIndex(where: { $0.id == id }) else { return }; document.media[i].favorite = !(document.media[i].favorite ?? false); save() }
    func rename(_ id: UUID, title: String) { guard let i = document.media.firstIndex(where: { $0.id == id }), !title.isEmpty else { return }; document.media[i].title = String(title.prefix(500)); save() }
    func remove(_ id: UUID) {
        document.media.removeAll { $0.id == id }; document.notes.removeAll { $0.mediaID == id }
        for i in document.playlists.indices { document.playlists[i].mediaIDs.removeAll { $0 == id } }; save()
    }
    func createPlaylist(_ name: String) { let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100)); guard !name.isEmpty else { return }; document.playlists.append(NamedPlaylist(name: name)); save() }
    func renamePlaylist(_ id: UUID, name: String) { guard let i = document.playlists.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; document.playlists[i].name = String(name.prefix(100)); save() }
    func removePlaylist(_ id: UUID) { document.playlists.removeAll { $0.id == id }; save() }
    func add(_ media: UUID, to playlist: UUID) { guard let i = document.playlists.firstIndex(where: { $0.id == playlist }), document.media.contains(where: { $0.id == media }), !document.playlists[i].mediaIDs.contains(media) else { return }; document.playlists[i].mediaIDs.append(media); save() }
    func remove(_ media: UUID, from playlist: UUID) { guard let i = document.playlists.firstIndex(where: { $0.id == playlist }) else { return }; document.playlists[i].mediaIDs.removeAll { $0 == media }; save() }
    func movePlaylistItems(_ id: UUID, from offsets: IndexSet, to destination: Int) {
        guard let i = document.playlists.firstIndex(where: { $0.id == id }) else { return }
        var values = document.playlists[i].mediaIDs
        let valid = offsets.filter { values.indices.contains($0) }; let moving = valid.sorted().map { values[$0] }
        for offset in valid.sorted(by: >) { values.remove(at: offset) }
        values.insert(contentsOf: moving, at: min(values.count, max(0, destination - valid.filter { $0 < destination }.count)))
        document.playlists[i].mediaIDs = values; save()
    }
    func addNote(media: UUID, seconds: Double?, text: String) {
        guard document.media.contains(where: { $0.id == media }), seconds == nil || (seconds!.isFinite && seconds! >= 0), !text.isEmpty else { return }
        document.notes.append(MediaNote(mediaID: media, seconds: seconds, text: String(text.prefix(10_000)))); save()
    }
    func editNote(_ id: UUID, text: String) {
        guard let i = document.notes.firstIndex(where: { $0.id == id }), !text.isEmpty else { return }
        document.notes[i].text = String(text.prefix(10_000)); save()
    }
    func removeNote(_ id: UUID) { document.notes.removeAll { $0.id == id }; save() }
    func exportData(favorites: [ExportFavorite], preferences: BrowserPreferences) throws -> Data {
        var archive = UserDataArchive(); archive.library = document
        // Bookmarks reveal local permissions; progress reveals viewing history.
        for i in archive.library.media.indices { archive.library.media[i].fileBookmark = nil; archive.library.media[i].position = 0; archive.library.media[i].duration = nil; archive.library.media[i].lastPlayedAt = nil; archive.library.media[i].completed = false }
        archive.favorites = favorites.filter { LibraryAddress.clean($0.address) != nil }
        archive.browserSettings = ExportBrowserSettings(desktop: preferences.desktop, zoom: preferences.zoom, gestures: preferences.gestures,
            history: preferences.history, restoreTabs: preferences.restoreTabs, blockedSites: preferences.blockedSites, sitePreferences: preferences.sitePreferences)
        archive.appearance = preferences.appearance; archive.searchEngine = preferences.searchEngine; archive.skipSeconds = preferences.skipSeconds
        return try JSONEncoder().encode(archive)
    }
    func importData(_ data: Data) throws -> UserDataArchive {
        guard writable, data.count <= 20_000_000 else { throw LibraryError.invalid("Import zu groß oder lokaler Speicher gesperrt.") }
        let archive = try JSONDecoder().decode(UserDataArchive.self, from: data)
        guard archive.format == "DevnTube.user-data", archive.version == 1, archive.favorites.count <= 10_000,
              (5...60).contains(archive.skipSeconds), archive.favorites.allSatisfy({ $0.title.count <= 500 && LibraryAddress.clean($0.address) != nil }) else { throw LibraryError.invalid("Unbekanntes oder ungültiges Sicherungsformat.") }
        try archive.browserSettings?.validate()
        var merged = document; try merged.merge(archive.library)
        document = merged; guard save() else { throw LibraryError.invalid(error ?? "Import nicht gespeichert.") }; return archive
    }
}

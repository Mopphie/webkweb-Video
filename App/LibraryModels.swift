import Foundation

struct LibraryMedia: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var kind: MediaSourceKind
    var address: String = ""
    var fileBookmark: Data? = nil
    var addedAt = Date()
    var lastPlayedAt: Date? = nil
    var position = 0.0
    var duration: Double? = nil
    var completed = false
    var favorite: Bool? = nil
}
struct NamedPlaylist: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var mediaIDs: [UUID] = []
}
struct MediaNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var mediaID: UUID
    var seconds: Double?
    var text: String
    var createdAt = Date()
}
struct LibraryDocument: Codable, Equatable {
    var version = 1
    var media: [LibraryMedia] = []
    var playlists: [NamedPlaylist] = []
    var notes: [MediaNote] = []
}
struct ExportFavorite: Codable, Equatable {
    var title: String
    var address: String
}
struct ExportBrowserSettings: Codable {
    var desktop: Bool
    var zoom: Double
    var gestures: Bool
    var history: Bool
    var restoreTabs: Bool
    var blockedSites: [String]
    var sitePreferences: [String: SitePreference]
    func validate() throws {
        guard zoom.isFinite, (0.5...2).contains(zoom), blockedSites.count <= 10_000,
              blockedSites.allSatisfy(SiteNavigationPolicy.validBlockedHost), sitePreferences.count <= 10_000,
              sitePreferences.allSatisfy({ host, value in
                  AddressResolver.directURL("https://" + host)?.host == host && !host.contains("/") &&
                  value.zoom.isFinite && (0.5...2).contains(value.zoom)
              }) else { throw LibraryError.invalid("Ungültige Browser-Einstellungen.") }
    }
}
struct UserDataArchive: Codable {
    var format = "DevnTube.user-data"
    var version = 1
    var library = LibraryDocument()
    var favorites: [ExportFavorite] = []
    var appearance = AppAppearance.system
    var searchEngine = SearchEngine.google
    var skipSeconds = 10
    var browserSettings: ExportBrowserSettings? = nil
    // Deliberately no sessions, cookies, local file bookmarks, shared groups,
    // locks, website permissions, CloudKit identity or diagnostic state.
}
enum LibraryError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

extension LibraryDocument {
    func validated(importing: Bool = false) throws -> Self {
        guard version == 1, media.count <= 10_000, playlists.count <= 500, notes.count <= 20_000 else { throw LibraryError.invalid("Unbekanntes Format oder zu viele Einträge.") }
        var result = self, ids = Set<UUID>(), noteIDs = Set<UUID>(), listIDs = Set<UUID>()
        for item in media {
            guard ids.insert(item.id).inserted, item.title.count <= 500, item.position.isFinite, item.position >= 0,
                  item.duration == nil || (item.duration!.isFinite && item.duration! > 0),
                  !importing || item.fileBookmark == nil else { throw LibraryError.invalid("Ungültige Medien oder Dateiberechtigungen im Import.") }
            switch item.kind {
            case .website: guard LibraryAddress.clean(item.address) != nil else { throw LibraryError.invalid("Ungültiger oder vertraulicher Link.") }
            case .authorizedDirect: guard SourceCapabilities.directMediaURL(item.address) != nil else { throw LibraryError.invalid("Ungültige Direktquelle.") }
            case .localFile: guard item.address.isEmpty else { throw LibraryError.invalid("Dateipfade gehören nicht in die Datensicherung.") }
            }
        }
        for index in result.playlists.indices {
            guard listIDs.insert(result.playlists[index].id).inserted, !result.playlists[index].name.isEmpty,
                  result.playlists[index].name.count <= 100, result.playlists[index].mediaIDs.count <= 10_000 else { throw LibraryError.invalid("Ungültige Playlist.") }
            var seen = Set<UUID>()
            result.playlists[index].mediaIDs = result.playlists[index].mediaIDs.filter { ids.contains($0) && seen.insert($0).inserted }
        }
        for note in notes {
            guard noteIDs.insert(note.id).inserted, ids.contains(note.mediaID), note.text.count <= 10_000,
                  note.seconds == nil || (note.seconds!.isFinite && note.seconds! >= 0) else { throw LibraryError.invalid("Ungültige Notiz.") }
        }
        return result
    }
    /// Conflict rule: existing IDs win; identical addresses are linked to the
    /// existing item. Imported lists/notes remap those IDs, never overwrite.
    mutating func merge(_ incoming: Self) throws {
        let value = try incoming.validated(importing: true)
        var remap: [UUID: UUID] = [:]
        for item in value.media {
            if let old = media.first(where: { $0.id == item.id || (!$0.address.isEmpty && $0.address == item.address) }) { remap[item.id] = old.id }
            else { media.append(item); remap[item.id] = item.id }
        }
        for var list in value.playlists where !playlists.contains(where: { $0.id == list.id }) {
            var seen = Set<UUID>()
            list.mediaIDs = list.mediaIDs.compactMap { remap[$0] }.filter { seen.insert($0).inserted }; playlists.append(list)
        }
        for var note in value.notes where !notes.contains(where: { $0.id == note.id }) {
            if let id = remap[note.mediaID] { note.mediaID = id; notes.append(note) }
        }
        self = try validated()
    }
}

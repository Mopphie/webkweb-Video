import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct UserBackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor
struct LibraryHubView: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var savedPages: [SavedPage]
    @ObservedObject var library: LibraryStore
    @State private var search = ""
    @State private var selectedMedia: UUID?
    @State private var filter = "Alle"
    @State private var newestFirst = true
    @State private var playlistName = ""
    @State private var address = ""
    @State private var title = ""
    @State private var authorized = false
    @State private var fileImport = false
    @State private var dataImport = false
    @State private var dataExport = false
    @State private var archive: UserBackupFile?
    @State private var pendingImport: Data?
    @State private var importConfirmation = false
    @State private var message: String?
    private var media: [LibraryMedia] {
        library.document.media.filter {
            (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.address.localizedCaseInsensitiveContains(search)) &&
            (filter == "Alle" || filter == "Dateien" && $0.kind == .localFile || filter == "Links" && $0.kind != .localFile || filter == "Weitersehen" && $0.position > 0 && !$0.completed || filter == "Favoriten" && $0.favorite == true)
        }.sorted { newestFirst ? $0.addedAt > $1.addedAt : $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var body: some View {
        NavigationStack {
            List {
                if browser.current.isPrivate {
                    Section { Label("Normale Mediathek", systemImage: "exclamationmark.shield"); Text("Speichern und Abspielen sind hier nicht privat. Inhalte deines privaten Tabs werden nicht automatisch übernommen.").font(.footnote) }
                }
                Section {
                    favoritesAndHistoryLink
                    Picker("Inhalt", selection: $filter) { ForEach(["Alle", "Dateien", "Links", "Weitersehen", "Favoriten"], id: \.self) { Text($0) } }
                    Toggle("Neueste zuerst", isOn: $newestFirst)
                }
                Section("Web-Favoriten") {
                    ForEach(savedPages.filter { $0.favorite && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.address.localizedCaseInsensitiveContains(search)) }.sorted { $0.favoriteOrder < $1.favoriteOrder }) { page in
                        Button(page.title) { browser.open(page.address); dismiss() }
                            .contextMenu {
                                Button("Mit Playlists und Notizen organisieren") { selectedMedia = library.addLink(title: page.title, address: page.address) }
                                Button("Zur Linkqueue") { browser.enqueue(address: page.address, title: page.title) }
                            }
                    }
                }
                Section("Mediathek") {
                    ForEach(media) { item in
                        NavigationLink { MediaDetailView(library: library, mediaID: item.id, openBrowser: { browser.open($0); dismiss() }) } label: {
                            HStack {
                                Image(systemName: item.kind == .localFile ? "film" : item.kind == .authorizedDirect ? "play.rectangle" : "globe")
                                VStack(alignment: .leading) {
                                    Text(item.title).lineLimit(2)
                                    Text(item.kind == .localFile ? "Eigene Datei" : URL(string: item.address)?.host ?? "Link").font(.caption).foregroundStyle(.secondary)
                                    if let total = item.duration, total > 0, item.position > 0 { ProgressView(value: min(1, item.position / total)).accessibilityLabel(item.completed ? "Abgeschlossen" : "Wiedergabefortschritt") }
                                }
                            }
                        }.swipeActions { Button("Entfernen", role: .destructive) { if browser.nativePlayer.mediaID == item.id { browser.nativePlayer.close() }; browser.nativePlayer.removeFromQueue(item.id); library.remove(item.id) } }
                    }
                    if media.isEmpty { Text("Noch keine passenden Medien").foregroundStyle(.secondary) }
                }
                Section("Playlists") {
                    ForEach(library.document.playlists) { list in
                        NavigationLink(list.name) { PlaylistDetailView(library: library, playlistID: list.id, openBrowser: { browser.open($0); dismiss() }) }
                            .swipeActions { Button("Löschen", role: .destructive) { library.removePlaylist(list.id) } }
                    }
                    HStack {
                        TextField("Neue Playlist", text: $playlistName)
                        Button("Erstellen") { library.createPlaylist(playlistName); playlistName = "" }.disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section("Hinzufügen") {
                    Button("Eigene Datei öffnen", systemImage: "folder") { fileImport = true }
                    TextField("Titel", text: $title)
                    TextField("HTTPS-Medienadresse oder Website", text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Website-Link speichern") { if library.addLink(title: title.isEmpty ? URL(string: address)?.host ?? "Link" : title, address: address) != nil { address = ""; title = "" } }
                        .disabled(LibraryAddress.clean(address) == nil)
                    Toggle("Ich darf diese Direktquelle außerhalb ihres Websiteplayers nutzen", isOn: $authorized)
                    Button("Autorisierte Direktquelle speichern") {
                        if library.addLink(title: title.isEmpty ? "Direktquelle" : title, address: address, kind: .authorizedDirect) != nil { address = ""; title = ""; authorized = false }
                    }.disabled(!authorized || SourceCapabilities.directMediaURL(address) == nil)
                    Text("Keine Streamsuche oder Plattform-Downloads. Signierte/zugangsgeschützte URLs werden nicht dauerhaft gespeichert. Die Bestätigung ersetzt keine Rechteprüfung des Anbieters.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Datensicherung") {
                    Button("Eigene Daten exportieren", systemImage: "square.and.arrow.up") {
                        do {
                            archive = UserBackupFile(data: try library.exportData(favorites: savedPages.filter(\.favorite).map { ExportFavorite(title: $0.title, address: $0.address) }, preferences: browser.options)); dataExport = true
                        } catch { message = error.localizedDescription }
                    }
                    Button("Sicherung importieren", systemImage: "square.and.arrow.down") { dataImport = true }
                    Text("Ohne Verlauf, Cookies, private Sitzungen, Dateiberechtigungen oder Wiedergabefortschritt. Vorhandene IDs und Favoriten gewinnen bei Konflikten; neue Einträge werden ergänzt. Dateien nach Import erneut auswählen.").font(.caption).foregroundStyle(.secondary)
                }
                if let error = library.error { Text(error).foregroundStyle(.red) }
            }
            .navigationDestination(item: $selectedMedia) { id in MediaDetailView(library: library, mediaID: id, openBrowser: { browser.open($0); dismiss() }) }
            .searchable(text: $search, prompt: "Titel oder Quelle")
            .navigationTitle("Mediathek")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .fileImporter(isPresented: $fileImport, allowedContentTypes: [.movie, .audio], allowsMultipleSelection: true) { result in
                do { let urls = try result.get(); for url in urls { let id = try library.addFile(url); if urls.count == 1 { browser.nativePlayer.open(id); dismiss() } } }
                catch { message = error.localizedDescription }
            }
            .fileExporter(isPresented: $dataExport, document: archive, contentType: .json, defaultFilename: "DevnTube-Sicherung") { result in if case .failure(let error) = result { message = error.localizedDescription } }
            .fileImporter(isPresented: $dataImport, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(), access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    guard data.count <= 20_000_000 else { throw LibraryError.invalid("Import zu groß.") }
                    let value = try JSONDecoder().decode(UserDataArchive.self, from: data)
                    guard value.version == 1, value.format == "DevnTube.user-data" else { throw LibraryError.invalid("Unbekanntes Sicherungsformat.") }
                    _ = try value.library.validated(importing: true); pendingImport = data; importConfirmation = true
                } catch { message = error.localizedDescription }
            }
            .confirmationDialog("Sicherung mit lokalen Daten zusammenführen? Bestehende Einträge bleiben erhalten.", isPresented: $importConfirmation, titleVisibility: .visible) {
                Button("Zusammenführen") { performImport() }
                Button("Abbrechen", role: .cancel) { pendingImport = nil }
            }
            .alert("Mediathek", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
        }
    }
    private var favoritesAndHistoryLink: some View {
        NavigationLink {
            LibraryView(open: openSavedPage, didChange: saveSavedPages)
        } label: {
            Label("Favoriten und Verlauf", systemImage: "star")
        }
    }

    private func openSavedPage(_ address: String) {
        browser.open(address)
        dismiss()
    }

    private func saveSavedPages() { try? context.save() }

    private func performImport() {
        defer { pendingImport = nil }
        do {
            guard let data = pendingImport else { return }
            let imported = try library.importData(data)
            for favorite in imported.favorites where !savedPages.contains(where: { $0.favorite && $0.address == favorite.address }) {
                if let existing = savedPages.first(where: { $0.address == favorite.address }) { existing.favorite = true }
                else { context.insert(SavedPage(title: favorite.title, address: favorite.address, favorite: true)) }
            }
            try context.save()
            browser.options.appearance = imported.appearance; browser.options.searchEngine = imported.searchEngine; browser.options.skipSeconds = imported.skipSeconds
            if let settings = imported.browserSettings {
                browser.options.desktop = settings.desktop; browser.options.zoom = settings.zoom; browser.options.gestures = settings.gestures
                browser.options.history = settings.history; browser.options.restoreTabs = settings.restoreTabs
                browser.options.blockedSites = settings.blockedSites; browser.options.sitePreferences = settings.sitePreferences
            }
            message = "Import zusammengeführt. Lokale Dateiberechtigungen bei Bedarf erneut auswählen."
        } catch { message = "Import nicht vollständig übernommen: \(error.localizedDescription)" }
    }
}

@MainActor
struct MediaDetailView: View {
    @EnvironmentObject private var browser: BrowserModel
    @ObservedObject var library: LibraryStore
    let mediaID: UUID
    let openBrowser: (String) -> Void
    @State private var title = ""
    @State private var note = ""
    @State private var withTime = true
    @State private var editingNote: UUID?
    @State private var relink = false
    @State private var fileError: String?
    private var item: LibraryMedia? { library.document.media.first { $0.id == mediaID } }
    var body: some View {
        Form {
            if let item {
                Section {
                    TextField("Eigener Titel", text: $title).onSubmit { library.rename(mediaID, title: title) }
                    Button("Titel speichern") { library.rename(mediaID, title: title) }
                    Button(item.favorite == true ? "Favorit entfernen" : "Als Medienfavorit markieren", systemImage: item.favorite == true ? "star.fill" : "star") { library.toggleFavorite(mediaID) }
                    if item.kind == .website { Button("Website öffnen") { openBrowser(item.address) } }
                    else {
                        Button(item.completed || item.position == 0 ? "Abspielen" : "Weitersehen") { browser.nativePlayer.open(mediaID) }
                        Button("Zur Queue") { browser.nativePlayer.enqueue(mediaID) }
                    }
                    if item.kind == .localFile { Button("Datei erneut auswählen") { relink = true } }
                    if let fileError { Text(fileError).foregroundStyle(.red) }
                    if !item.address.isEmpty, let url = URL(string: item.address) { ShareLink(item: url) }
                    Text(SourceCapabilities.forSource(item.kind).explanation).font(.caption).foregroundStyle(.secondary)
                }
                Section("Zu Playlist hinzufügen") {
                    if library.document.playlists.isEmpty { Text("Lege zuerst eine Playlist in der Mediathek an.") }
                    ForEach(library.document.playlists) { list in Button(list.name) { library.add(mediaID, to: list.id) } }
                }
                Section("Eigene Zeitmarken und Notizen") {
                    ForEach(library.document.notes.filter { $0.mediaID == mediaID }) { entry in
                        VStack(alignment: .leading) {
                            Text(entry.text).textSelection(.enabled)
                            if let seconds = entry.seconds, item.kind != .website {
                                Button("Zu \(Int(seconds)) s springen") { browser.nativePlayer.open(mediaID, seekTo: seconds) }
                            }
                            ShareLink(item: entry.text + (entry.seconds.map { " (\(Int($0)) s)" } ?? "") + (item.address.isEmpty ? "" : "\n" + item.address))
                        }.swipeActions { Button("Löschen", role: .destructive) { library.removeNote(entry.id) } }
                        .swipeActions(edge: .leading) { Button("Bearbeiten") { note = entry.text; editingNote = entry.id } }
                    }
                    TextField("Notiz", text: $note, axis: .vertical)
                    if browser.nativePlayer.mediaID == mediaID && browser.nativePlayer.duration != nil { Toggle("Aktuellen Zeitpunkt speichern", isOn: $withTime) }
                    Button("Notiz speichern") {
                        let time: Double? = withTime && browser.nativePlayer.mediaID == mediaID && browser.nativePlayer.duration != nil ? browser.nativePlayer.time : nil
                        if let id = editingNote { library.editNote(id, text: note) } else { library.addNote(media: mediaID, seconds: time, text: note) }; note = ""; editingNote = nil
                    }.disabled(note.isEmpty)
                }
            } else { Text("Eintrag wurde entfernt.") }
        }.navigationTitle("Medium").onAppear { title = item?.title ?? "" }
        .fileImporter(isPresented: $relink, allowedContentTypes: [.movie, .audio]) { result in
            do {
                let url = try result.get()
                if browser.nativePlayer.mediaID == mediaID { browser.nativePlayer.close() }
                try library.relinkFile(mediaID, to: url); fileError = nil
            } catch { fileError = error.localizedDescription }
        }
    }
}

@MainActor
struct PlaylistDetailView: View {
    @EnvironmentObject private var browser: BrowserModel
    @ObservedObject var library: LibraryStore
    let playlistID: UUID
    let openBrowser: (String) -> Void
    @State private var name = ""
    private var list: NamedPlaylist? { library.document.playlists.first { $0.id == playlistID } }
    var body: some View {
        List {
            if let list {
                TextField("Listenname", text: $name).onSubmit { library.renamePlaylist(playlistID, name: name) }
                Button("Umbenennen") { library.renamePlaylist(playlistID, name: name) }
                let nativeIDs = list.mediaIDs.filter { id in library.document.media.contains { $0.id == id && $0.kind != .website } }
                Button("Native Medien als Queue abspielen") { browser.nativePlayer.playPlaylist(nativeIDs) }.disabled(nativeIDs.isEmpty)
                Text("Website-Links einzeln öffnen; kein automatischer Plattformplayer-Wechsel.").font(.caption).foregroundStyle(.secondary)
                ForEach(list.mediaIDs, id: \.self) { id in
                    if let item = library.document.media.first(where: { $0.id == id }) {
                        NavigationLink(item.title) { MediaDetailView(library: library, mediaID: id, openBrowser: openBrowser) }
                            .swipeActions { Button("Aus Liste entfernen", role: .destructive) { library.remove(id, from: playlistID) } }
                    }
                }.onMove { library.movePlaylistItems(playlistID, from: $0, to: $1) }
            }
        }.navigationTitle(list?.name ?? "Playlist").toolbar { EditButton() }.onAppear { name = list?.name ?? "" }
    }
}

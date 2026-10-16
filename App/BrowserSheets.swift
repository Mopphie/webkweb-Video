import SwiftUI
import SwiftData
import WebKit
import LocalAuthentication

enum LibrarySection: String, CaseIterable { case favorites = "Favoriten", history = "Verlauf" }

@MainActor
struct AddressEntryView: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            Form {
                TextField("Suchen oder Adresse", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.webSearch).submitLabel(.go).focused($focused).onSubmit(open)
                    .accessibilityLabel("Suchen oder Adresse")
                Button("Öffnen", action: open).disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.navigationTitle("Adresse")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
                .task { address = browser.current.address; focused = true }
        }
    }
    private func open() { browser.open(address); dismiss() }
}

@MainActor
struct LibraryView: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedPage.visitedAt, order: .reverse) private var pages: [SavedPage]
    let open: (String) -> Void
    let didChange: () -> Void
    var initialSection: LibrarySection = .favorites
    @State private var selectedSection: LibrarySection = .favorites
    @State private var search = ""
    @State private var clearHistory = false
    @State private var clearProgress = false
    @State private var editingPage: SavedPage?
    private var favorites: [SavedPage] { pages.filter(\.favorite).sorted { $0.favoriteOrder < $1.favoriteOrder } }
    private var filtered: [SavedPage] {
        (selectedSection == .favorites ? favorites : pages.filter { !$0.favorite && $0.isHistory }).filter {
            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.address.localizedCaseInsensitiveContains(search)
        }
    }
    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { page in row(page) }
                    .onMove { from, to in
                        guard selectedSection == .favorites, search.isEmpty else { return }
                        var ordered = favorites; ordered.move(fromOffsets: from, toOffset: to)
                        for (index, page) in ordered.enumerated() { page.favoriteOrder = Double(index + 1) }
                        didChange()
                    }
                if filtered.isEmpty { Text(selectedSection == .favorites ? "Noch keine Favoriten." : "Noch kein Verlauf.").foregroundStyle(.secondary) }
            }
            .safeAreaInset(edge: .top) {
                Picker("Gespeicherte Seiten", selection: $selectedSection) {
                    ForEach(LibrarySection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 8)
            }
            .onAppear { selectedSection = initialSection }
            .searchable(text: $search, prompt: "Titel oder Adresse")
            .navigationTitle("Deine Seiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if selectedSection == .favorites && search.isEmpty { EditButton() }
                    else { Button("Verlauf löschen", systemImage: "trash") { clearHistory = true } }
                }
            }
            .confirmationDialog("Verlauf löschen? Favoriten bleiben.", isPresented: $clearHistory, titleVisibility: .visible) {
                Button("Verlauf löschen", role: .destructive) { for page in pages { if page.favorite { page.visitedAt = .distantPast; page.isHistory = false } else { context.delete(page) } }; browser.clearRecentNavigation(); didChange() }
            }
            .sheet(item: $editingPage) { page in FavoriteEditor(page: page, didSave: didChange) }
        }
    }
    private func row(_ page: SavedPage) -> some View {
        Button { open(page.address) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(page.title).foregroundStyle(.primary).lineLimit(2)
                Text(page.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .contextMenu {
            Button("Im Hintergrund öffnen", systemImage: "square.on.square") { browser.openBackground(page.address, isPrivate: false) }
            Button("Zur Queue", systemImage: "text.badge.plus") { browser.enqueue(address: page.address, title: page.title) }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { context.delete(page); didChange() } label: { Label("Löschen", systemImage: "trash") }
            if page.favorite { Button { editingPage = page } label: { Label("Bearbeiten", systemImage: "pencil") }.tint(.blue) }
        }
        .swipeActions(edge: .leading) {
            Button {
                page.favorite.toggle()
                if !page.favorite && !page.isHistory { context.delete(page) }
                if page.favorite { page.favoriteOrder = (favorites.map(\.favoriteOrder).max() ?? 0) + 1 }
                didChange()
            } label: { Label(page.favorite ? "Entfernen" : "Favorit", systemImage: page.favorite ? "star.slash" : "star") }.tint(.orange)
        }
    }
}

@MainActor
private struct FavoriteEditor: View {
    let page: SavedPage
    let didSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var address = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Titel", text: $title)
                TextField("Adresse", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Favorit bearbeiten")
                .onAppear { title = page.title; address = page.address }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") {
                            guard let url = AddressResolver.directURL(address) else { error = "HTTP(S)-Adresse ohne Zugangsdaten erforderlich."; return }
                            page.title = title.isEmpty ? (url.host ?? "Favorit") : title
                            if page.address != url.absoluteString { page.isHistory = false; page.visitedAt = .distantPast }
                            page.address = url.absoluteString; page.customTitle = !title.isEmpty; didSave(); dismiss()
                        }
                    }
                }
        }
    }
}

@MainActor
struct TabsView: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var tabGroup = ""
    var body: some View {
        NavigationStack {
            List {
                ForEach(browser.tabs.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.address.localizedCaseInsensitiveContains(search) || $0.group.localizedCaseInsensitiveContains(search) }.sorted { $0.pinned && !$1.pinned }) { tab in
                    TabRow(tab: tab, selected: tab.id == browser.selectedID) {
                        browser.selectedID = tab.id
                        dismiss()
                    }
                    .swipeActions { Button("Schließen", role: .destructive) { browser.close(tab.id) } }
                    .contextMenu {
                        Button(tab.pinned ? "Lösen" : "Anheften") { browser.objectWillChange.send(); tab.pinned.toggle(); browser.persistSession() }
                        Button("Gruppe zuweisen") { browser.objectWillChange.send(); tab.group = String(tabGroup.prefix(60)); browser.persistSession() }
                        Button("Gruppe entfernen") { browser.objectWillChange.send(); tab.group = ""; browser.persistSession() }
                    }
                }
                Section("Tabgruppen") {
                    TextField("Gruppenname", text: $tabGroup)
                    Text("Gruppen über das Tabmenü zuweisen; nach Namen suchen. Private Gruppen bleiben flüchtig.").font(.caption)
                    Button("Geschlossenen normalen Tab wiederherstellen") { browser.reopenClosedTab() }.disabled(browser.closedTabs.isEmpty || browser.tabs.count >= 12)
                    Button("Private Sitzung beenden", role: .destructive) { browser.endPrivateSession() }.disabled(!browser.tabs.contains(where: \.isPrivate))
                }
            }
            .searchable(text: $search, prompt: "Tabs oder Gruppen")
            .navigationTitle("Tabs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Neuer Tab", systemImage: "plus") { browser.addTab(); dismiss() }
                        Button("Privater Tab", systemImage: "hand.raised") { browser.addTab(isPrivate: true); dismiss() }
                    } label: { Image(systemName: "plus") }
                }
            }
        }
    }
}

@MainActor
private struct TabRow: View {
    @ObservedObject var tab: BrowserTab
    let selected: Bool
    let select: () -> Void
    var body: some View {
        Button(action: select) {
            HStack {
                Image(systemName: tab.playing ? (tab.muted ? "speaker.slash" : "speaker.wave.2") : "globe").foregroundStyle(.teal)
                VStack(alignment: .leading) {
                    Text((tab.pinned ? "📌 " : "") + tab.title).foregroundStyle(.primary).lineLimit(2)
                    if !tab.group.isEmpty { Text(tab.group).font(.caption).foregroundStyle(.teal) }
                    if tab.isPrivate { Text("Privat").font(.caption) }
                    Text(tab.address.isEmpty ? "Startseite" : tab.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill") }
            }
        }
    }
}

@MainActor
struct SleepTimerView: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var hours = 0
    @State private var minutes = 30
    @State private var seconds = 0
    @State private var videos = 1
    var body: some View {
        NavigationStack {
            Form {
                Picker("Pause nach", selection: $mode) {
                    Text("Dauer").tag(0); Text("Videos").tag(1); Text("Aktuelles Video").tag(2); Text("Queue-Ende").tag(3)
                }
                if mode == 0 {
                    Stepper("\(hours) Stunden", value: $hours, in: 0...23)
                    Stepper("\(minutes) Minuten", value: $minutes, in: 0...59)
                    Stepper("\(seconds) Sekunden", value: $seconds, in: 0...59)
                } else if mode == 1 { Stepper("\(videos) Videos", value: $videos, in: 1...100) }
                Button("Timer starten") {
                    if mode == 0 { browser.sleep(seconds: hours * 3600 + minutes * 60 + seconds) }
                    else if mode == 3 { browser.sleepAfterQueue() }
                    else { browser.sleep(videos: mode == 2 ? 1 : videos, currentVideoOnly: mode == 2) }
                    dismiss()
                }.disabled(mode == 0 ? (hours * 3600 + minutes * 60 + seconds == 0) : (browser.nativePlayer.isOpen ? browser.nativePlayer.duration == nil : browser.current.activeMediaKind != "video" || !browser.current.canControlMedia || browser.current.duration == nil || mode == 3))
                Text("Zeitdauer läuft auch bei Pause und Quellenwechsel weiter. Native Video-/Queue-Enden zählen tatsächliche Endereignisse. Bei Live-Medien gibt es keine Ende-Option. Während nativer Audio-/PiP-/AirPlay-Wiedergabe wird der Zeit-Timer geprüft; für suspendierte Webseiten erst nach Rückkehr. Exakte Ausführung während Gerätesperre muss am Gerät geprüft werden.")
                    .font(.caption).foregroundStyle(.secondary)
                if browser.sleepPlan.deadline != nil { Button("Um 10 Minuten verlängern") { browser.extendSleep() } }
                if browser.sleepPlan.isActive || browser.sleepAfterNativeQueue { Button("Timer abbrechen", role: .destructive) { browser.cancelSleep(); dismiss() } }
            }.navigationTitle("Sleep-Timer")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var clearWebsiteData = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Browser") {
                    Picker("Suchmaschine", selection: $browser.options.searchEngine) {
                        ForEach(SearchEngine.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Desktopansicht", isOn: $browser.options.desktop)
                    LabeledContent("Seitenzoom", value: "\(Int(browser.options.zoom * 100)) %")
                    Slider(value: $browser.options.zoom, in: 0.5...2, step: 0.1)
                    Button("Aktuelle Seite neu laden") { browser.current.reload() }.disabled(browser.current.address.isEmpty)
                    Toggle("Gestenfläche zum Spulen", isOn: $browser.gesturesEnabled)
                }
                Section("Wiedergabe und Darstellung") {
                    Picker("Sprungweite", selection: $browser.options.skipSeconds) { ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) Sekunden").tag($0) } }
                    Picker("Erscheinungsbild", selection: $browser.options.appearance) { ForEach(AppAppearance.allCases) { Text($0.title).tag($0) } }
                    Text("Native Medien unterstützen Hintergrund-Audio. Websitefunktionen bleiben beim jeweiligen Anbieter; keine Premium-Freischaltung.").font(.caption)
                }
                Section("Website-Einstellungen") {
                    if let host = URL(string: browser.current.address)?.host, !browser.current.isPrivate {
                        Text(host)
                        Button("Aktuelle Browseransicht für diese Website speichern") { browser.setSitePreference(desktop: browser.options.desktop, zoom: browser.options.zoom) }
                        Button("Website-Einstellung zurücksetzen") { browser.options.sitePreferences.removeValue(forKey: host); browser.current.applyAppearance() }
                    } else { Text("Im Privatmodus werden keine Website-Einstellungen dauerhaft gespeichert.").font(.caption) }
                    NavigationLink("Website-Sperrliste") { FilterSourcesView() }
                }
                Section("Lokale Daten") {
                    Toggle("Verlauf speichern", isOn: $browser.options.history)
                    Toggle("Normale Tabs wiederherstellen", isOn: $browser.options.restoreTabs)
                    Toggle("Favoriten für Widgets und Siri freigeben", isOn: $browser.options.shareFavoritesWithSystem)
                    Toggle("App mit Gerätecode / Biometrie sperren", isOn: Binding(get: { browser.options.privateLock }, set: { value in
                        if value { var failure: NSError?; guard LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &failure) else { browser.notice = "Richte zuerst einen Gerätecode in iOS ein."; return } }
                        browser.options.privateLock = value
                    }))
                    Text("Die Sperre benötigt einen eingerichteten Gerätecode. Sie ist keine zusätzliche Datenverschlüsselung. Private Tabs verwenden flüchtigen Webspeicher, keine Wiederherstellung, Diagnose oder System-PiP. Privates Website-Audio wird beim Appwechsel pausiert. Speichern außerhalb des Privatbereichs benötigt Bestätigung. Privat bedeutet keine Anonymität im Netz.").font(.caption).foregroundStyle(.secondary)
                    Button(browser.wipingData ? "Wird gelöscht …" : "Website-Daten löschen", role: .destructive) { clearWebsiteData = true }.disabled(browser.wipingData)
                }
                Section("iCloud") {
                    Text("iCloud-Abgleich ist nicht eingerichtet.")
                    Text("iCloud ist in dieser Version nicht verfügbar.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Datenschutz & Support") {
                    NavigationLink("Datenschutz") { PrivacyView() }
                    NavigationLink("Lizenzen") { ThirdPartyNoticesView() }
                    if let url = ReleaseConfiguration.privacyURL { Link("Öffentliche Datenschutzerklärung", destination: url) }
                    if let url = ReleaseConfiguration.supportURL { Link("Support", destination: url) }
                    if !ReleaseConfiguration.operatorContact.isEmpty { Text(ReleaseConfiguration.operatorContact).font(.footnote) }
                }
                Section {
                    Text("Video-Funktionen hängen von iOS und dem Webseitenplayer ab.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Einstellungen")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
                .confirmationDialog("Alle aktiven Seiten schließen und Website-Daten löschen?", isPresented: $clearWebsiteData, titleVisibility: .visible) {
                    Button("Schließen & löschen", role: .destructive) { Task { await browser.wipeWebsiteData() } }
                }
        }
    }
}

@MainActor
struct AirPlayView: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var tab: BrowserTab
    var body: some View {
        NavigationStack {
            Form {
                Section("AirPlay") {
                    HStack { Text("Ausgabegerät wählen"); Spacer(); AirPlayControl().frame(width: 44, height: 44) }
                    Text("Für Websitevideos nutze die von der Website angebotene AirPlay-Funktion. Der Systemdialog alleine bestätigt keine Video-Unterstützung.")
                }
                Section {
                    Text("AirPlay verwendet die Systemrouten von iOS. Verfügbarkeit und Wiedergabe hängen von Webseite, Gerät und Netzwerk ab.")
                }.font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("AirPlay")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}

@MainActor
struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Datenschutz").font(.largeTitle.bold())
                Text("DevnTube speichert normale Favoriten, Verlauf und eigene Mediathekdaten lokal. Private Tabs nutzen nicht persistenten WebKit-Speicher und werden weder wiederhergestellt noch exportiert. Sie senden keine Inhalte an Widgets, Siri oder App-Diagnosen. Bewusstes Speichern verlässt nach Bestätigung den Privatbereich.")
                Text("Websites und Suchanbieter erhalten Browseranfragen einschließlich IP-Adresse und können eigene Cookies oder Tracker nutzen. Kein eigenes Analytics-, Werbe- oder Proxy-Backend. Es gibt keine Filterlisten-Abrufe. Website-Daten und Verlauf lassen sich getrennt löschen.")
                Text("Die Freigabe normaler Favoriten für Widgets und Siri ist optional. iCloud ist nicht eingerichtet. Exporte enthalten nur eigene ausgewählte App-Daten, keine Cookies oder Sitzungen. Dateiberechtigungen bleiben lokal. Native Medien können System-Medienanzeigen und AirPlay verwenden; private Website-Wiedergabe wird beim Appwechsel pausiert.")
                Text("Die App-Sperre und verdeckte App-Umschalteransicht ersetzen keine vollständige Verschlüsselung oder Anonymität. Betriebssystem und Websites haben eigene Datenschutzregeln.")
                Text(ReleaseConfiguration.operatorContact.isEmpty ? "Anbieter- und Kontaktangaben sind noch nicht hinterlegt." : ReleaseConfiguration.operatorContact)
                if let url = ReleaseConfiguration.privacyURL { Link("Vollständige Datenschutzerklärung", destination: url) }
                if let url = ReleaseConfiguration.supportURL { Link("Support", destination: url) }
            }.padding(24).frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity)
        }.navigationTitle("Datenschutz").navigationBarTitleDisplayMode(.inline)
    }
}

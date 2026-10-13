import SwiftUI
import SwiftData
import WebKit

enum LibrarySection: String, CaseIterable { case favorites = "Favoriten", history = "Verlauf" }

@MainActor
struct LibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedPage.visitedAt, order: .reverse) private var pages: [SavedPage]
    let open: (String) -> Void
    let didChange: () -> Void
    var initialSection: LibrarySection = .favorites
    @State private var selectedSection: LibrarySection = .favorites
    @State private var search = ""
    @State private var clearHistory = false
    @State private var editingPage: SavedPage?
    private var favorites: [SavedPage] { pages.filter(\.favorite).sorted { $0.favoriteOrder < $1.favoriteOrder } }
    private var filtered: [SavedPage] {
        (selectedSection == .favorites ? favorites : pages.filter { !$0.favorite }).filter {
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
                Button("Verlauf löschen", role: .destructive) { for page in pages where !page.favorite { context.delete(page) }; didChange() }
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
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { context.delete(page); didChange() } label: { Label("Löschen", systemImage: "trash") }
            if page.favorite { Button { editingPage = page } label: { Label("Bearbeiten", systemImage: "pencil") }.tint(.blue) }
        }
        .swipeActions(edge: .leading) {
            Button {
                page.favorite.toggle()
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
    var body: some View {
        NavigationStack {
            List {
                ForEach(browser.tabs) { tab in
                    TabRow(tab: tab, selected: tab.id == browser.selectedID) {
                        browser.selectedID = tab.id
                        dismiss()
                    }
                    .swipeActions {
                        Button("Schließen", role: .destructive) { browser.close(tab.id) }
                    }
                }
            }
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
                Image(systemName: tab.playing ? "speaker.wave.2" : "globe").foregroundStyle(.teal)
                VStack(alignment: .leading) {
                    Text(tab.title).foregroundStyle(.primary).lineLimit(2)
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
                    Text("Dauer").tag(0); Text("Videos").tag(1); Text("Aktuelles Video").tag(2)
                }
                if mode == 0 {
                    Stepper("\(hours) Stunden", value: $hours, in: 0...23)
                    Stepper("\(minutes) Minuten", value: $minutes, in: 0...59)
                    Stepper("\(seconds) Sekunden", value: $seconds, in: 0...59)
                } else if mode == 1 { Stepper("\(videos) Videos", value: $videos, in: 1...100) }
                Button("Timer starten") {
                    if mode == 0 { browser.sleep(seconds: hours * 3600 + minutes * 60 + seconds) }
                    else { browser.sleep(videos: mode == 2 ? 1 : videos, currentVideoOnly: mode == 2) }
                    dismiss()
                }.disabled(mode == 0 ? (hours * 3600 + minutes * 60 + seconds == 0) : (browser.current.activeMediaKind != "video" || CastService.shared.isControllingMedia))
                Text("Nur der primäre Webseiten-Videoplayer zählt. Kein Live-/Cast-Zähler. Zeit-Timer bleibt nach Neustart erhalten; private Tab-Zähler werden nicht gespeichert. Ende-des-aktuellen-Videos wird nach Neustart verworfen. Eine suspendierte App kann erst beim Fortsetzen pausieren.")
                    .font(.caption).foregroundStyle(.secondary)
                if browser.sleepPlan.isActive { Button("Timer abbrechen", role: .destructive) { browser.cancelSleep(); dismiss() } }
            }.navigationTitle("Sleep-Timer")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var rules = RuleStore.shared
    @State private var clearWebsiteData = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Browser") {
                    Picker("Suchmaschine", selection: $browser.options.searchEngine) {
                        ForEach(SearchEngine.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Desktop-Kennung", isOn: $browser.options.desktop)
                    LabeledContent("Seitenzoom", value: "\(Int(browser.options.zoom * 100)) %")
                    Slider(value: $browser.options.zoom, in: 0.5...2, step: 0.1)
                    Button("Aktuelle Seite neu laden") { browser.current.reload() }.disabled(browser.current.address.isEmpty)
                    Toggle("Gestenfläche zum Spulen", isOn: $browser.gesturesEnabled)
                }
                Section("Netzwerkfilter") {
                    Toggle("Filter aktiv", isOn: $browser.blockingEnabled)
                    Text(rules.status).font(.caption).foregroundStyle(.secondary)
                    NavigationLink("Filterquellen & Import") { FilterSourcesView() }
                    NavigationLink("Erlaubte Webseiten") { FilterAllowlistView() }
                    Button(rules.refreshing ? "Wird aktualisiert …" : "Jetzt aktualisieren") { Task { await rules.refreshIfNeeded(force: true) } }.disabled(rules.refreshing)
                    if let date = rules.lastUpdate { Text(date.formatted()).font(.caption).foregroundStyle(.secondary) }
                }
                Section("SponsorBlock") {
                    Toggle("Segmente überspringen", isOn: $browser.sponsorBlockEnabled)
                    NavigationLink("Auf Webseiten deaktivieren") { FilterAllowlistView(sponsor: true) }
                    ForEach(SponsorSegment.categories, id: \.self) { category in
                        Toggle(SponsorCategoryLabels.title(category), isOn: Binding(
                            get: { browser.options.categories.contains(category) },
                            set: { enabled in if enabled { browser.options.categories.insert(category) } else { browser.options.categories.remove(category) } }))
                    }
                    Text("Bei Aktivierung erhält sponsor.ajay.app die YouTube-Video-ID und IP-Adresse. Kategorien gelten auch für YouTube-Frames. Skip und Zurück stehen im Player bereit.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Lokale Daten") {
                    Toggle("Verlauf speichern", isOn: $browser.options.history)
                    Toggle("Normale Tabs wiederherstellen", isOn: $browser.options.restoreTabs)
                    Text("Private Tabs verwenden einen separaten flüchtigen Webspeicher; kein Verlauf und keine Wiederherstellung. Manuell gespeicherte Favoriten bleiben erhalten. Privat bedeutet keine Anonymität im Netz.").font(.caption).foregroundStyle(.secondary)
                    Button(browser.wipingData ? "Wird gelöscht …" : "Website-Daten löschen", role: .destructive) { clearWebsiteData = true }.disabled(browser.wipingData)
                }
                Section("iCloud") {
                    Toggle("Verlauf & Favoriten synchronisieren", isOn: $browser.options.cloudSync).disabled(ReleaseConfiguration.cloudContainer == nil && !browser.options.cloudSync)
                    Text(ReleaseConfiguration.cloudContainer == nil ? "Noch nicht provisioniert. Der Entwickler muss eine echte CloudKit-Container-ID mit dem lokalen Konfigurationsskript und Apple-Capabilities hinterlegen." : "Änderung gilt nach App-Neustart. SwiftData nutzt denselben lokalen Store; iCloud synchronisiert Verlauf/Favoriten, keine privaten Tabs.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Datenschutz & Support") {
                    NavigationLink("Datenschutz") { PrivacyView() }
                    NavigationLink("Veröffentlichungsangaben") { ReleaseDetailsView() }
                    if let url = ReleaseConfiguration.publicURL(browser.options.privacyURL) { Link("Öffentliche Datenschutzerklärung", destination: url) }
                    if let url = ReleaseConfiguration.publicURL(browser.options.supportURL) { Link("Support", destination: url) }
                }
                Section {
                    Text("Autoplay, PiP, AirPlay, Hintergrundaudio und Clock-Stop hängen von iOS und Webseite ab. Keine Zusage für werbefreies YouTube oder App-Store-Zulassung.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Einstellungen")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
                .confirmationDialog("Alle aktiven Seiten schließen und Website-Daten löschen?", isPresented: $clearWebsiteData, titleVisibility: .visible) {
                    Button("Schließen & löschen", role: .destructive) { Task { await browser.wipeWebsiteData() } }
                }
        }
    }
}

enum SponsorCategoryLabels {
    static func title(_ value: String) -> String {
        ["sponsor": "Sponsor", "intro": "Intro", "outro": "Outro", "selfpromo": "Eigenwerbung"][value] ?? value
    }
}

@MainActor
private struct ReleaseDetailsView: View {
    @EnvironmentObject private var browser: BrowserModel
    var body: some View {
        Form {
            TextField("Datenschutz-URL (HTTPS)", text: $browser.options.privacyURL).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Support-URL (HTTPS)", text: $browser.options.supportURL).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Verantwortlicher & Kontakt", text: $browser.options.operatorContact, axis: .vertical)
            Text("Diese Angaben sind noch offen. Erst echte öffentlich erreichbare URLs und Betreiberangaben hinterlegen; keine Platzhalter als Release-Angaben veröffentlichen.").font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("Veröffentlichung")
    }
}

@MainActor
struct CastView: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var tab: BrowserTab
    @ObservedObject private var cast = CastService.shared
    var body: some View {
        NavigationStack {
            Form {
                Section("AirPlay") {
                    HStack { Text("Ausgabegerät wählen"); Spacer(); AirPlayControl().frame(width: 40, height: 40) }
                    Button("AirPlay für Webseitenvideo öffnen") { tab.runMedia("globalThis.__webkweb?.airplay()") }
                }
                Section("Google Cast") {
                    #if canImport(GoogleCast)
                    HStack { Text("Cast-Gerät wählen"); Spacer(); CastDeviceButton().frame(width: 40, height: 40) }
                    Button("Direkten Medienlink übertragen") {
                        guard let media = tab.directMedia else { return }
                        _ = cast.load(media, title: tab.title, at: tab.playbackTime)
                    }.disabled(tab.directMedia == nil)
                    #else
                    Text("Google Cast ist eine optionale Build-Erweiterung und in diesem Standardbuild nicht enthalten.")
                    #endif
                    if let media = tab.directMedia { Text(media.url.host ?? "Medienlink").font(.caption).foregroundStyle(.secondary) }
                    else { Text("Kein übertragbarer direkter HTTP(S)-Medienlink erkannt.").font(.caption).foregroundStyle(.secondary) }
                    if !cast.status.isEmpty { Text(cast.status).font(.caption) }
                    if cast.isControllingMedia {
                        Button(cast.isPlaying ? "Cast pausieren" : "Cast abspielen") { browser.togglePlayback() }
                        Button("Cast-Steuerung öffnen") { cast.showControls() }
                        Button("Cast trennen") { cast.disconnect() }
                    }
                }
                Section {
                    Text("Der Cast-Empfänger muss den Link selbst ohne Browser-Cookies, Login, DRM oder spezielle Header laden können. blob:-URLs und verschlüsselte Medien werden abgelehnt. YouTube-MSE-Player werden nicht durch einen YouTube-Watch-Link ersetzt. Live-Streams, Receiver-Codec-Support und CORS können die Wiedergabe begrenzen.")
                    Text("SponsorBlock und Videozählung wirken im Webseitenplayer, nicht auf dem Cast-Empfänger. Ein Zeit-Timer kann die aktive Cast-Session pausieren, solange die App läuft.")
                }.font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Auf dem Fernseher")
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
                Text("WebKWeb speichert Verlauf und Favoriten lokal mit SwiftData. Bei aktivem Verlauf werden die letzten 500 nicht favorisierten Seiten behalten. Private Tabs werden nicht gespeichert; normale Tabs und Zeit-Timer können lokal wiederhergestellt werden. Favoriten werden zusätzlich im lokalen App-Group-Speicher für Widgets und Siri abgelegt. Es gibt keinen eigenen Analytics- oder Werbedienst. Optionaler iCloud-Sync benötigt einen provisionierten Build und explizite Aktivierung.")
                Text("Webseiten erhalten übliche Browseranfragen einschließlich IP-Adresse und können Cookies oder eigene Tracker verwenden. Eine Google-Suche übermittelt den eingegebenen Suchbegriff an Google. Website-Daten lassen sich in den Einstellungen löschen; Verlauf und Favoriten in der Bibliothek.")
                Text("Bei eingeschaltetem Netzwerkfilter wird höchstens einmal täglich sowie auf manuelle Anforderung die AdGuard DNS-Liste von adguardteam.github.io geladen. Der Server erhält eine normale Netzwerkanfrage. Die Liste wird lokal zu WebKit-Regeln kompiliert; dein Verlauf wird nicht an AdGuard gesendet.")
                Text("SponsorBlock ist zunächst ausgeschaltet. Nach Aktivierung werden YouTube-Video-IDs an sponsor.ajay.app übermittelt, ohne Browser-Cookies. Der Dienst sieht dabei deine IP-Adresse. Abschalten beendet weitere Abfragen; bereits gesendete Anfragen lassen sich nicht zurückholen.")
                Text("AirPlay verwendet iOS. Ein optionaler Build mit dem Google Cast SDK sucht nach Geräten im lokalen Netzwerk und übermittelt den gewählten direkten Medienlink und Titel an den Empfänger. Die jeweiligen Geräte und Drittanbieter haben eigene Datenschutzregeln.")
                Text("Diese Entwicklungsversion benötigt vor Veröffentlichung eine öffentlich erreichbare Datenschutzerklärung, eine Kontaktadresse des verantwortlichen Entwicklers und ausgefüllte App-Store-Datenschutzangaben.")
            }.padding(24).frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity)
        }.navigationTitle("Datenschutz").navigationBarTitleDisplayMode(.inline)
    }
}

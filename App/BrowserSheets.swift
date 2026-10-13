import SwiftUI
import SwiftData
import WebKit

enum LibrarySection: String, CaseIterable {
    case favorites = "Favoriten"
    case history = "Verlauf"
}

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

    private var filtered: [SavedPage] {
        pages.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.address.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if selectedSection == .favorites { Section("Favoriten") {
                    let favorites = filtered.filter(\.favorite)
                    if favorites.isEmpty { Text("Speichere eine Seite mit dem Stern.").foregroundStyle(.secondary) }
                    ForEach(favorites) { page in row(page) }
                } }
                if selectedSection == .history { Section("Verlauf") {
                    let history = filtered.filter { !$0.favorite }
                    if history.isEmpty { Text("Noch keine besuchten Seiten.").foregroundStyle(.secondary) }
                    ForEach(history) { page in row(page) }
                } }
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
                ToolbarItem(placement: .primaryAction) { Button("Verlauf löschen", systemImage: "trash") { clearHistory = true } }
            }
            .confirmationDialog("Verlauf löschen? Favoriten bleiben gespeichert.", isPresented: $clearHistory, titleVisibility: .visible) {
                Button("Verlauf löschen", role: .destructive) {
                    for page in pages where !page.favorite { context.delete(page) }
                    didChange()
                }
            }
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
        }
        .swipeActions(edge: .leading) {
            Button { page.favorite.toggle(); didChange() } label: {
                Label(page.favorite ? "Entfernen" : "Favorit", systemImage: page.favorite ? "star.slash" : "star")
            }.tint(.orange)
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
                    Button("Neuer Tab", systemImage: "plus") { browser.addTab(); dismiss() }
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
    @State private var minutes = 30
    @State private var videos = 1
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Pause nach", selection: $mode) {
                        Text("Dauer").tag(0)
                        Text("Videos").tag(1)
                    }.pickerStyle(.segmented)
                    if mode == 0 { Stepper("\(minutes) Minuten", value: $minutes, in: 5...240, step: 5) }
                    else { Stepper("\(videos) Video(s)", value: $videos, in: 1...20) }
                    Button("Timer starten") {
                        if mode == 0 { browser.sleep(minutes: minutes) } else { browser.sleep(videos: videos) }
                        dismiss()
                    }.buttonStyle(.borderedProminent)
                } footer: {
                    Text("Videozählung gilt für den beim Start gewählten Tab und HTML-Medien mit ended-Ereignis. Bei Live-Streams und Cast wird nicht gezählt. Eine pausierte oder von iOS angehaltene App kann den Timer erst beim Fortsetzen ausführen.")
                }
                if browser.sleepPlan.isActive {
                    Section { Button("Aktuellen Timer abbrechen", role: .destructive) { browser.cancelSleep(); dismiss() } }
                }
            }
            .navigationTitle("Sleep-Timer")
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
    @State private var clearing = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Netzwerkfilter", isOn: $browser.blockingEnabled)
                    Text(rules.status).font(.caption).foregroundStyle(.secondary)
                    if let date = rules.lastUpdate { LabeledContent("Letztes Update", value: date.formatted(date: .abbreviated, time: .shortened)) }
                    Button(rules.refreshing ? "Wird aktualisiert …" : "Filterliste aktualisieren") {
                        Task { await rules.refreshIfNeeded(force: true) }
                    }.disabled(rules.refreshing)
                } header: { Text("Filter") } footer: {
                    Text("AdGuard DNS-Liste: sichere Domainregeln und bestimmte YouTube-pagead-Endpunkte. Nicht alle Anzeigen lassen sich filtern. Falls eine Seite nicht funktioniert, deaktiviere den Filter und lade sie erneut.")
                }
                Section {
                    Toggle("SponsorBlock", isOn: $browser.sponsorBlockEnabled)
                } header: { Text("YouTube-Segmente") } footer: {
                    Text("Überspringt gemeldete Sponsor-, Intro-, Outro- und Eigenwerbungssegmente. Bei Aktivierung erhält sponsor.ajay.app die Video-ID und deine IP-Adresse. Einträge stammen aus der Community und können fehlen oder falsch sein.")
                }
                Section {
                    Toggle("Gestenfläche zum Spulen", isOn: $browser.gesturesEnabled)
                    Text("Doppelt links/rechts tippen: ±10 Sekunden. Horizontal wischen: weiter spulen. Die Lautstärke nutzt den nativen iOS-Regler.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Player") } footer: {
                    Text("Die App verwendet eine mobile Safari-Kennung. Inline-Wiedergabe, Autoplay, AirPlay und Bild-in-Bild benötigen Unterstützung durch Webseite und iOS. AVAudioSession ist für Wiedergabe eingerichtet; WebKit kann Audio im Hintergrund dennoch anhalten.")
                }
                Section {
                    Button(clearing ? "Wird gelöscht …" : "Cookies & Website-Daten löschen", role: .destructive) { clearWebsiteData = true }.disabled(clearing)
                    NavigationLink("Datenschutz") { PrivacyView() }
                    LabeledContent("iCloud-Sync", value: "Nicht aktiviert")
                } header: { Text("Daten") } footer: {
                    Text("Verlauf und Favoriten bleiben auf diesem Gerät. Widgets und Siri lesen nur deine lokal gespeicherten Favoriten.")
                }
                Section {
                    Text("WebKWeb 0.1 · iOS 17+").font(.footnote)
                    Text("Ein Browser mit nativen Videofunktionen. Keine Verbindung zu YouTube, AdGuard oder SponsorBlock; keine Zusage werbefreier Wiedergabe oder einer App-Store-Zulassung.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Einstellungen")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
            .confirmationDialog("Website-Daten löschen? Du wirst auf Webseiten abgemeldet.", isPresented: $clearWebsiteData, titleVisibility: .visible) {
                Button("Cookies & Website-Daten löschen", role: .destructive) {
                    clearing = true
                    browser.pauseAll()
                    for tab in browser.tabs { tab.webView.stopLoading() }
                    WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
                        Task { @MainActor in clearing = false }
                    }
                }
            }
        }
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
                        if cast.load(media, title: tab.title, at: tab.playbackTime) {
                            tab.run("globalThis.__webkweb?.pause()", allFrames: true)
                        }
                    }.disabled(tab.directMedia == nil)
                    #else
                    Text("Google Cast ist eine optionale Build-Erweiterung und in diesem Standardbuild nicht enthalten.")
                    #endif
                    if let media = tab.directMedia { Text(media.url.host ?? "Medienlink").font(.caption).foregroundStyle(.secondary) }
                    else { Text("Kein übertragbarer direkter HTTP(S)-Medienlink erkannt.").font(.caption).foregroundStyle(.secondary) }
                    if !cast.status.isEmpty { Text(cast.status).font(.caption) }
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
                Text("WebKWeb speichert Verlauf und Favoriten lokal mit SwiftData. Die letzten 500 nicht favorisierten Seiten werden behalten. Favoriten werden zusätzlich im lokalen App-Group-Speicher für Widgets und Siri abgelegt. Es gibt keinen eigenen Analytics- oder Werbedienst und keinen aktiven iCloud-Sync.")
                Text("Webseiten erhalten übliche Browseranfragen einschließlich IP-Adresse und können Cookies oder eigene Tracker verwenden. Eine Google-Suche übermittelt den eingegebenen Suchbegriff an Google. Website-Daten lassen sich in den Einstellungen löschen; Verlauf und Favoriten in der Bibliothek.")
                Text("Bei eingeschaltetem Netzwerkfilter wird höchstens einmal täglich sowie auf manuelle Anforderung die AdGuard DNS-Liste von adguardteam.github.io geladen. Der Server erhält eine normale Netzwerkanfrage. Die Liste wird lokal zu WebKit-Regeln kompiliert; dein Verlauf wird nicht an AdGuard gesendet.")
                Text("SponsorBlock ist zunächst ausgeschaltet. Nach Aktivierung werden YouTube-Video-IDs an sponsor.ajay.app übermittelt, ohne Browser-Cookies. Der Dienst sieht dabei deine IP-Adresse. Abschalten beendet weitere Abfragen; bereits gesendete Anfragen lassen sich nicht zurückholen.")
                Text("AirPlay verwendet iOS. Ein optionaler Build mit dem Google Cast SDK sucht nach Geräten im lokalen Netzwerk und übermittelt den gewählten direkten Medienlink und Titel an den Empfänger. Die jeweiligen Geräte und Drittanbieter haben eigene Datenschutzregeln.")
                Text("Diese Entwicklungsversion benötigt vor Veröffentlichung eine öffentlich erreichbare Datenschutzerklärung, eine Kontaktadresse des verantwortlichen Entwicklers und ausgefüllte App-Store-Datenschutzangaben.")
            }.padding(24).frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity)
        }.navigationTitle("Datenschutz").navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI
import SwiftData

@MainActor
struct QueueView: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedPage.favoriteOrder) private var pages: [SavedPage]
    @State private var address = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Shuffle", isOn: Binding(get: { browser.queue.shuffled }, set: { browser.queue.setShuffle($0) }))
                    Picker("Wiederholen", selection: $browser.queue.repeatMode) { ForEach(QueueRepeat.allCases) { Text($0.title).tag($0) } }
                    HStack {
                        Button { browser.previousQueue() } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Vorheriger Titel").disabled(!browser.queue.canPrevious || browser.queueTabID == nil)
                        Spacer()
                        Button { browser.nextQueue() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Nächster Titel").disabled(!browser.queue.canNext || browser.queueTabID == nil)
                    }
                }
                Section("Queue") {
                    if browser.queue.entries.isEmpty { Text("Noch keine Titel").foregroundStyle(.secondary) }
                    ForEach(browser.queue.entries) { entry in
                        Button { browser.startQueue(entry.id); dismiss() } label: {
                            HStack {
                                Image(systemName: entry.id == browser.queue.currentID ? "play.fill" : "music.note.list")
                                VStack(alignment: .leading) { Text(entry.title).lineLimit(2); Text(entry.address).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                        }
                        .swipeActions { Button("Entfernen", role: .destructive) { browser.removeQueueEntry(entry.id) } }
                    }.onMove { browser.queue.move(from: $0, to: $1) }
                }
                Section("Hinzufügen") {
                    Button("Aktuelle Seite") { browser.enqueueCurrent() }.disabled(browser.current.isPrivate || browser.current.address.isEmpty)
                    HStack {
                        TextField("HTTP(S)-Adresse", text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button { browser.enqueue(address: address, title: URL(string: address)?.host ?? address); address = "" } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                            .accessibilityLabel("Adresse zur Queue hinzufügen").disabled(AddressResolver.directURL(address) == nil)
                    }
                    ForEach(pages.filter(\.favorite)) { page in Button(page.title) { browser.enqueue(address: page.address, title: page.title) } }
                    Button("Alle Favoriten") {
                        for page in pages where page.favorite { browser.enqueue(address: page.address, title: page.title) }
                    }.disabled(!pages.contains(where: \.favorite))
                }
                Section {
                    Text("Die lokale Queue umfasst ihre gesamten Einträge. Webseiten müssen einen HTML-Player mit Endereignissen bereitstellen. Private Tabs werden nicht übernommen. YouTube-Playlists werden nicht ausgelesen.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Queue")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }; ToolbarItem(placement: .primaryAction) { EditButton() } }
        }
    }
}

@MainActor
struct PlayerOptionsView: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var tab: BrowserTab
    var body: some View {
        NavigationStack {
            Form {
                Section("Player") {
                    HStack {
                        Button("Vollbild", systemImage: "arrow.up.left.and.arrow.down.right") { tab.runMedia("globalThis.__webkweb?.fullscreen()"); dismiss() }
                        Spacer()
                        Button("PiP", systemImage: "pip") { tab.runMedia("globalThis.__webkweb?.pip()"); dismiss() }
                    }.disabled(tab.activeMediaKind != "video")
                    Picker("Geschwindigkeit", selection: Binding(get: { tab.playbackRate }, set: { tab.runMedia("globalThis.__webkweb?.setRate(\($0))") })) {
                        ForEach(Array(Set([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, tab.playbackRate])).sorted(), id: \.self) { Text("\($0.formatted())×").tag($0) }
                    }.disabled(!tab.hasMedia)
                    if !tab.resolution.isEmpty { LabeledContent("Quelldimension", value: tab.resolution) }
                    if tab.muted { Text("Der Webseitenplayer ist stummgeschaltet.").font(.caption).foregroundStyle(.secondary) }
                    if tab.waiting { Label("Player lädt …", systemImage: "hourglass") }
                    if !tab.mediaError.isEmpty { Text(tab.mediaError).foregroundStyle(.red) }
                    Button("Wiedergabe erneut versuchen") { tab.runMedia("globalThis.__webkweb?.recover()") }.disabled(!tab.hasMedia)
                    NativeVolumeControl().frame(minHeight: 44).accessibilityLabel("Systemlautstärke")
                    if browser.gesturesEnabled { SeekGesturePad(seek: browser.seek) }
                }
                Section("Untertitel") {
                    Picker("Spur", selection: Binding(get: { tab.captions.first(where: \.selected)?.id ?? -1 }, set: { tab.runMedia("globalThis.__webkweb?.setCaption(\($0))") })) {
                        Text("Aus").tag(-1)
                        ForEach(tab.captions) { Text($0.title).tag($0.id) }
                    }.disabled(tab.captions.isEmpty)
                    if tab.captions.isEmpty { Text("Der Player stellt keine HTML-Untertitelspuren bereit. Nutze seine eigenen Untertitel.").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Audio") {
                    Picker("Spur", selection: Binding(get: { tab.audioTracks.first(where: \.selected)?.id ?? -1 }, set: { tab.runMedia("globalThis.__webkweb?.setAudio(\($0))") })) {
                        if tab.audioTracks.isEmpty { Text("Webseitenplayer").tag(-1) }
                        ForEach(tab.audioTracks) { Text($0.title).tag($0.id) }
                    }.disabled(tab.audioTracks.isEmpty)
                    Toggle("Original bevorzugen", isOn: $browser.options.preferOriginalAudio)
                    Text("Nur verfügbar, wenn der Webseitenplayer eine Originalspur anbietet.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Text("Qualität wird vom Webseitenplayer gewählt. AirPlay behält die aktuelle Quelle; 1080p lässt sich ohne passende Quelle nicht erzwingen. HTML-Untertitel können im nativen Vollbild erscheinen, Webseiten-Overlays möglicherweise nicht.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Player")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}

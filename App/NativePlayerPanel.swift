import SwiftUI

@MainActor
struct NativePlayerPanel: View {
    @EnvironmentObject private var browser: BrowserModel
    @ObservedObject var playback: NativePlayer
    @State private var options = false
    @State private var queue = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSize
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(playback.title).font(.headline).lineLimit(1)
                Spacer()
                Button { playback.expanded.toggle() } label: { Image(systemName: playback.expanded ? "chevron.down" : "chevron.up") }.accessibilityLabel("Playergröße ändern").accessibilityIdentifier("native.expand")
                    #if DEBUG
                    .accessibilityValue(ProcessInfo.processInfo.arguments.contains("--ui-test-native") ? "time=\(playback.time);playing=\(playback.playing);waiting=\(playback.waiting);error=\(playback.error ?? "none");media=\(playback.mediaID?.uuidString ?? "none")" : "")
                    #endif
                Button { playback.close() } label: { Image(systemName: "xmark") }.accessibilityLabel("Player schließen").frame(minWidth: 44, minHeight: 44)
            }.padding(.horizontal)
            HStack(spacing: 0) {
                NativePlayerSurface(playback: playback)
                    .frame(height: playback.focus ? nil : playback.expanded ? (verticalSize == .compact ? 90 : sizeClass == .regular ? 300 : 210) : 80)
                    .frame(maxHeight: playback.focus ? .infinity : nil)
                    .accessibilityIdentifier("native.player")
                if sizeClass == .regular && playback.expanded && !playback.focus {
                    List(playback.queueIDs, id: \.self) { id in
                        if let item = browser.library.document.media.first(where: { $0.id == id }) {
                            Button(item.title) { playback.open(id) }.accessibilityLabel("Queue: " + item.title)
                        }
                    }.frame(width: 240, height: 300).accessibilityLabel("Queue neben dem Player")
                }
            }
            if let error = playback.error {
                HStack { Text(error).font(.caption); Button("Erneut versuchen") { playback.retry() } }.padding(.horizontal)
            }
            if playback.waiting { ProgressView("Medium lädt …") }
            if playback.focus && (browser.sleepPlan.isActive || browser.sleepAfterNativeQueue) {
                HStack { Label("Sleep-Timer", systemImage: "moon.zzz"); if let deadline = browser.sleepPlan.deadline { Text(deadline, style: .timer) }; Button("Abbrechen") { browser.cancelSleep() } }.font(.caption)
            }
            HStack {
                Button { playback.skip(-Double(browser.options.skipSeconds)) } label: { Image(systemName: "gobackward") }.disabled(playback.live).accessibilityLabel("Zurückspulen")
                Button { playback.toggle() } label: { Image(systemName: playback.playing ? "pause.fill" : "play.fill") }.disabled(playback.error != nil).accessibilityLabel(playback.playing ? "Pause" : "Abspielen")
                Button { playback.skip(Double(browser.options.skipSeconds)) } label: { Image(systemName: "goforward") }.disabled(playback.live).accessibilityLabel("Vorspulen")
                Spacer()
                Button { queue = true } label: { Image(systemName: "music.note.list") }.accessibilityLabel("Queue").accessibilityIdentifier("native.queue")
                Button { options = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Native Playeroptionen")
                Button { playback.focus.toggle() } label: { Image(systemName: playback.focus ? "rectangle.expand.vertical" : "viewfinder") }.accessibilityLabel(playback.focus ? "Fokusmodus beenden" : "Fokusmodus")
            }.buttonStyle(.bordered).padding(.horizontal)
            if !playback.focus, let duration = playback.duration {
                Slider(value: Binding(get: { min(duration, playback.time) }, set: { playback.seek(to: $0) }), in: 0...max(0.1, duration)).padding(.horizontal).accessibilityLabel("Wiedergabeposition")
            }
        }.padding(.vertical, 8).background(.regularMaterial)
            .sheet(isPresented: $options) { NativePlaybackOptions(playback: playback) }
            .sheet(isPresented: $queue) { NativeQueueView(playback: playback, library: browser.library) }
    }
}

@MainActor
struct NativePlaybackOptions: View {
    @ObservedObject var playback: NativePlayer
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Picker("Geschwindigkeit", selection: $playback.rate) { ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 2], id: \.self) { Text("\($0.formatted())×").tag($0) } }.disabled(playback.live)
                Toggle("Medium wiederholen", isOn: $playback.repeatOne).disabled(playback.live)
                Section("A–B-Schleife") {
                    Button("A bei \(Int(playback.time)) s setzen") { playback.setLoopStart() }.disabled(playback.live)
                    Button("B bei \(Int(playback.time)) s setzen") { playback.setLoopEnd() }.disabled(playback.live || playback.loopA == nil || playback.time <= (playback.loopA ?? 0) + 0.5)
                    if let a = playback.loopA { Text("A: \(Int(a)) s" + (playback.loopB.map { " · B: \(Int($0)) s" } ?? "")) }
                    Button("Schleife löschen") { playback.clearLoop() }.disabled(playback.loopA == nil)
                }
                Section("Untertitel") {
                    Picker("Spur", selection: Binding(get: { playback.captionID }, set: playback.selectCaption)) {
                        Text("Aus").tag(-1)
                        ForEach(playback.captions) { Text($0.title).tag($0.id) }
                    }.disabled(playback.captions.isEmpty)
                    if playback.captions.isEmpty { Text("Keine System-Untertitelspur vorhanden.") }
                }
                Section("Audio") {
                    Picker("Audiospur", selection: Binding(get: { playback.audioID }, set: playback.selectAudio)) {
                        if playback.audioID == -1 { Text("Standard").tag(-1) }
                        ForEach(playback.audioOptions) { Text($0.title).tag($0.id) }
                    }.disabled(playback.audioOptions.count < 2)
                    HStack { Text("AirPlay"); Spacer(); AirPlayControl().frame(width: 44, height: 44) }
                    Text("Der Empfänger spielt die Originalquelle. Es gibt keine Filterung auf dem Empfänger.").font(.caption)
                }
                Section("Kapitel") {
                    ForEach(playback.chapters) { chapter in Button(chapter.title) { playback.seek(to: chapter.seconds); dismiss() } }
                    if playback.chapters.isEmpty { Text("Keine Kapitelmetadaten vorhanden.") }
                }
                Text("PiP und Vollbild über die Systembedienelemente im Video. Hintergrund-Audio benötigt laufende, berechtigt nutzbare Medien. Keine stille Keep-alive-Wiedergabe.").font(.caption)
            }.navigationTitle("Player").toolbar { Button("Fertig") { dismiss() } }
        }
    }
}

@MainActor
struct NativeQueueView: View {
    @ObservedObject var playback: NativePlayer
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button("Zurück") { playback.previous() }.disabled(!playback.canPrevious)
                        Spacer(); Button("Weiter") { playback.next() }.accessibilityIdentifier("native.queue.next").disabled(!playback.canNext)
                    }
                }
                ForEach(playback.queueIDs, id: \.self) { id in
                    if let item = library.document.media.first(where: { $0.id == id }) {
                        Button { playback.open(id); dismiss() } label: {
                            VStack(alignment: .leading) {
                                Label(item.title, systemImage: playback.mediaID == id ? "play.fill" : "film")
                                if let reason = playback.unavailable[id] { Text(reason).font(.caption).foregroundStyle(.red) }
                            }
                        }.swipeActions { Button("Entfernen", role: .destructive) { playback.removeFromQueue(id) } }
                    }
                }.onMove { playback.moveQueue(from: $0, to: $1) }
                Section("Native Medien hinzufügen") {
                    ForEach(library.document.media.filter { $0.kind != .website }) { item in Button(item.title) { playback.enqueue(item.id) } }
                }
                Text("Duplikate werden vermieden. Ein Quellenfehler stoppt den Übergang; erneutes Abspielen erfolgt bewusst. Playlists bleiben davon getrennt.").font(.caption)
            }.navigationTitle("Medienqueue").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }; ToolbarItem(placement: .primaryAction) { EditButton() } }
        }
    }
}

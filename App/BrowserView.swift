import SwiftUI
import SwiftData
import WidgetKit
import WebKit

private enum BrowserSheet: String, Identifiable {
    case library, tabs, sleep, settings, cast
    var id: String { rawValue }
}

@MainActor
struct BrowserView: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \SavedPage.visitedAt, order: .reverse) private var pages: [SavedPage]
    @ObservedObject private var router = IntentRouter.shared
    @State private var sheet: BrowserSheet?
    @State private var persistenceError: String?

    var body: some View {
        NavigationStack {
            BrowserScreen(tab: browser.current, showLibrary: { sheet = .library },
                showTabs: { sheet = .tabs }, showSleep: { sheet = .sleep },
                showSettings: { sheet = .settings }, showCast: { sheet = .cast },
                favorite: { favoriteCurrent() }, isFavorite: pages.contains { $0.favorite && $0.address == browser.current.address })
                .id(browser.current.id)
                .toolbar(.hidden, for: .navigationBar)
                .sheet(item: $sheet) { selected in
                    switch selected {
                    case .library: LibraryView(open: { address in browser.open(address); sheet = nil }, didChange: saveAndSync)
                    case .tabs: TabsView()
                    case .sleep: SleepTimerView()
                    case .settings: SettingsView()
                    case .cast: CastView(tab: browser.current)
                    }
                }
        }
        .task {
            browser.onVisit = recordVisit
            syncFavorites()
            if browser.blockingEnabled { await RuleStore.shared.refreshIfNeeded() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { browser.enforceSleepDeadline() }
        }
        .onReceive(router.$command) { command in
            guard let command else { return }
            router.command = nil
            switch command {
            case .open(let address): browser.open(address)
            case .sleep(let minutes): browser.sleep(minutes: minutes)
            case .pause: browser.pauseAll()
            }
        }
        .alert("WebKWeb", isPresented: Binding(get: { browser.notice != nil || persistenceError != nil },
            set: { if !$0 { browser.notice = nil; persistenceError = nil } })) {
            Button("OK") { browser.notice = nil; persistenceError = nil }
        } message: { Text(persistenceError ?? browser.notice ?? "") }
        .alert("Webseite", isPresented: Binding(get: { browser.confirm != nil }, set: { value in
            if !value, let confirm = browser.confirm { browser.confirm = nil; confirm.completion(false) }
        })) {
            Button("Abbrechen", role: .cancel) { completeConfirmation(false) }
            Button("OK") { completeConfirmation(true) }
        } message: { Text(browser.confirm?.message ?? "") }
    }

    private func completeConfirmation(_ accepted: Bool) {
        let confirmation = browser.confirm
        browser.confirm = nil
        confirmation?.completion(accepted)
    }

    private func recordVisit(_ title: String, _ address: String) {
        do {
            var request = FetchDescriptor<SavedPage>(predicate: #Predicate { $0.address == address })
            request.fetchLimit = 1
            if let existing = try context.fetch(request).first {
                existing.title = title
                existing.visitedAt = .now
            } else {
                context.insert(SavedPage(title: title, address: address))
            }
            // Bound local history while preserving every favorite.
            let history = try context.fetch(FetchDescriptor<SavedPage>(predicate: #Predicate { !$0.favorite },
                sortBy: [SortDescriptor(\SavedPage.visitedAt, order: .reverse)]))
            for old in history.dropFirst(500) { context.delete(old) }
            try context.save()
        } catch { persistenceError = "Verlauf konnte nicht gespeichert werden: \(error.localizedDescription)" }
    }

    private func favoriteCurrent() {
        let tab = browser.current
        guard !tab.address.isEmpty else { return }
        do {
            let address = tab.address
            var request = FetchDescriptor<SavedPage>(predicate: #Predicate { $0.address == address })
            request.fetchLimit = 1
            if let existing = try context.fetch(request).first { existing.favorite.toggle() }
            else { context.insert(SavedPage(title: tab.title, address: address, favorite: true)) }
            saveAndSync()
        } catch { persistenceError = error.localizedDescription }
    }

    private func saveAndSync() {
        do { try context.save(); syncFavorites() }
        catch { persistenceError = "Änderung konnte nicht gespeichert werden: \(error.localizedDescription)" }
    }

    private func syncFavorites() {
        let request = FetchDescriptor<SavedPage>(predicate: #Predicate { $0.favorite },
            sortBy: [SortDescriptor(\SavedPage.visitedAt, order: .reverse)])
        guard let favorites = try? context.fetch(request) else { return }
        FavoriteStorage.write(favorites.map { FavoriteSnapshot(id: $0.address, title: $0.title, address: $0.address) })
        WidgetCenter.shared.reloadTimelines(ofKind: "WebKWebFavorites")
    }
}

@MainActor
private struct BrowserScreen: View {
    @EnvironmentObject private var browser: BrowserModel
    @ObservedObject var tab: BrowserTab
    let showLibrary: () -> Void
    let showTabs: () -> Void
    let showSleep: () -> Void
    let showSettings: () -> Void
    let showCast: () -> Void
    let favorite: () -> Void
    let isFavorite: Bool
    @State private var draft = ""
    @FocusState private var editing: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            if sizeClass == .regular {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(browser.tabs) { item in
                            TabPill(tab: item, selected: item.id == browser.selectedID,
                                select: { browser.selectedID = item.id }, close: { browser.close(item.id) })
                        }
                        Button { browser.addTab() } label: { Image(systemName: "plus") }.padding(10)
                    }.padding(.horizontal)
                }.padding(.bottom, 6)
            }
            ProgressView(value: tab.progress).progressViewStyle(.linear)
                .frame(height: 2).opacity(tab.loading ? 1 : 0)
            ZStack {
                BrowserWebView(tab: tab)
                if tab.address.isEmpty && !tab.loading { home }
                if let error = tab.error {
                    ContentUnavailableView {
                        Label("Seite nicht geladen", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Erneut laden") { tab.webView.reload() }.buttonStyle(.borderedProminent)
                    }.background(.background)
                }
            }
            if tab.hasMedia { mediaControls }
            if browser.sleepPlan.isActive { timerStatus }
            bottomBar
        }
        .onAppear { draft = tab.address }
        .onChange(of: tab.address) { _, value in if !editing { draft = value } }
    }

    private var addressBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe").foregroundStyle(.teal).accessibilityHidden(true)
            TextField("Adresse oder Google-Suche", text: $draft)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.webSearch)
                .submitLabel(.go).focused($editing)
                .onSubmit { browser.open(draft); editing = false }
                .accessibilityLabel("Adresse oder Google-Suche")
            if editing && !draft.isEmpty {
                Button { draft = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Eingabe löschen")
            } else if !tab.address.isEmpty {
                Button { tab.loading ? tab.webView.stopLoading() : tab.webView.reload() } label: {
                    Image(systemName: tab.loading ? "xmark" : "arrow.clockwise")
                }.accessibilityLabel(tab.loading ? "Laden stoppen" : "Neu laden")
            }
        }
        .padding(12).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "play.rectangle.on.rectangle.fill").font(.system(size: 52))
                    .foregroundStyle(.teal).padding(.top, 30)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dein Web. Dein Player.").font(.largeTitle.bold())
                    Text("Webseiten ansehen, Videos steuern und Favoriten behalten.").foregroundStyle(.secondary)
                }
                HStack {
                    quickLink("YouTube", icon: "play.rectangle", address: "https://m.youtube.com")
                    quickLink("Google", icon: "magnifyingglass", address: "https://www.google.com")
                }
                Button(action: showLibrary) { Label("Favoriten & Verlauf", systemImage: "star") }
                    .buttonStyle(.bordered).controlSize(.large)
                VStack(alignment: .leading, spacing: 10) {
                    Label("Inline-Video, Bild-in-Bild und AirPlay", systemImage: "pip")
                    Label("Netzwerkfilter mit täglichen Listen-Updates", systemImage: "shield")
                    Label("SponsorBlock nach Aktivierung in Einstellungen", systemImage: "forward.end")
                }.font(.subheadline).foregroundStyle(.secondary)
                Text("Autoplay, Bild-in-Bild und Hintergrundwiedergabe hängen von der Webseite und iOS ab.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.frame(maxWidth: 640, alignment: .leading).padding(24).frame(maxWidth: .infinity)
        }.background(.background)
    }

    private func quickLink(_ title: String, icon: String, address: String) -> some View {
        Button { browser.open(address) } label: {
            Label(title, systemImage: icon).frame(maxWidth: .infinity).padding(16)
        }.background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var mediaControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 18) {
                Button { browser.seek(-10) } label: { Image(systemName: "gobackward.10") }.accessibilityLabel("10 Sekunden zurück")
                Button { browser.togglePlayback() } label: { Image(systemName: tab.playing ? "pause.fill" : "play.fill") }
                    .accessibilityLabel(tab.playing ? "Pausieren" : "Abspielen")
                Button { browser.seek(10) } label: { Image(systemName: "goforward.10") }.accessibilityLabel("10 Sekunden vor")
                Spacer(minLength: 0)
                Text(time(tab.playbackTime)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button { tab.runMedia("globalThis.__webkweb?.pip()") } label: { Image(systemName: "pip") }
                    .accessibilityLabel("Bild-in-Bild")
                AirPlayControl().frame(width: 30, height: 30).accessibilityLabel("AirPlay-Auswahl")
                Button(action: showCast) { Image(systemName: "tv") }.accessibilityLabel("Cast-Optionen")
            }.font(.title3)
            NativeVolumeControl().frame(height: 28).accessibilityLabel("Systemlautstärke")
            if !tab.sponsorStatus.isEmpty { Text(tab.sponsorStatus).font(.caption).foregroundStyle(.secondary) }
            if browser.gesturesEnabled { SeekGesturePad(seek: browser.seek) }
        }.padding(.horizontal, 18).padding(.vertical, 10).background(.bar)
    }

    private var timerStatus: some View {
        HStack {
            Image(systemName: "moon.zzz")
            if let deadline = browser.sleepPlan.deadline {
                Text("Pause in"); Text(deadline, style: .timer).monospacedDigit()
            } else if let remaining = browser.sleepPlan.remainingVideos {
                Text("Pause nach \(remaining) Video(s) im gewählten Tab")
            }
            Spacer()
            Button("Abbrechen") { browser.cancelSleep() }
        }.font(.caption).padding(10).background(.teal.opacity(0.1))
    }

    private var bottomBar: some View {
        HStack {
            Button { tab.webView.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!tab.canGoBack).accessibilityLabel("Zurück")
            Spacer()
            Button { tab.webView.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!tab.canGoForward).accessibilityLabel("Vorwärts")
            Spacer()
            Button(action: favorite) { Image(systemName: isFavorite ? "star.fill" : "star") }
                .disabled(tab.address.isEmpty).accessibilityLabel(isFavorite ? "Favorit entfernen" : "Als Favorit speichern")
            Spacer()
            Button(action: showTabs) { Image(systemName: "square.on.square").overlay(alignment: .bottomTrailing) {
                Text("\(browser.tabs.count)").font(.system(size: 9, weight: .bold)).offset(x: 5, y: 4)
            } }.accessibilityLabel("\(browser.tabs.count) Tabs")
            Spacer()
            Menu {
                Button("Neuer Tab", systemImage: "plus") { browser.addTab() }
                Button("Favoriten & Verlauf", systemImage: "books.vertical", action: showLibrary)
                Button("Sleep-Timer", systemImage: "moon.zzz", action: showSleep)
                Button("Einstellungen", systemImage: "gear", action: showSettings)
                if let url = URL(string: tab.address) { ShareLink(item: url) }
                Button("Alles pausieren", systemImage: "pause.circle") { browser.pauseAll() }
            } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Menü")
        }.font(.title3).padding(.horizontal, 24).frame(height: 50).background(.bar)
    }

    private func time(_ value: Double) -> String {
        let seconds = max(0, Int(value))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

@MainActor
private struct TabPill: View {
    @ObservedObject var tab: BrowserTab
    let selected: Bool
    let select: () -> Void
    let close: () -> Void
    var body: some View {
        HStack {
            Button(action: select) { Text(tab.title).lineLimit(1).frame(maxWidth: 180) }
            Button(action: close) { Image(systemName: "xmark").font(.caption) }.accessibilityLabel("Tab schließen")
        }.padding(10).background(selected ? Color.teal.opacity(0.15) : Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 10))
    }
}

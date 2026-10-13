import SwiftUI
import SwiftData
import WidgetKit
import WebKit

private enum BrowserSheet: String, Identifiable {
    case library, history, tabs, sleep, settings, cast
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
                showHistory: { sheet = .history },
                showTabs: { sheet = .tabs }, showSleep: { sheet = .sleep },
                showSettings: { sheet = .settings }, showCast: { sheet = .cast },
                favorite: { favoriteCurrent() }, isFavorite: pages.contains { $0.favorite && $0.address == browser.current.address })
                .id(browser.current.id)
                .toolbar(.hidden, for: .navigationBar)
                .sheet(item: $sheet) { selected in
                    switch selected {
                    case .library: LibraryView(open: { address in browser.open(address); sheet = nil }, didChange: saveAndSync)
                    case .history: LibraryView(open: { address in browser.open(address); sheet = nil }, didChange: saveAndSync, initialSection: .history)
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
    let showHistory: () -> Void
    let showTabs: () -> Void
    let showSleep: () -> Void
    let showSettings: () -> Void
    let showCast: () -> Void
    let favorite: () -> Void
    let isFavorite: Bool
    @State private var draft = ""
    @FocusState private var editing: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 60
    private var isHome: Bool { tab.address.isEmpty && !tab.loading }
    private var shortcutSize: CGFloat { min(iconSize, dynamicType.isAccessibilitySize ? 84 : 64) }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicType.isAccessibilitySize ? 2 : 4) }

    var body: some View {
        VStack(spacing: 0) {
            if !isHome {
                addressBar.padding(.horizontal, 12).padding(.vertical, 8)
                if sizeClass == .regular { tabStrip }
                ProgressView(value: tab.progress).progressViewStyle(.linear)
                    .frame(height: 2).opacity(tab.loading ? 1 : 0)
            }
            ZStack {
                if isHome { home }
                else { BrowserWebView(tab: tab) }
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
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(.white)
        .onAppear { draft = tab.address }
        .onChange(of: tab.address) { _, value in if !editing { draft = value } }
    }

    private var addressBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.65)).accessibilityHidden(true)
            TextField("Suchen oder Adresse", text: $draft)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.webSearch)
                .submitLabel(.go).focused($editing)
                .onSubmit { openDraft() }
                .accessibilityLabel("Suchen oder Adresse")
            if editing && !draft.isEmpty {
                Button { draft = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("Eingabe löschen").frame(minWidth: 28, minHeight: 28)
            } else if !isHome {
                Button { tab.loading ? tab.webView.stopLoading() : tab.webView.reload() } label: {
                    Image(systemName: tab.loading ? "xmark" : "arrow.clockwise")
                }.accessibilityLabel(tab.loading ? "Laden stoppen" : "Neu laden").frame(minWidth: 28, minHeight: 28)
            } else if !draft.isEmpty {
                Button(action: openDraft) { Image(systemName: "arrow.up.right") }
                    .accessibilityLabel("Öffnen").frame(minWidth: 28, minHeight: 28)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(minHeight: 54).browserGlass()
    }

    private func openDraft() { browser.open(draft); editing = false }

    private var home: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 28) {
                    addressBar
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(HomeSite.allCases) { site in
                            shortcut(site.title, action: { browser.open(site.address) }) { HomeSiteGlyph(site: site) }
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 24) {
                        shortcut("Favoriten", symbol: "star", action: showLibrary)
                        shortcut("Verlauf", symbol: "clock.arrow.circlepath", action: showHistory)
                        shortcut("Timer", symbol: "moon.zzz", action: showSleep)
                        shortcut("Einstellungen", symbol: "slider.horizontal.3", action: showSettings)
                    }
                }
                .frame(maxWidth: 500)
                .padding(.horizontal, 24)
                .padding(.top, max(72, geometry.size.height * 0.28))
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
            }.scrollDismissesKeyboard(.interactively)
        }
    }

    private func shortcut<Icon: View>(_ title: String, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                icon().frame(width: shortcutSize, height: shortcutSize)
                    .browserGlass(radius: shortcutSize / 2)
                Text(title).font(.caption2).foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore).accessibilityLabel(title)
    }

    private func shortcut(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        shortcut(title, action: action) {
            Image(systemName: symbol).font(.system(size: 23, weight: .medium)).foregroundStyle(.white.opacity(0.88))
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(browser.tabs) { item in
                    TabPill(tab: item, selected: item.id == browser.selectedID,
                        select: { browser.selectedID = item.id }, close: { browser.close(item.id) })
                }
                Button { browser.addTab() } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
            }.padding(.horizontal, 12)
        }.padding(.bottom, 8)
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
                Button { tab.runMedia("globalThis.__webkweb?.pip()") } label: { Image(systemName: "pip") }.accessibilityLabel("Bild-in-Bild")
                AirPlayControl().frame(width: 30, height: 30).accessibilityLabel("AirPlay-Auswahl")
                Button(action: showCast) { Image(systemName: "tv") }.accessibilityLabel("Cast-Optionen")
            }.font(.title3)
            NativeVolumeControl().frame(height: 28).accessibilityLabel("Systemlautstärke")
            if !tab.sponsorStatus.isEmpty { Text(tab.sponsorStatus).font(.caption).foregroundStyle(.secondary) }
            if browser.gesturesEnabled { SeekGesturePad(seek: browser.seek) }
        }.padding(.horizontal, 18).padding(.vertical, 10)
            .browserGlass(radius: 22).padding(.horizontal, 8)
    }

    private var timerStatus: some View {
        HStack {
            Image(systemName: "moon.zzz")
            if let deadline = browser.sleepPlan.deadline { Text(deadline, style: .timer).monospacedDigit() }
            else if let remaining = browser.sleepPlan.remainingVideos { Text("\(remaining) Video(s)") }
            Spacer()
            Button { browser.cancelSleep() } label: { Image(systemName: "xmark") }.accessibilityLabel("Timer abbrechen")
        }.font(.caption).padding(12).browserGlass(radius: 18).padding(.horizontal, 12).padding(.top, 8)
            .accessibilityLabel("Sleep-Timer")
    }

    private var bottomBar: some View {
        HStack(spacing: isHome ? 12 : 8) {
            if !isHome {
                HStack(spacing: 2) {
                    Button { tab.webView.goBack() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 48) }
                        .disabled(!tab.canGoBack).accessibilityLabel("Zurück")
                    Button { tab.webView.goForward() } label: { Image(systemName: "chevron.right").frame(width: 44, height: 48) }
                        .disabled(!tab.canGoForward).accessibilityLabel("Vorwärts")
                }.browserGlass(radius: 24)
                Button(action: favorite) { Image(systemName: isFavorite ? "star.fill" : "star").frame(width: 44, height: 48) }
                    .browserGlass(radius: 24).accessibilityLabel(isFavorite ? "Favorit entfernen" : "Als Favorit speichern")
                Spacer(minLength: 0)
            } else {
                Button { browser.blockingEnabled.toggle() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: browser.blockingEnabled ? "shield.lefthalf.filled" : "shield")
                        Circle().fill(browser.blockingEnabled ? Color.green.opacity(0.8) : Color.white.opacity(0.3)).frame(width: 5, height: 5)
                    }.frame(width: 72, height: 48)
                }.browserGlass(radius: 24).accessibilityLabel("Netzwerkfilter")
                    .accessibilityValue(browser.blockingEnabled ? "Aktiv" : "Aus")
                    .accessibilityHint("Doppeltippen schaltet den Filter um")
            }
            Button(action: showTabs) {
                HStack(spacing: 7) {
                    Image(systemName: "square.on.square")
                    Text("\(browser.tabs.count)").font(.caption.monospacedDigit())
                }.frame(width: isHome ? 72 : 64, height: 48)
            }.browserGlass(radius: 24).accessibilityLabel("\(browser.tabs.count) Tabs")
            browserMenu
        }
        .font(.system(size: 19, weight: .medium)).buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
        .frame(maxWidth: isHome ? 320 : 700)
        .frame(maxWidth: .infinity)
    }

    private var browserMenu: some View {
        Menu {
            Button("Neuer Tab", systemImage: "plus") { browser.addTab() }
            Button("Favoriten", systemImage: "star", action: showLibrary)
            Button("Verlauf", systemImage: "clock.arrow.circlepath", action: showHistory)
            Button("Sleep-Timer", systemImage: "moon.zzz", action: showSleep)
            Button("Einstellungen", systemImage: "gear", action: showSettings)
            Toggle("Netzwerkfilter", isOn: $browser.blockingEnabled)
            if let url = URL(string: tab.address) { ShareLink(item: url) }
            Button("Alles pausieren", systemImage: "pause.circle") { browser.pauseAll() }
        } label: { Image(systemName: "ellipsis").frame(width: 48, height: 48).browserGlass(radius: 24) }
        .accessibilityLabel("Menü")
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
            Button(action: close) { Image(systemName: "xmark").font(.caption).frame(minWidth: 28, minHeight: 28) }
                .accessibilityLabel("Tab schließen")
        }.padding(10).browserGlass(radius: 18)
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(selected ? 0.25 : 0), lineWidth: 1) }
    }
}

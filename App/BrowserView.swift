import SwiftUI
import SwiftData
import WidgetKit
import WebKit

private enum BrowserSheet: String, Identifiable {
    case library, history, tabs, sleep, settings, cast, queue, player, downloads, address
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
    @State private var promptText = ""

    private var favoriteDigest: [String] {
        pages.filter(\.favorite).map { "\($0.identifier)|\($0.title)|\($0.address)|\($0.favoriteOrder)" }.sorted()
    }

    var body: some View {
        NavigationStack {
            BrowserScreen(tab: browser.current, showLibrary: { sheet = .library },
                showHistory: { sheet = .history },
                showTabs: { sheet = .tabs }, showSleep: { sheet = .sleep },
                showSettings: { sheet = .settings }, showCast: { sheet = .cast },
                showQueue: { sheet = .queue }, showPlayer: { sheet = .player }, showDownloads: { sheet = .downloads },
                showAddress: { sheet = .address },
                favorite: { favoriteCurrent() }, isFavorite: pages.contains { $0.favorite && $0.address == StoredAddress.clean(browser.current.address) })
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
                    case .queue: QueueView()
                    case .player: PlayerOptionsView(tab: browser.current)
                    case .downloads:
                        #if WEBKWEB_NO_DOWNLOADS
                        EmptyView()
                        #else
                        DownloadsView()
                        #endif
                    case .address: AddressEntryView().presentationDetents([.medium, .large])
                    }
                }
        }
        .task {
            browser.onVisit = recordVisit
            normalizeSavedPages()
            syncFavorites()
            if browser.blockingEnabled { await RuleStore.shared.refreshIfNeeded() }
        }
        .onChange(of: favoriteDigest) { _, _ in syncFavorites() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await browser.foreground() } }
            else { if phase == .inactive { browser.playbackTab.attemptAutoPiP() }; browser.persistSession() }
        }
        .onReceive(router.$revision) { _ in
            for command in router.drain() {
                switch command {
                case .open(let address): browser.open(address)
                case .sleep(let minutes): browser.sleep(minutes: minutes)
                case .pause: browser.pauseAll(blockAutoplay: true)
                }
            }
        }
        .onChange(of: browser.dialog?.id) { _, _ in promptText = browser.dialog?.defaultText ?? "" }
        .alert(browser.dialog == nil ? "DevnTube" : "Webseite", isPresented: Binding(
            get: { browser.dialog != nil || browser.notice != nil || persistenceError != nil },
            set: { shown in
                if !shown {
                    let id = browser.dialog?.id
                    DispatchQueue.main.async {
                        if let id, browser.dialog?.id == id { browser.completeDialog(nil) }
                        else if id == nil { browser.notice = nil; persistenceError = nil }
                    }
                }
            })) {
                if let dialog = browser.dialog {
                    if dialog.kind == .prompt { TextField("Eingabe", text: $promptText) }
                    if dialog.kind != .alert { Button("Abbrechen", role: .cancel) { browser.completeDialog(nil) } }
                    Button("OK") { browser.completeDialog(dialog.kind == .prompt ? promptText : "true") }
                } else { Button("OK") { browser.notice = nil; persistenceError = nil } }
            } message: { Text(browser.dialog?.message ?? persistenceError ?? browser.notice ?? "") }
    }

    private func normalizeSavedPages() {
        var seen = Set<String>()
        for (index, page) in pages.enumerated() {
            if let clean = StoredAddress.clean(page.address) { page.address = clean }
            if page.identifier.isEmpty || !seen.insert(page.identifier).inserted { page.identifier = UUID().uuidString; seen.insert(page.identifier) }
            if page.favoriteOrder == 0 { page.favoriteOrder = Double(index + 1) }
        }
        try? context.save()
    }

    private func recordVisit(_ title: String, _ address: String) {
        do {
            var request = FetchDescriptor<SavedPage>(predicate: #Predicate { $0.address == address })
            request.fetchLimit = 1
            if let existing = try context.fetch(request).first {
                if !existing.customTitle { existing.title = title }
                existing.visitedAt = .now
            } else {
                context.insert(SavedPage(title: title, address: address))
            }
            // Bound local history while preserving every favorite.
            let history = try context.fetch(FetchDescriptor<SavedPage>(predicate: #Predicate { !$0.favorite },
                sortBy: [SortDescriptor(\SavedPage.visitedAt, order: .reverse)]))
            for old in history.dropFirst(500) { context.delete(old) }
            try context.save()
            syncFavorites()
        } catch { persistenceError = "Verlauf konnte nicht gespeichert werden: \(error.localizedDescription)" }
    }

    private func favoriteCurrent() {
        let tab = browser.current
        guard let address = StoredAddress.clean(tab.address) else { return }
        do {
            var request = FetchDescriptor<SavedPage>(predicate: #Predicate { $0.address == address })
            request.fetchLimit = 1
            if let existing = try context.fetch(request).first {
                existing.favorite.toggle(); if existing.favorite { existing.favoriteOrder = (pages.filter(\.favorite).map(\.favoriteOrder).max() ?? 0) + 1 }
            }
            else {
                let page = SavedPage(title: tab.title, address: address, favorite: true)
                page.favoriteOrder = (pages.filter(\.favorite).map(\.favoriteOrder).max() ?? 0) + 1; context.insert(page)
            }
            saveAndSync()
        } catch { persistenceError = error.localizedDescription }
    }

    private func saveAndSync() {
        do { try context.save(); syncFavorites() }
        catch { persistenceError = "Änderung konnte nicht gespeichert werden: \(error.localizedDescription)" }
    }

    private func syncFavorites() {
        let request = FetchDescriptor<SavedPage>(predicate: #Predicate { $0.favorite },
            sortBy: [SortDescriptor(\SavedPage.favoriteOrder), SortDescriptor(\SavedPage.visitedAt, order: .reverse)])
        guard let favorites = try? context.fetch(request) else { return }
        FavoriteStorage.write(favorites.compactMap { page in StoredAddress.clean(page.address).map { FavoriteSnapshot(id: page.identifier, title: page.title, address: $0) } })
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
    let showQueue: () -> Void
    let showPlayer: () -> Void
    let showDownloads: () -> Void
    let showAddress: () -> Void
    let favorite: () -> Void
    let isFavorite: Bool
    @State private var draft = ""
    @FocusState private var editing: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ObservedObject private var cast = CastService.shared
    @State private var watchActionsVisible = false
    @State private var pendingWatchAction: (() -> Void)?
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 60
    private var isHome: Bool { tab.address.isEmpty && !tab.loading }
    private var isWatch: Bool { YouTubeAddress.isWatchPage(URL(string: tab.address)) }
    private var shortcutSize: CGFloat { min(iconSize, dynamicType.isAccessibilitySize ? 84 : 64) }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicType.isAccessibilitySize ? 2 : 4) }

    var body: some View {
        VStack(spacing: 0) {
            if !isHome && !isWatch {
                addressBar.padding(.horizontal, 12).padding(.vertical, 8)
                if sizeClass == .regular { tabStrip }
                ProgressView(value: tab.progress).progressViewStyle(.linear)
                    .frame(height: 2).opacity(tab.loading ? 1 : 0)
            }
            ZStack {
                if isHome { home }
                else { BrowserWebView(tab: tab, watchPresentation: isWatch) }
                if let error = tab.error {
                    ContentUnavailableView {
                        Label("Seite nicht geladen", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Erneut laden") { tab.reload() }.buttonStyle(.borderedProminent)
                    }.background(.background)
                }
            }
            if !isWatch {
                if tab.hasMedia || cast.isControllingMedia { mediaControls }
                if browser.sleepPlan.isActive { timerStatus }
                bottomBar
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isWatch {
                Button { watchActionsVisible = true } label: {
                    Image(systemName: "ellipsis").font(.system(size: 21, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(Color.red, in: Circle()).contentShape(Circle())
                }
                .accessibilityLabel("Browseraktionen")
                .padding(.trailing, 14).padding(.bottom, 18)
            }
        }
        .sheet(isPresented: $watchActionsVisible, onDismiss: {
            let action = pendingWatchAction
            pendingWatchAction = nil
            action?()
        }) { watchActions }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(.white)
        .onAppear { draft = tab.address }
        .onChange(of: tab.address) { _, value in if !editing { draft = value } }
    }

    private var addressBar: some View {
        HStack(spacing: 12) {
            Image(systemName: tab.isPrivate ? "hand.raised" : "magnifyingglass").foregroundStyle(.white.opacity(0.65)).accessibilityHidden(true)
            TextField("Suchen oder Adresse", text: $draft)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.webSearch)
                .submitLabel(.go).focused($editing)
                .onSubmit { openDraft() }
                .accessibilityLabel("Suchen oder Adresse")
            if editing && !draft.isEmpty {
                Button { draft = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("Eingabe löschen").frame(minWidth: 28, minHeight: 28)
            } else if !isHome {
                Button { tab.loading ? tab.webView.stopLoading() : tab.reload() } label: {
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
                Text(title).font(.caption2).foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
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
            ViewThatFits(in: .horizontal) {
                if !dynamicType.isAccessibilitySize {
                    HStack(spacing: 8) { playbackButtons; playbackPosition; Spacer(minLength: 0); routeButtons }
                }
                VStack(spacing: 4) {
                    HStack(spacing: 8) { playbackButtons; Spacer(minLength: 0); playbackPosition }
                    HStack(spacing: 8) { Spacer(); routeButtons; Spacer() }
                }
            }.font(.title3)
            if cast.isControllingMedia { Button("Cast-Steuerung") { cast.showControls() } }
            else { NativeVolumeControl().frame(height: 28).accessibilityLabel("Systemlautstärke") }
            if tab.waiting || !tab.mediaError.isEmpty {
                HStack {
                    if tab.waiting { ProgressView().controlSize(.small) }
                    Text(tab.mediaError.isEmpty ? "Player lädt …" : tab.mediaError).font(.caption)
                    Spacer()
                    Button { tab.runMedia("globalThis.__webkweb?.recover()") } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Wiedergabe erneut versuchen")
                }
            }
            if browser.sponsorBlockEnabled && !cast.isControllingMedia {
                HStack {
                    Button("Skip", systemImage: "forward.end") { tab.runMedia("globalThis.__webkweb?.skip()") }
                    Button("Zurück", systemImage: "arrow.uturn.backward") { tab.runMedia("globalThis.__webkweb?.undoSkip()") }.disabled(!tab.canUndoSkip)
                }.font(.caption)
            }
            if browser.gesturesEnabled { SeekGesturePad(seek: browser.seek) }
        }.padding(.horizontal, 18).padding(.vertical, 10)
            .browserGlass(radius: 22).padding(.horizontal, 8)
    }

    private var playbackButtons: some View {
        Group {
            Button { browser.seek(-10) } label: { Image(systemName: "gobackward.10").frame(width: 44, height: 44) }.accessibilityLabel("10 Sekunden zurück")
            Button { browser.togglePlayback() } label: {
                Image(systemName: (cast.isControllingMedia ? cast.isPlaying : tab.playing) ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
            }.accessibilityLabel((cast.isControllingMedia ? cast.isPlaying : tab.playing) ? "Pausieren" : "Abspielen")
            Button { browser.seek(10) } label: { Image(systemName: "goforward.10").frame(width: 44, height: 44) }.accessibilityLabel("10 Sekunden vor")
        }
    }
    private var playbackPosition: some View {
        Text(time(cast.isControllingMedia ? cast.elapsed : tab.playbackTime)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
    }
    private var routeButtons: some View {
        Group {
            Button { tab.runMedia("globalThis.__webkweb?.fullscreen()") } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44) }
                .disabled(cast.isControllingMedia || tab.activeMediaKind != "video").accessibilityLabel("Vollbild")
            Button { tab.runMedia("globalThis.__webkweb?.pip()") } label: { Image(systemName: "pip").frame(width: 44, height: 44) }
                .disabled(cast.isControllingMedia).accessibilityLabel("Bild-in-Bild")
            AirPlayControl().frame(width: 44, height: 44).accessibilityLabel("AirPlay-Auswahl")
            Button(action: showCast) { Image(systemName: "tv").frame(width: 44, height: 44) }.accessibilityLabel("Cast-Optionen")
            Button(action: showPlayer) { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.accessibilityLabel("Player-Einstellungen")
        }
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
            if isWatch {
                Section("Navigation") {
                    Button("Zurück", systemImage: "chevron.left") { tab.webView.goBack() }.disabled(!tab.canGoBack)
                    Button("Vorwärts", systemImage: "chevron.right") { tab.webView.goForward() }.disabled(!tab.canGoForward)
                    Button("Startseite", systemImage: "house") { browser.addTab() }
                    Button("Tabs", systemImage: "square.on.square", action: showTabs)
                    Button("Adresse oder Suche", systemImage: "magnifyingglass", action: showAddress)
                    Button(tab.loading ? "Laden stoppen" : "Neu laden", systemImage: tab.loading ? "xmark" : "arrow.clockwise") { tab.loading ? tab.webView.stopLoading() : tab.reload() }
                    Button(isFavorite ? "Favorit entfernen" : "Als Favorit speichern", systemImage: isFavorite ? "star.fill" : "star", action: favorite)
                }
                Section("Wiedergabe") {
                    Button((cast.isControllingMedia ? cast.isPlaying : tab.playing) ? "Pausieren" : "Abspielen", systemImage: (cast.isControllingMedia ? cast.isPlaying : tab.playing) ? "pause" : "play") { browser.togglePlayback() }.disabled(!tab.hasMedia && !cast.isControllingMedia)
                    Button("10 Sekunden zurück", systemImage: "gobackward.10") { browser.seek(-10) }.disabled(!tab.hasMedia && !cast.isControllingMedia)
                    Button("10 Sekunden vor", systemImage: "goforward.10") { browser.seek(10) }.disabled(!tab.hasMedia && !cast.isControllingMedia)
                    Button("Auf dem Fernseher", systemImage: "tv", action: showCast)
                    if browser.sponsorBlockEnabled && !cast.isControllingMedia {
                        Button("Segment überspringen", systemImage: "forward.end") { tab.runMedia("globalThis.__webkweb?.skip()") }
                        Button("Skip rückgängig", systemImage: "arrow.uturn.backward") { tab.runMedia("globalThis.__webkweb?.undoSkip()") }.disabled(!tab.canUndoSkip)
                    }
                    if browser.sleepPlan.isActive { Button("Timer abbrechen", systemImage: "moon.zzz") { browser.cancelSleep() } }
                }
            }
            Button("Neuer Tab", systemImage: "plus") { browser.addTab() }
            Button("Privater Tab", systemImage: "hand.raised") { browser.addTab(isPrivate: true) }
            Button("Favoriten", systemImage: "star", action: showLibrary)
            Button("Verlauf", systemImage: "clock.arrow.circlepath", action: showHistory)
            Button("Sleep-Timer", systemImage: "moon.zzz", action: showSleep)
            Button("Queue", systemImage: "music.note.list", action: showQueue)
            #if !WEBKWEB_NO_DOWNLOADS
            Button("Downloads", systemImage: "arrow.down.circle", action: showDownloads)
            #endif
            if !isHome {
                Button("Zur Queue", systemImage: "text.badge.plus") { browser.enqueueCurrent() }.disabled(tab.isPrivate)
                Button("Player", systemImage: "slider.horizontal.3", action: showPlayer).disabled(!tab.hasMedia)
                #if !WEBKWEB_NO_DOWNLOADS
                if let media = tab.directMedia, DownloadStore.supports(media) {
                    Button("Mediendatei speichern", systemImage: "arrow.down.to.line") { DownloadStore.shared.start(media, title: tab.title); showDownloads() }
                }
                #endif
            }
            Button("Einstellungen", systemImage: "gear", action: showSettings)
            Toggle("Netzwerkfilter", isOn: $browser.blockingEnabled)
            if let host = URL(string: tab.address)?.host {
                Button(browser.shouldBlock(URL(string: tab.address)) ? "Filter für diese Seite aus" : "Filter für diese Seite ein", systemImage: "shield") {
                    if let allowed = browser.options.allowlist.first(where: { host == $0 || host.hasSuffix("." + $0) }) { browser.options.allowlist.removeAll { $0 == allowed } } else { browser.options.allowlist.append(host) }
                }
            }
            if let host = URL(string: tab.address)?.host {
                Button(browser.shouldSponsor(URL(string: tab.address), page: URL(string: tab.address)) ? "SponsorBlock hier aus" : "SponsorBlock hier ein", systemImage: "forward.end") {
                    if let allowed = browser.options.sponsorAllowlist.first(where: { host == $0 || host.hasSuffix("." + $0) }) { browser.options.sponsorAllowlist.removeAll { $0 == allowed } } else { browser.options.sponsorAllowlist.append(host) }
                }
            }
            if let url = URL(string: tab.address) { ShareLink(item: url) }
            Button("Alles pausieren", systemImage: "pause.circle") { browser.pauseAll() }
        } label: {
            if isWatch {
                Image(systemName: "ellipsis").font(.system(size: 21, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Color(red: 1, green: 0, blue: 0), in: Circle()).contentShape(Circle())
            } else { Image(systemName: "ellipsis").frame(width: 48, height: 48).browserGlass(radius: 24) }
        }
        .buttonStyle(.plain).accessibilityLabel("Browsermenü")
        .accessibilityHint("Navigation, Adresse, Tabs und Wiedergabeoptionen")
    }

    private func closeWatchActions(then action: @escaping () -> Void) {
        pendingWatchAction = action
        watchActionsVisible = false
    }

    private var watchActions: some View {
        NavigationStack {
            List {
                Section("Wiedergabe") {
                    Button((cast.isControllingMedia ? cast.isPlaying : tab.playing) ? "Pausieren" : "Abspielen",
                           systemImage: (cast.isControllingMedia ? cast.isPlaying : tab.playing) ? "pause" : "play") {
                        closeWatchActions { browser.togglePlayback() }
                    }.disabled(!tab.hasMedia && !cast.isControllingMedia)
                    Button("10 Sekunden zurück", systemImage: "gobackward.10") { closeWatchActions { browser.seek(-10) } }
                        .disabled(!tab.hasMedia && !cast.isControllingMedia)
                    Button("10 Sekunden vor", systemImage: "goforward.10") { closeWatchActions { browser.seek(10) } }
                        .disabled(!tab.hasMedia && !cast.isControllingMedia)
                    Button("Bild-in-Bild", systemImage: "pip") {
                        closeWatchActions { tab.runMedia("globalThis.__webkweb?.pip()") }
                    }.disabled(!tab.hasMedia || cast.isControllingMedia)
                    Button("Auf dem Fernseher", systemImage: "tv") { closeWatchActions(showCast) }
                    if browser.sponsorBlockEnabled && !cast.isControllingMedia {
                        Button("Sponsorsegment überspringen", systemImage: "forward.end") {
                            closeWatchActions { tab.runMedia("globalThis.__webkweb?.skip()") }
                        }
                        Button("Sponsor-Skip rückgängig", systemImage: "arrow.uturn.backward") {
                            closeWatchActions { tab.runMedia("globalThis.__webkweb?.undoSkip()") }
                        }.disabled(!tab.canUndoSkip)
                    }
                    if browser.sleepPlan.isActive {
                        Button("Timer abbrechen", systemImage: "moon.zzz") { closeWatchActions { browser.cancelSleep() } }
                    }
                }
                Section("Navigation") {
                    Button("Zurück", systemImage: "chevron.left") { closeWatchActions { tab.webView.goBack() } }
                        .disabled(!tab.canGoBack)
                    Button("Vorwärts", systemImage: "chevron.right") { closeWatchActions { tab.webView.goForward() } }
                        .disabled(!tab.canGoForward)
                    Button("Startseite", systemImage: "house") { closeWatchActions { browser.addTab() } }
                    Button("Tabs", systemImage: "square.on.square") { closeWatchActions(showTabs) }
                    Button("Adresse oder Suche", systemImage: "magnifyingglass") { closeWatchActions(showAddress) }
                    Button(tab.loading ? "Laden stoppen" : "Neu laden", systemImage: tab.loading ? "xmark" : "arrow.clockwise") {
                        closeWatchActions { tab.loading ? tab.webView.stopLoading() : tab.reload() }
                    }
                    Button(isFavorite ? "Favorit entfernen" : "Als Favorit speichern", systemImage: "star") { closeWatchActions(favorite) }
                }
                Section("Browser") {
                    Button("Neuer Tab", systemImage: "plus") { closeWatchActions { browser.addTab() } }
                    Button("Privater Tab", systemImage: "hand.raised") { closeWatchActions { browser.addTab(isPrivate: true) } }
                    Button("Favoriten", systemImage: "star") { closeWatchActions(showLibrary) }
                    Button("Verlauf", systemImage: "clock.arrow.circlepath") { closeWatchActions(showHistory) }
                    Button("Sleep-Timer", systemImage: "moon.zzz") { closeWatchActions(showSleep) }
                    Button("Queue", systemImage: "music.note.list") { closeWatchActions(showQueue) }
                    #if !WEBKWEB_NO_DOWNLOADS
                    Button("Downloads", systemImage: "arrow.down.circle") { closeWatchActions(showDownloads) }
                    #endif
                    Button("Zur Queue", systemImage: "text.badge.plus") { closeWatchActions { browser.enqueueCurrent() } }
                        .disabled(tab.isPrivate)
                    Button("Player", systemImage: "slider.horizontal.3") { closeWatchActions(showPlayer) }
                        .disabled(!tab.hasMedia)
                    Button("Einstellungen", systemImage: "gear") { closeWatchActions(showSettings) }
                    Toggle("Netzwerkfilter", isOn: $browser.blockingEnabled)
                    if let host = URL(string: tab.address)?.host {
                        Button(browser.shouldBlock(URL(string: tab.address)) ? "Filter für diese Seite aus" : "Filter für diese Seite ein",
                               systemImage: "shield") {
                            closeWatchActions {
                                if let allowed = browser.options.allowlist.first(where: { host == $0 || host.hasSuffix("." + $0) }) {
                                    browser.options.allowlist.removeAll { $0 == allowed }
                                } else { browser.options.allowlist.append(host) }
                            }
                        }
                        Button(browser.shouldSponsor(URL(string: tab.address), page: URL(string: tab.address)) ? "SponsorBlock hier aus" : "SponsorBlock hier ein",
                               systemImage: "forward.end") {
                            closeWatchActions {
                                if let allowed = browser.options.sponsorAllowlist.first(where: { host == $0 || host.hasSuffix("." + $0) }) {
                                    browser.options.sponsorAllowlist.removeAll { $0 == allowed }
                                } else { browser.options.sponsorAllowlist.append(host) }
                            }
                        }
                    }
                    if let url = URL(string: tab.address) { ShareLink(item: url) }
                    Button("Alles pausieren", systemImage: "pause.circle") { closeWatchActions { browser.pauseAll() } }
                }
            }
            .navigationTitle("Aktionen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schließen", systemImage: "xmark") { watchActionsVisible = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
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

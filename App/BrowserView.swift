import SwiftUI
import SwiftData
import WidgetKit
import WebKit
import UIKit

private enum BrowserSheet: String, Identifiable {
    case library, collection, history, tabs, sleep, settings, airplay, queue, player, address
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
    @State private var confirmPrivateFavorite = false
    @StateObject private var shield = PrivacyShield()
    @EnvironmentObject private var native: NativePlayer

    private var favoriteDigest: [String] {
        pages.filter(\.favorite).map { "\($0.identifier)|\($0.title)|\($0.address)|\($0.favoriteOrder)" }.sorted()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            BrowserScreen(tab: browser.current, showLibrary: { sheet = .collection },
                showHistory: { sheet = .history },
                showTabs: { sheet = .tabs }, showSleep: { sheet = .sleep },
                showSettings: { sheet = .settings }, showAirPlay: { sheet = .airplay },
                showQueue: { sheet = .queue }, showPlayer: { sheet = .player },
                showAddress: { sheet = .address },
                favorite: { favoriteCurrent() }, isFavorite: pages.contains { $0.favorite && $0.address == StoredAddress.clean(browser.current.address) })
                .id(browser.current.id)
                .frame(height: native.isOpen && native.focus ? 0 : nil)
                .clipped().accessibilityHidden(native.isOpen && native.focus)
                .toolbar(.hidden, for: .navigationBar)
                .sheet(item: $sheet) { selected in
                    switch selected {
                    case .collection: LibraryHubView(library: browser.library)
                    case .library: LibraryView(open: { address in browser.open(address); sheet = nil }, didChange: saveAndSync)
                    case .history: LibraryView(open: { address in browser.open(address); sheet = nil }, didChange: saveAndSync, initialSection: .history)
                    case .tabs: TabsView()
                    case .sleep: SleepTimerView()
                    case .settings: SettingsView()
                    case .airplay: AirPlayView(tab: browser.current)
                    case .queue: QueueView()
                    case .player: PlayerOptionsView(tab: browser.current)
                    case .address: AddressEntryView().presentationDetents([.medium, .large])
                    }
                }
                if native.isOpen { NativePlayerPanel(playback: native) }
            }
        }
        .opacity(browser.privacyLocked ? 0 : 1)
        .allowsHitTesting(!browser.privacyLocked)
        .accessibilityHidden(browser.privacyLocked)
        .confirmationDialog("Diesen Link aus dem Privatbereich in normale Favoriten übernehmen? Er kann nach deiner Freigabe auch in Widgets, Exporten und Kurzbefehlen erscheinen.", isPresented: $confirmPrivateFavorite, titleVisibility: .visible) {
            Button("In normale Favoriten speichern") { favoriteCurrent(allowPrivate: true) }
        }
        .task {
            browser.onVisit = recordVisit
            normalizeSavedPages()
            syncFavorites()
            shield.update(phase: scenePhase, browser: browser)
            if !browser.privacyLocked { browser.consumeSharedLinks() }
        }
        .onChange(of: favoriteDigest) { _, _ in syncFavorites() }
        .onChange(of: browser.options.shareFavoritesWithSystem) { _, _ in syncFavorites() }
        .onChange(of: browser.options.privateLock) { _, _ in shield.update(phase: scenePhase, browser: browser) }
        .onChange(of: browser.privacyLocked) { _, locked in if !locked { browser.consumeSharedLinks() } }
        .onChange(of: scenePhase) { _, phase in
            native.sceneActive = phase == .active
            browser.enforceSleepDeadline()
            shield.update(phase: phase, browser: browser)
            if phase == .active { Task { await browser.foreground() } }
            else { if phase == .inactive { browser.playbackTab.attemptAutoPiP() }; browser.persistSession() }
        }
        .onReceive(router.$revision) { _ in
            for command in router.drain() {
                guard !browser.privacyLocked else { browser.notice = "App zuerst entsperren und Aktion erneut ausführen."; continue }
                switch command {
                case .open(let address): browser.open(address)
                case .sleep(let minutes): browser.sleep(minutes: minutes)
                case .pause: browser.pauseAll(blockAutoplay: true, reason: .shortcut)
                case .save(let address): _ = browser.library.addLink(title: URL(string: address)?.host ?? "Link", address: address)
                case .playlist(let name):
                    if let list = browser.library.document.playlists.first(where: { $0.name == name }) {
                        let native = list.mediaIDs.filter { id in browser.library.document.media.contains { $0.id == id && $0.kind != .website } }
                        if native.isEmpty { browser.notice = "Diese Liste enthält keine nativ abspielbaren Medien." } else { browser.nativePlayer.playPlaylist(native) }
                    } else { browser.notice = "Playlist nicht gefunden." }
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
            if StoredAddress.clean(page.address) == nil {
                if page.favorite, var parts = URLComponents(string: page.address), ["http", "https"].contains(parts.scheme ?? ""), parts.host != nil {
                    parts.user = nil; parts.password = nil; parts.query = nil; parts.fragment = nil
                    page.address = parts.url?.absoluteString ?? ""
                } else { context.delete(page); continue }
            }
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
                existing.visitedAt = .now; existing.isHistory = true
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

    private func favoriteCurrent(allowPrivate: Bool = false) {
        let tab = browser.current
        guard let address = LibraryAddress.clean(tab.address) else { persistenceError = "Vertrauliche oder ungültige Adresse wird nicht gespeichert."; return }
        if tab.isPrivate && !allowPrivate && !pages.contains(where: { $0.favorite && $0.address == address }) { confirmPrivateFavorite = true; return }
        do {
            var request = FetchDescriptor<SavedPage>(predicate: #Predicate { $0.address == address })
            request.fetchLimit = 1
            if let existing = try context.fetch(request).first {
                existing.favorite.toggle(); if existing.favorite { existing.favoriteOrder = (pages.filter(\.favorite).map(\.favoriteOrder).max() ?? 0) + 1 } else if !existing.isHistory { context.delete(existing) }
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
        guard browser.options.shareFavoritesWithSystem else { FavoriteStorage.write([]); WidgetCenter.shared.reloadAllTimelines(); return }
        let request = FetchDescriptor<SavedPage>(predicate: #Predicate { $0.favorite },
            sortBy: [SortDescriptor(\SavedPage.favoriteOrder), SortDescriptor(\SavedPage.visitedAt, order: .reverse)])
        guard let favorites = try? context.fetch(request) else { return }
        FavoriteStorage.write(favorites.compactMap { page in StoredAddress.clean(page.address).map { FavoriteSnapshot(id: page.identifier, title: page.title, address: $0) } }, consent: true)
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
    let showAirPlay: () -> Void
    let showQueue: () -> Void
    let showPlayer: () -> Void
    let showAddress: () -> Void
    let favorite: () -> Void
    let isFavorite: Bool
    @State private var draft = ""
    @State private var actionsPresented = false
    @State private var pendingAction: (() -> Void)?
    @FocusState private var editing: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 60
    private var isHome: Bool { tab.address.isEmpty && !tab.loading }
    private var isWatch: Bool { tab.presentsWatchImmersively }
    private var shortcutSize: CGFloat { min(iconSize, dynamicType.isAccessibilitySize ? 84 : 64) }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicType.isAccessibilitySize ? 2 : 4) }

    var body: some View {
        VStack(spacing: 0) {
            if isWatch { watchNavigation }
            if !isHome && !isWatch {
                addressBar.padding(.horizontal, 12).padding(.vertical, 8)
                if sizeClass == .regular { tabStrip }
                ProgressView(value: tab.progress).progressViewStyle(.linear)
                    .frame(height: 2).opacity(tab.loading ? 1 : 0)
            }
            ZStack {
                if isHome { home }
                else { BrowserWebView(tab: tab, watchPresentation: isWatch, leaveWatch: tab.leaveWatch) }
                if let error = tab.error {
                    ContentUnavailableView {
                        Label("Seite nicht geladen", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Erneut laden") { tab.reload() }.buttonStyle(.borderedProminent)

                        Button("Zur Startseite") { browser.home() }
                    }.background(.background)
                }
            }
            if !isWatch {
                if tab.hasMedia && tab.canControlMedia { mediaControls }
                if browser.sleepPlan.isActive || browser.sleepAfterNativeQueue { timerStatus }
                bottomBar
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isWatch { browserMenu.padding(.trailing, 14).padding(.bottom, 18) }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .sheet(isPresented: $actionsPresented, onDismiss: {
            let action = pendingAction; pendingAction = nil; action?()
        }) { browserActions }
        .tint(.primary)
        .onAppear { draft = tab.address }
        .onChange(of: tab.address) { _, value in if !editing { draft = value } }
    }

    private var watchNavigation: some View {
        HStack(spacing: 8) {
            Button { tab.leaveWatch() } label: {
                Image(systemName: "chevron.down").frame(width: 44, height: 44)
            }.accessibilityLabel("Video verlassen und zurück zu YouTube")
                .accessibilityIdentifier("browser.watch.exit")
                .accessibilityHint("Du kannst auch vom oberen Videobereich nach unten wischen")
            Button {
                tab.showNormalWebsite()
                browser.open("https://m.youtube.com/")
            } label: { Image(systemName: "house").frame(width: 44, height: 44) }
                .accessibilityLabel("YouTube-Startseite")
                .accessibilityIdentifier("browser.watch.home")
            Spacer()
        }.font(.system(size: 19, weight: .medium)).buttonStyle(.plain)
            .padding(.horizontal, 8).background(Color(.systemBackground))
    }

    private var addressBar: some View {
        HStack(spacing: 12) {
            Image(systemName: tab.isPrivate ? "hand.raised" : "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
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
                    if !tab.isPrivate {
                        ForEach(Array(library.document.media.filter { $0.kind != .website && $0.position > 0 && !$0.completed }.sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }.prefix(3))) { item in
                            Button { browser.nativePlayer.open(item.id) } label: { Label(item.title, systemImage: "play.circle").lineLimit(1) }.accessibilityLabel("Weitersehen: " + item.title)
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 24) {
                        shortcut("Mediathek", symbol: "star", action: showLibrary)
                        shortcut("Verlauf", symbol: "clock.arrow.circlepath", action: showHistory)
                        shortcut("Linkqueue", symbol: "music.note.list", action: showQueue)
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
                Text(title).font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore).accessibilityLabel(title)
    }

    private func shortcut(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        shortcut(title, action: action) {
            Image(systemName: symbol).font(.system(size: 23, weight: .medium)).foregroundStyle(.primary)
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(browser.tabs) { item in
                    TabPill(tab: item, selected: item.id == browser.selectedID,
                        select: { browser.selectedID = item.id }, close: { browser.close(item.id) })
                }
                Button { browser.home() } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
            }.padding(.horizontal, 12)
        }.padding(.bottom, 8)
    }

    private var mediaControls: some View {
        // Keep the website visible. Detailed controls, volume, recovery and
        // optional seek gestures live in the player sheet, not a second panel.
        HStack(spacing: 4) {
            Button { browser.togglePlayback() } label: {
                Image(systemName: tab.playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
            }.accessibilityLabel(tab.playing ? "Pausieren" : "Abspielen")

            ProgressView(value: mediaProgress ?? 0).progressViewStyle(.linear)
                .tint(.primary).frame(height: 2).clipped()
                .accessibilityLabel("Wiedergabefortschritt")
                .accessibilityValue(mediaProgress == nil ? "Live oder unbekannte Dauer" : time(tab.playbackTime))

            Button(action: showPlayer) {
                Group {
                    if !tab.mediaError.isEmpty { Image(systemName: "exclamationmark.circle").foregroundStyle(.red) }
                    else if tab.waiting { ProgressView().controlSize(.small) }
                    else { Image(systemName: "slider.horizontal.3") }
                }.frame(width: 44, height: 44)
            }.accessibilityLabel("Player-Einstellungen")
                .accessibilityValue(tab.mediaError.isEmpty ? (tab.waiting ? "Player lädt" : "") : tab.mediaError)
                .accessibilityHint("Öffnet weitere Bedienelemente und Hilfe bei Wiedergabefehlern")
        }
        .font(.system(size: 15, weight: .medium)).buttonStyle(.plain)
        .padding(.horizontal, 12).frame(height: 44)
        .frame(maxWidth: 700).frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var mediaProgress: Double? {
        guard let duration = tab.duration, duration.isFinite, duration > 0,
              tab.playbackTime.isFinite else { return nil }
        return min(1, max(0, tab.playbackTime / duration))
    }

    private var timerStatus: some View {
        HStack {
            Image(systemName: "moon.zzz")
            if let deadline = browser.sleepPlan.deadline { Text(deadline, style: .timer).monospacedDigit() }
            else if browser.sleepAfterNativeQueue { Text("Nach Queue-Ende") }
            else if let remaining = browser.sleepPlan.remainingVideos { Text("\(remaining) Video(s)") }
            Spacer()
            if browser.sleepPlan.deadline != nil { Button("+10 Min") { browser.extendSleep() } }
            Button { browser.cancelSleep() } label: { Image(systemName: "xmark") }.accessibilityLabel("Timer abbrechen")
        }.font(.caption).padding(12).browserGlass(radius: 18).padding(.horizontal, 12).padding(.top, 8)
            .accessibilityLabel("Sleep-Timer")
    }

    private var bottomBar: some View {
        HStack(spacing: isHome ? 12 : 8) {
            if !isHome {
                HStack(spacing: 2) {
                    Button { browser.backOrHome() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 48) }
                        .accessibilityLabel(tab.canGoBack ? "Zurück" : "Startseite")
                    Button { tab.webView.goForward() } label: { Image(systemName: "chevron.right").frame(width: 44, height: 48) }
                        .disabled(!tab.canGoForward).accessibilityLabel("Vorwärts")
                }.browserGlass(radius: 24)
                Button(action: favorite) { Image(systemName: isFavorite ? "star.fill" : "star").frame(width: 44, height: 48) }
                    .browserGlass(radius: 24).accessibilityLabel(isFavorite ? "Favorit entfernen" : "Als Favorit speichern")
                Spacer(minLength: 0)
            } else {
                Button { browser.home() } label: { Image(systemName: "house").frame(width: 72, height: 48) }
                    .browserGlass(radius: 24).accessibilityLabel("Startseite")
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
        Button { actionsPresented = true } label: {
            if isWatch {
                Image(systemName: "ellipsis").font(.system(size: 21, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Color(red: 1, green: 0, blue: 0), in: Circle()).contentShape(Circle())
            } else { Image(systemName: "ellipsis").frame(width: 48, height: 48).browserGlass(radius: 24) }
        }
        .buttonStyle(.plain).accessibilityLabel("Browsermenü").accessibilityIdentifier("browser.actions")
        .accessibilityHint("Öffnet Navigation, Adresse, Tabs und Wiedergabeoptionen")
        #if DEBUG
        // UI-test failures can read the same redacted report without reaching
        // into WebKit or relying on clipboard permissions. Not in Release.
        .accessibilityValue(ProcessInfo.processInfo.arguments.contains("--ui-test-browser") ? tab.mediaDiagnosticReport() : "")
        #endif
    }

    // A modal list keeps stable hit targets while WebKit publishes progress and
    // playback changes. It also prevents gestures from reaching the page below.
    private var browserActions: some View {
        NavigationStack {
            List {
                Section("Navigation") {
                    action("Zurück oder Startseite", symbol: "chevron.left") { browser.backOrHome() }
                    action("Vorwärts", symbol: "chevron.right", enabled: tab.canGoForward) { tab.webView.goForward() }
                    action("Startseite", symbol: "house") { browser.home() }
                    action("Tabs", symbol: "square.on.square", perform: showTabs)
                    action("Adresse oder Suche", symbol: "magnifyingglass", perform: showAddress)
                    action("Neu laden", symbol: "arrow.clockwise", enabled: !isHome) { tab.reload() }
                    if YouTubeAddress.isWatchPage(URL(string: tab.address)) {
                        action("Normale YouTube-Ansicht", symbol: "rectangle.topthird.inset.filled") { tab.showNormalWebsite() }
                        action("Video verlassen", symbol: "chevron.down") { tab.leaveWatch() }
                        if !isWatch { action("Videoansicht", symbol: "play.rectangle") { tab.showWatchPresentation() } }
                    }
                }
                Section("Wiedergabe") {
                    if tab.canControlMedia {
                    action("Abspielen", symbol: "play", enabled: tab.hasMedia && tab.canControlMedia) { browser.play() }
                    action("\(browser.options.skipSeconds) Sekunden zurück", symbol: "gobackward", enabled: tab.hasMedia && tab.canControlMedia) { browser.seek(-Double(browser.options.skipSeconds)) }
                    action("\(browser.options.skipSeconds) Sekunden vor", symbol: "goforward", enabled: tab.hasMedia && tab.canControlMedia) { browser.seek(Double(browser.options.skipSeconds)) }
                    action("Player", symbol: "slider.horizontal.3", enabled: tab.hasMedia, perform: showPlayer)
                    } else { Text(SourceCapabilities.forSource(.website).explanation).font(.footnote).foregroundStyle(.secondary) }
                    action("Alles pausieren", symbol: "pause.circle") { browser.pauseAll() }
                    action("AirPlay", symbol: "tv", perform: showAirPlay)
                    action("Sleep-Timer", symbol: "moon.zzz", perform: showSleep)
                    if browser.sleepPlan.isActive { action("Timer abbrechen", symbol: "xmark") { browser.cancelSleep() } }
                }
                Section("Sammlung") {
                    action("Favoriten", symbol: "star", perform: showLibrary)
                    action("Verlauf", symbol: "clock.arrow.circlepath", perform: showHistory)
                    action(isFavorite ? "Favorit entfernen" : "Als Favorit speichern", symbol: isFavorite ? "star.fill" : "star", enabled: !isHome, perform: favorite)
                    action("Linkqueue", symbol: "music.note.list", perform: showQueue)
                    action("Zur Queue", symbol: "text.badge.plus", enabled: !isHome && !tab.isPrivate) { browser.enqueueCurrent() }
                }
                Section("Browser") {
                    action("Neuer Tab", symbol: "plus") { browser.home() }
                    action("Privater Tab", symbol: "hand.raised") { browser.addTab(isPrivate: true) }
                    action("Einstellungen", symbol: "gear", perform: showSettings)
                    if let url = URL(string: tab.address) {
                        ShareLink(item: url).frame(minHeight: 44)
                        if !tab.isPrivate { action("Im Standardbrowser öffnen", symbol: "safari") { UIApplication.shared.open(url) } }
                    }
                    action("Playerdiagnose kopieren", symbol: "doc.on.doc", enabled: tab.hasMedia && !tab.isPrivate) {
                        UIPasteboard.general.setItems([["public.utf8-plain-text": tab.mediaDiagnosticReport()]],
                            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)])
                        browser.notice = "Playerdiagnose kopiert. Sie enthält keine Videoadressen, Seitentitel oder Cookies."
                    }
                }
            }.accessibilityIdentifier("browser.actions.panel")
                .navigationTitle("Browser").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { actionsPresented = false }.accessibilityIdentifier("browser.actions.close")
                    }
                }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }

    private func action(_ title: String, symbol: String, enabled: Bool = true, perform: @escaping () -> Void) -> some View {
        Button {
            pendingAction = perform
            actionsPresented = false
        } label: { Label(title, systemImage: symbol).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }
            .disabled(!enabled)
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
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(selected ? 0.35 : 0), lineWidth: 1) }
    }
}

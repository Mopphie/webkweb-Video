import AppIntents
import Combine
import Foundation

enum BrowserCommand {
    case open(String)
    case sleep(Int)
    case pause
    case save(String)
    case playlist(String)
}

@MainActor
final class IntentRouter: ObservableObject {
    static let shared = IntentRouter()
    @Published private(set) var revision: UInt = 0
    private var queue: [BrowserCommand] = []
    func send(_ command: BrowserCommand) { guard queue.count < 32 else { return }; queue.append(command); revision &+= 1 }
    func drain() -> [BrowserCommand] { let pending = queue; queue.removeAll(); return pending }
    init() {}
}

struct OpenWebPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Webseite oder Suche öffnen"
    static var description = IntentDescription("Öffnet eine Adresse oder Suche mit deiner gewählten Suchmaschine in DevnTube.")
    static var openAppWhenRun = true
    @Parameter(title: "Adresse oder Suchbegriff") var address: String

    func perform() async throws -> some IntentResult {
        await MainActor.run { IntentRouter.shared.send(.open(address)) }
        return .result()
    }
}

struct OpenFavoriteIntent: AppIntent {
    static var title: LocalizedStringResource = "Favorit öffnen"
    static var openAppWhenRun = true
    @Parameter(title: "Favorit") var favorite: FavoriteEntity
    func perform() async throws -> some IntentResult {
        if let value = FavoriteStorage.read().first(where: { $0.id == favorite.id }) {
            await MainActor.run { IntentRouter.shared.send(.open(value.address)) }
        }
        return .result()
    }
}

struct StartSleepTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Sleep-Timer starten"
    static var openAppWhenRun = true
    @Parameter(title: "Minuten", default: 30) var minutes: Int
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard (1...1440).contains(minutes) else {
            return .result(dialog: "Wähle zwischen 1 und 1440 Minuten.")
        }
        await MainActor.run { IntentRouter.shared.send(.sleep(minutes)) }
        return .result(dialog: "Sleep-Timer für \(minutes) Minuten angefordert. Bei aktiver App-Sperre zuerst entsperren und die Aktion erneut starten.")
    }
}

struct PausePlaybackIntent: AppIntent {
    static var title: LocalizedStringResource = "Wiedergabe pausieren"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        await MainActor.run { IntentRouter.shared.send(.pause) }
        return .result()
    }
}

struct VideoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenWebPageIntent(), phrases: ["Öffne eine Webseite in \(.applicationName)"],
                    shortTitle: "Webseite öffnen", systemImageName: "globe")
        AppShortcut(intent: OpenFavoriteIntent(), phrases: ["Öffne einen Favoriten in \(.applicationName)"],
                    shortTitle: "Favorit öffnen", systemImageName: "star")
        AppShortcut(intent: StartSleepTimerIntent(), phrases: ["Starte den Sleep-Timer in \(.applicationName)"],
                    shortTitle: "Sleep-Timer", systemImageName: "moon.zzz")
        AppShortcut(intent: SaveLinkIntent(), phrases: ["Speichere einen Link in \(.applicationName)"], shortTitle: "Link speichern", systemImageName: "bookmark")
        AppShortcut(intent: OpenPlaylistIntent(), phrases: ["Öffne eine Playlist in \(.applicationName)"], shortTitle: "Playlist", systemImageName: "music.note.list")
        AppShortcut(intent: PausePlaybackIntent(), phrases: ["Pausiere die Wiedergabe in \(.applicationName)"],
                    shortTitle: "Pausieren", systemImageName: "pause.circle")
    }
}

struct SaveLinkIntent: AppIntent {
    static var title: LocalizedStringResource = "Link in Mediathek speichern"
    static var openAppWhenRun = true
    @Parameter(title: "HTTP(S)-Adresse") var address: String
    func perform() async throws -> some IntentResult {
        if let clean = StoredAddress.clean(address) { await MainActor.run { IntentRouter.shared.send(.save(clean)) } }
        return .result()
    }
}
struct OpenPlaylistIntent: AppIntent {
    static var title: LocalizedStringResource = "Vorhandene Playlist abspielen"
    static var openAppWhenRun = true
    @Parameter(title: "Listenname") var name: String
    func perform() async throws -> some IntentResult {
        guard name.count <= 100 else { return .result() }
        await MainActor.run { IntentRouter.shared.send(.playlist(name)) }
        return .result()
    }
}

import AppIntents
import Combine
import Foundation

enum BrowserCommand {
    case open(String)
    case sleep(Int)
    case pause
}

@MainActor
final class IntentRouter: ObservableObject {
    static let shared = IntentRouter()
    @Published private(set) var revision: UInt = 0
    private var queue: [BrowserCommand] = []
    func send(_ command: BrowserCommand) { queue.append(command); revision &+= 1 }
    func drain() -> [BrowserCommand] { let pending = queue; queue.removeAll(); return pending }
    private init() {}
}

struct OpenWebPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Webseite oder Suche öffnen"
    static var description = IntentDescription("Öffnet eine Adresse oder Suche mit deiner gewählten Suchmaschine in WebKWeb.")
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
        await MainActor.run { IntentRouter.shared.send(.open(favorite.address)) }
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
        return .result(dialog: "Sleep-Timer für \(minutes) Minuten gestartet.")
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
        AppShortcut(intent: PausePlaybackIntent(), phrases: ["Pausiere die Wiedergabe in \(.applicationName)"],
                    shortTitle: "Pausieren", systemImageName: "pause.circle")
    }
}

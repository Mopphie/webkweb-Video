import SwiftUI
import SwiftData
import AVFoundation

@main
@MainActor
struct WebKWebApp: App {
    @StateObject private var browser = BrowserModel()
    private let container: ModelContainer?
    private let storageError: String?

    init() {
        do {
            let config = ModelConfiguration(cloudKitDatabase: .none)
            container = try ModelContainer(for: SavedPage.self, configurations: config)
            storageError = nil
        } catch {
            container = nil
            storageError = error.localizedDescription
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // The web player still works if iOS refuses audio-session activation.
        }
        CastService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                BrowserView()
                    .environmentObject(browser)
                    .modelContainer(container)
                    .tint(.teal)
                    .onOpenURL { url in
                        if let input = AddressResolver.deepLink(url) { browser.open(input) }
                    }
            } else {
                ContentUnavailableView("Lokaler Speicher nicht verfügbar", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("\(storageError ?? "Unbekannter Fehler"). Deine Daten wurden nicht gelöscht. Starte die App erneut."))
            }
        }
    }
}

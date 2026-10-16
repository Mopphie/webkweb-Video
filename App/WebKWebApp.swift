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
        var localContainer: ModelContainer?
        var failure: String?
        do { localContainer = try ModelContainer(for: SavedPage.self, configurations: ModelConfiguration(cloudKitDatabase: .none)) }
        catch { failure = error.localizedDescription }
        container = localContainer; storageError = failure
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                BrowserView()
                    .environmentObject(browser)
                    .environmentObject(browser.library)
                    .environmentObject(browser.nativePlayer)
                    .preferredColorScheme(browser.options.appearance == .system ? nil : browser.options.appearance == .dark ? .dark : .light)
                    .modelContainer(container)
                    .tint(.teal)
                    .onOpenURL { url in
                        guard !browser.privacyLocked else { return }
                        if url.scheme == "devntube", url.host == "home" { browser.addTab() }
                        else if let input = AddressResolver.deepLink(url) { browser.open(input) }
                    }
            } else {
                ContentUnavailableView("Lokaler Speicher nicht verfügbar", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("\(storageError ?? "Unbekannter Fehler"). Deine Daten wurden nicht gelöscht. Starte die App erneut."))
            }
        }
    }
}

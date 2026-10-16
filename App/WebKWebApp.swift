import SwiftUI
import SwiftData
import AVFoundation

@main
@MainActor
struct WebKWebApp: App {
    @StateObject private var browser = BrowserModel()
    private let container: ModelContainer?
    private let storageError: String?
    private let cloudWarning: String?

    init() {
        let options = PreferencesStorage.load()
        let cloud: ModelConfiguration.CloudKitDatabase = options.cloudSync ? ReleaseConfiguration.cloudContainer.map { .private($0) } ?? .none : .none
        var warning = options.cloudSync && ReleaseConfiguration.cloudContainer == nil ? "iCloud ist nicht provisioniert; lokaler Speicher wird verwendet." : nil
        var localContainer: ModelContainer?
        var failure: String?
        do { localContainer = try ModelContainer(for: SavedPage.self, configurations: ModelConfiguration(cloudKitDatabase: cloud)) }
        catch {
            if options.cloudSync {
                do {
                    localContainer = try ModelContainer(for: SavedPage.self, configurations: ModelConfiguration(cloudKitDatabase: .none))
                    warning = "iCloud konnte nicht gestartet werden; lokaler Speicher bleibt verfügbar. \(error.localizedDescription)"
                } catch { failure = error.localizedDescription }
            } else { failure = error.localizedDescription }
        }
        container = localContainer; storageError = failure; cloudWarning = warning
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                BrowserView()
                    .environmentObject(browser)
                    .modelContainer(container)
                    .tint(.teal)
                    .task { if let cloudWarning { browser.notice = cloudWarning } }
                    .onOpenURL { url in
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

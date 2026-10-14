import WidgetKit
import SwiftUI
import AppIntents

struct FavoritesEntry: TimelineEntry { let date: Date; let favorites: [FavoriteSnapshot] }
struct FavoritesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FavoritesEntry {
        FavoritesEntry(date: .now, favorites: [FavoriteSnapshot(id: "sample", title: "Deine Lieblingsseite", address: "https://example.com")])
    }
    private func entry(_ configuration: FavoriteWidgetConfiguration) -> FavoritesEntry {
        let all = FavoriteStorage.read()
        let selected = [configuration.first, configuration.second, configuration.third, configuration.fourth].compactMap { $0?.id }
        var seen = Set<String>()
        let favorites = selected.isEmpty ? all : selected.compactMap { id in all.first { $0.id == id } }.filter { seen.insert($0.id).inserted }
        return FavoritesEntry(date: .now, favorites: favorites)
    }
    func snapshot(for configuration: FavoriteWidgetConfiguration, in context: Context) async -> FavoritesEntry { context.isPreview ? placeholder(in: context) : entry(configuration) }
    func timeline(for configuration: FavoriteWidgetConfiguration, in context: Context) async -> Timeline<FavoritesEntry> {
        Timeline(entries: [entry(configuration)], policy: .after(Date().addingTimeInterval(1800)))
    }
}
struct FavoritesWidgetView: View {
    let entry: FavoritesEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("DevnTube", systemImage: "play.rectangle.fill").font(.headline).foregroundStyle(.teal)
            if entry.favorites.isEmpty {
                Text("Favoriten in der App speichern oder Widget bearbeiten.").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Link("Browser öffnen", destination: URL(string: "devntube://home")!).font(.caption.bold())
            } else {
                ForEach(Array(entry.favorites.prefix(family == .systemSmall ? 2 : 4))) { favorite in
                    if let link = favorite.deepLink {
                        Link(destination: link) {
                            HStack { Image(systemName: "star.fill").font(.caption).foregroundStyle(.teal); Text(favorite.title).font(.subheadline).lineLimit(1) }
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }.containerBackground(for: .widget) { Color(.systemBackground) }.privacySensitive()
    }
}
@main
struct WebKWebFavoritesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WebKWebFavorites", intent: FavoriteWidgetConfiguration.self, provider: FavoritesProvider()) { FavoritesWidgetView(entry: $0) }
            .configurationDisplayName("DevnTube-Favoriten").description("Wähle Favoriten oder nutze die Bibliotheksreihenfolge.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

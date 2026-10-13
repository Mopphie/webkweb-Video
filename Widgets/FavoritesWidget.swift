import WidgetKit
import SwiftUI

struct FavoritesEntry: TimelineEntry {
    let date: Date
    let favorites: [FavoriteSnapshot]
}

struct FavoritesProvider: TimelineProvider {
    func placeholder(in context: Context) -> FavoritesEntry {
        FavoritesEntry(date: .now, favorites: [FavoriteSnapshot(id: "sample", title: "Deine Lieblingsseite", address: "https://example.com")])
    }
    func getSnapshot(in context: Context, completion: @escaping (FavoritesEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : FavoritesEntry(date: .now, favorites: FavoriteStorage.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FavoritesEntry>) -> Void) {
        completion(Timeline(entries: [FavoritesEntry(date: .now, favorites: FavoriteStorage.read())], policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct FavoritesWidgetView: View {
    let entry: FavoritesEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("WebKWeb", systemImage: "play.rectangle.fill").font(.headline).foregroundStyle(.teal)
            if entry.favorites.isEmpty {
                Text("Speichere Favoriten in der App.").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Link("Browser öffnen", destination: URL(string: "webkweb://open?url=https%3A%2F%2Fm.youtube.com")!)
                    .font(.caption.bold())
            } else {
                ForEach(Array(entry.favorites.prefix(family == .systemSmall ? 2 : 4))) { favorite in
                    if let link = favorite.deepLink {
                        Link(destination: link) {
                            HStack {
                                Image(systemName: "star.fill").font(.caption).foregroundStyle(.teal)
                                Text(favorite.title).font(.subheadline).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .privacySensitive()
    }
}

@main
struct WebKWebFavoritesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WebKWebFavorites", provider: FavoritesProvider()) { FavoritesWidgetView(entry: $0) }
            .configurationDisplayName("WebKWeb-Favoriten")
            .description("Öffne deine gespeicherten Seiten direkt im Video-Browser.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

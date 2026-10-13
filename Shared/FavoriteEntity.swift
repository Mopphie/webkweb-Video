import AppIntents
import Foundation

struct FavoriteEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Favorit"
    static var defaultQuery = FavoriteQuery()
    let id: String
    let title: String
    let address: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    init(_ favorite: FavoriteSnapshot) {
        id = favorite.id
        title = favorite.title
        address = favorite.address
    }
}

struct FavoriteQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FavoriteEntity] {
        FavoriteStorage.read().filter { identifiers.contains($0.id) }.map(FavoriteEntity.init)
    }
    func suggestedEntities() async throws -> [FavoriteEntity] { FavoriteStorage.read().map(FavoriteEntity.init) }
}


struct FavoriteWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Favoriten auswählen"
    static var description = IntentDescription("Wähle bis zu vier Favoriten. Leere Auswahl nutzt die Bibliotheksreihenfolge.")
    @Parameter(title: "Erster Favorit") var first: FavoriteEntity?
    @Parameter(title: "Zweiter Favorit") var second: FavoriteEntity?
    @Parameter(title: "Dritter Favorit") var third: FavoriteEntity?
    @Parameter(title: "Vierter Favorit") var fourth: FavoriteEntity?
}

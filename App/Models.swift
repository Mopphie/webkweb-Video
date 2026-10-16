import Foundation
import SwiftData

@Model
final class SavedPage {
    var identifier: String = ""
    var title: String = ""
    var address: String = ""
    var visitedAt: Date = Date.now
    var favorite: Bool = false
    var favoriteOrder: Double = 0
    var customTitle: Bool = false
    var isHistory: Bool = true

    init(title: String, address: String, favorite: Bool = false) {
        identifier = UUID().uuidString
        self.title = title
        self.address = address
        self.favorite = favorite
        isHistory = !favorite
        visitedAt = favorite ? .distantPast : .now
    }
}

import Foundation
import SwiftData

@Model
final class StoredShow {
    @Attribute(.unique) var id: Int
    var titel: String
    var untertitel: String
    var lastUpdated: Date
    
    init(from show: Show) {
        self.id = show.id
        self.titel = show.titel
        self.untertitel = show.untertitel
        self.lastUpdated = Date()
    }
    
    func toShow() -> Show {
        return Show(id: id, titel: titel, untertitel: untertitel)
    }
}

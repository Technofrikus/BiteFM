import Foundation
import SwiftData

@Model
final class StoredListeningHistoryEntry {
    @Attribute(.unique) var showID: Int
    var dateString: String
    var addedAt: Date
    
    init(showID: Int, dateString: String) {
        self.showID = showID
        self.dateString = dateString
        self.addedAt = Date()
    }
}

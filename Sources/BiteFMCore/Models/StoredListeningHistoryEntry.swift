import Foundation
import SwiftData

@Model
final class StoredListeningHistoryEntry {
    @Attribute(.unique) var showID: Int
    var dateString: String
    var addedAt: Date
    /// Local plays are visible immediately and remain pending until the server history confirms them.
    var pendingSync: Bool = false
    /// Route metadata required to replay ByteFM's "mark as listened" request after an offline play.
    var syncShowSlug: String?
    var syncDateSegment: String?
    var syncTerminSlug: String?
    
    init(showID: Int, dateString: String) {
        self.showID = showID
        self.dateString = dateString
        self.addedAt = Date()
    }
}

enum ListeningHistoryStateLogic {
    static func visibleShowIDs(serverIDs: Set<Int>, pendingIDs: Set<Int>) -> Set<Int> {
        serverIDs.union(pendingIDs)
    }

    static func shouldDeleteLocalEntry(showID: Int, pendingSync: Bool, serverIDs: Set<Int>) -> Bool {
        !pendingSync && !serverIDs.contains(showID)
    }
}

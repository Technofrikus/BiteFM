import Foundation
import SwiftData

@Model
final class StoredPlaybackPosition {
    @Attribute(.unique) var terminID: Int
    var position: Double
    var lastPlayed: Date
    
    init(terminID: Int, position: Double) {
        self.terminID = terminID
        self.position = position
        self.lastPlayed = Date()
    }
}

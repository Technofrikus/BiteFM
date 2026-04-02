/*
  StoredFavoriteShow.swift
  BiteFM

  Persists favorite episode (show) IDs from get_favorites for offline checks.
*/

import Foundation
import SwiftData

@Model
final class StoredFavoriteShow {
    @Attribute(.unique) var showID: Int
    var createdAt: Date = Date()
    
    init(showID: Int, createdAt: Date = Date()) {
        self.showID = showID
        self.createdAt = createdAt
    }
}

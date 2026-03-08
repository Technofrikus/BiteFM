/*
  StoredFavoriteBroadcast.swift
  ByteFM

  Created by AI Coding Assistant on 2026-03-07.
*/

import Foundation
import SwiftData

@Model
final class StoredFavoriteBroadcast {
    @Attribute(.unique) var sendungSlug: String
    var sendungTitel: String
    var createdAt: Date = Date()
    
    init(from item: FavoriteBroadcast) {
        self.sendungSlug = item.sendungSlug
        self.sendungTitel = item.sendungTitel
        self.createdAt = Date()
    }
    
    init(sendungSlug: String, sendungTitel: String) {
        self.sendungSlug = sendungSlug
        self.sendungTitel = sendungTitel
        self.createdAt = Date()
    }
    
    func toFavoriteBroadcast() -> FavoriteBroadcast {
        return FavoriteBroadcast(
            sendungTitel: sendungTitel,
            sendungSlug: sendungSlug
        )
    }
}

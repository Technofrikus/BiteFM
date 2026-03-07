/*
  FavoriteBroadcast.swift
  ByteFM

  Created by AI Coding Assistant on 2026-03-07.
*/

import Foundation

// The top-level response structure
struct FavoritesResponse: Codable {
    let shows: [FavoriteShowItem]
    let tracks: [FavoriteTrackItem]
    let broadcasts: [FavoriteBroadcastItem]
}

// Item in the "broadcasts" array
struct FavoriteBroadcastItem: Codable {
    let id: Int
    let broadcast: BroadcastInfo
}

// Item in the "shows" array (specific episodes)
struct FavoriteShowItem: Codable {
    let id: Int
    let show: ShowInfo
    let broadcast: BroadcastInfo
}

// Item in the "tracks" array
struct FavoriteTrackItem: Codable {
    let id: Int
    let title: String
    let broadcast: BroadcastInfo?
    let show: ShowInfo?
    
    enum CodingKeys: String, CodingKey {
        case id, title, broadcast, show
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        
        // Handle broadcast being either BroadcastInfo object or false (bool)
        if let broadcastInfo = try? container.decode(BroadcastInfo.self, forKey: .broadcast) {
            broadcast = broadcastInfo
        } else {
            broadcast = nil
        }
        
        // Handle show being either ShowInfo object or false (bool)
        if let showInfo = try? container.decode(ShowInfo.self, forKey: .show) {
            show = showInfo
        } else {
            show = nil
        }
    }
}

// Shared broadcast info
struct BroadcastInfo: Codable {
    let id: Int
    let slug: String
    let title: String
}

// Shared show/episode info
struct ShowInfo: Codable {
    let id: Int
    let slug: String
    let date: String
    let subtitle: String
    let is_playable: Bool?
}

// Keeping this for compatibility with existing sync logic, 
// but it will represent the extracted broadcast info
struct FavoriteBroadcast: Codable, Identifiable {
    var id: String { sendungSlug }
    let sendungTitel: String
    let sendungSlug: String
}

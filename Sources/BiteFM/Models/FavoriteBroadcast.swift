/*
  FavoriteBroadcast.swift
  BiteFM

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
    /// When the user favorited this episode (API key varies; may be nil).
    let favoritedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id, show, broadcast
        case favoritedAt = "favorited_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case favoriteDate = "favorite_date"
        case dateAdded = "date_added"
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        show = try c.decode(ShowInfo.self, forKey: .show)
        broadcast = try c.decode(BroadcastInfo.self, forKey: .broadcast)
        favoritedAt = Self.decodeFavoritedAt(from: c)
    }
    
    private static func decodeFavoritedAt(from c: KeyedDecodingContainer<CodingKeys>) -> Date? {
        let keys: [CodingKeys] = [.favoritedAt, .createdAt, .updatedAt, .favoriteDate, .dateAdded]
        for key in keys {
            if let d = try? c.decodeIfPresent(Date.self, forKey: key) { return d }
            if let s = try? c.decodeIfPresent(String.self, forKey: key) {
                if let d = ISO8601DateFormatter().date(from: s) { return d }
                if let d = Self.germanOrISOPlainDate(s) { return d }
            }
        }
        return nil
    }
    
    /// Parses `yyyy-MM-dd` as UTC noon so sorting is stable.
    private static func germanOrISOPlainDate(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = t.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        comps.year = y
        comps.month = m
        comps.day = d
        comps.hour = 12
        return comps.date
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(show, forKey: .show)
        try c.encode(broadcast, forKey: .broadcast)
        try c.encodeIfPresent(favoritedAt, forKey: .favoritedAt)
    }
}

// Item in the "tracks" array
struct FavoriteTrackItem: Codable {
    let id: Int
    let title: String
    let broadcast: BroadcastInfo?
    let show: ShowInfo?
    /// Start position in seconds within the episode (API may use `time`, `position`, `offset`, …).
    let startOffsetSeconds: Double
    
    enum CodingKeys: String, CodingKey {
        case id, title, broadcast, show
        case time, position, offset, start
        case startOffset = "start_offset"
        case startTime = "start_time"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        
        if let broadcastInfo = try? container.decode(BroadcastInfo.self, forKey: .broadcast) {
            broadcast = broadcastInfo
        } else {
            broadcast = nil
        }
        
        if let showInfo = try? container.decode(ShowInfo.self, forKey: .show) {
            show = showInfo
        } else {
            show = nil
        }
        
        startOffsetSeconds = Self.decodeStartOffset(from: container)
    }
    
    private static func decodeStartOffset(from c: KeyedDecodingContainer<CodingKeys>) -> Double {
        if let t = try? c.decodeIfPresent(Int.self, forKey: .time) { return Double(t) }
        if let t = try? c.decodeIfPresent(Double.self, forKey: .time) { return t }
        if let t = try? c.decodeIfPresent(Double.self, forKey: .position) { return t }
        if let t = try? c.decodeIfPresent(Int.self, forKey: .position) { return Double(t) }
        if let t = try? c.decodeIfPresent(Double.self, forKey: .offset) { return t }
        if let t = try? c.decodeIfPresent(Int.self, forKey: .offset) { return Double(t) }
        if let t = try? c.decodeIfPresent(Double.self, forKey: .start) { return t }
        if let t = try? c.decodeIfPresent(Int.self, forKey: .start) { return Double(t) }
        if let t = try? c.decodeIfPresent(Double.self, forKey: .startOffset) { return t }
        if let t = try? c.decodeIfPresent(Int.self, forKey: .startOffset) { return Double(t) }
        if let t = try? c.decodeIfPresent(Double.self, forKey: .startTime) { return t }
        if let t = try? c.decodeIfPresent(Int.self, forKey: .startTime) { return Double(t) }
        return 0
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(broadcast, forKey: .broadcast)
        try c.encodeIfPresent(show, forKey: .show)
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

// MARK: - AJAX change-favorite response

struct ChangeFavoriteResponse: Codable {
    let error: Int
    let status: String
    let value: Bool
    let id: Int?
    let broadcast: BroadcastInfo?
    let show: ShowInfo?
}

// MARK: - Pure favorite checks (for tests and APIClient)

enum FavoriteStateLogic {
    static func isFavoriteBroadcast(slug: String, title: String, favoriteSlugs: Set<String>) -> Bool {
        let lSlug = slug.lowercased()
        return favoriteSlugs.contains(lSlug) || favoriteSlugs.contains(title)
    }
    
    static func isEpisodeFavorite(terminID: Int, terminSlug: String, favoriteShowIDs: Set<Int>, favoriteSlugs: Set<String>) -> Bool {
        favoriteShowIDs.contains(terminID) || favoriteSlugs.contains(terminSlug.lowercased())
    }
    
    static func isFavoriteArchiveItem(
        sendungSlug: String,
        terminSlug: String,
        sendungTitel: String,
        terminID: Int,
        favoriteSlugs: Set<String>,
        favoriteShowIDs: Set<Int>
    ) -> Bool {
        isFavoriteBroadcast(slug: sendungSlug, title: sendungTitel, favoriteSlugs: favoriteSlugs)
            || isFavoriteBroadcast(slug: terminSlug, title: "", favoriteSlugs: favoriteSlugs)
            || isEpisodeFavorite(terminID: terminID, terminSlug: terminSlug, favoriteShowIDs: favoriteShowIDs, favoriteSlugs: favoriteSlugs)
    }
}

// MARK: - FavoriteShowItem → ArchiveItem (playback / rows)

extension FavoriteTrackItem {
    /// Builds an `ArchiveItem` for playback when episode metadata is present.
    func toArchiveItem() -> ArchiveItem? {
        guard let show, let broadcast else { return nil }
        let isoDate = show.date.trimmingCharacters(in: .whitespacesAndNewlines)
        let datumDe = FavoriteShowItem.formatDatumDe(fromISODate: isoDate)
        return ArchiveItem(
            audioFile1: "",
            audioFile2: "",
            audioFile3: "",
            sendungTitel: broadcast.title,
            untertitelSendung: "",
            terminID: show.id,
            terminSlug: show.slug,
            sendungSlug: broadcast.slug,
            sendungID: broadcast.id,
            datum: isoDate,
            datumDe: datumDe,
            startTime: "",
            endTime: "",
            untertitelTermin: show.subtitle
        )
    }
}

extension FavoriteShowItem {
    /// Parsed `show.date` (`yyyy-MM-dd`) for sorting; falls back to distant past if invalid.
    var episodeBroadcastDateForSort: Date {
        let iso = show.date.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else {
            return .distantPast
        }
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        comps.year = y
        comps.month = m
        comps.day = d
        return comps.date ?? .distantPast
    }
    
    func toArchiveItem() -> ArchiveItem {
        let isoDate = show.date.trimmingCharacters(in: .whitespacesAndNewlines)
        let datumDe = FavoriteShowItem.formatDatumDe(fromISODate: isoDate)
        return ArchiveItem(
            audioFile1: "",
            audioFile2: "",
            audioFile3: "",
            sendungTitel: broadcast.title,
            untertitelSendung: "",
            terminID: show.id,
            terminSlug: show.slug,
            sendungSlug: broadcast.slug,
            sendungID: broadcast.id,
            datum: isoDate,
            datumDe: datumDe,
            startTime: "",
            endTime: "",
            untertitelTermin: show.subtitle
        )
    }
    
    fileprivate static func formatDatumDe(fromISODate iso: String) -> String {
        let parts = iso.split(separator: "-")
        if parts.count == 3,
           let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) {
            return String(format: "%02d.%02d.%04d", d, m, y)
        }
        return iso
    }
}

import Foundation

public struct BroadcastDetail: Codable {
    public let id: Int
    public let broadcastTitle: String
    public let showSubtitle: String
    public let showTime: String
    public let showDate: String
    public let moderator: String
    public let moderatorImage: String?
    public let showDescription: String
    public let recordings: [Recording]
    
    enum CodingKeys: String, CodingKey {
        case id
        case broadcastTitle = "broadcast_title"
        case showSubtitle = "show_subtitle"
        case showTime = "show_time"
        case showDate = "show_date"
        case moderator
        case moderatorImage = "moderator_image"
        case showDescription = "show_description"
        case recordings
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try Self.decodeIntLenient(c, forKey: .id)
        broadcastTitle = try c.decodeIfPresent(String.self, forKey: .broadcastTitle) ?? ""
        showSubtitle = try c.decodeIfPresent(String.self, forKey: .showSubtitle) ?? ""
        showTime = try c.decodeIfPresent(String.self, forKey: .showTime) ?? ""
        showDate = try c.decodeIfPresent(String.self, forKey: .showDate) ?? ""
        moderator = try c.decodeIfPresent(String.self, forKey: .moderator) ?? ""
        moderatorImage = try c.decodeIfPresent(String.self, forKey: .moderatorImage)
        showDescription = try c.decodeIfPresent(String.self, forKey: .showDescription) ?? ""
        recordings = try c.decodeIfPresent([Recording].self, forKey: .recordings) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(broadcastTitle, forKey: .broadcastTitle)
        try c.encode(showSubtitle, forKey: .showSubtitle)
        try c.encode(showTime, forKey: .showTime)
        try c.encode(showDate, forKey: .showDate)
        try c.encode(moderator, forKey: .moderator)
        try c.encodeIfPresent(moderatorImage, forKey: .moderatorImage)
        try c.encode(showDescription, forKey: .showDescription)
        try c.encode(recordings, forKey: .recordings)
    }
    
    private static func decodeIntLenient(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Int {
        if let v = try? c.decode(Int.self, forKey: key) { return v }
        if let s = try? c.decode(String.self, forKey: key), let v = Int(s) { return v }
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Expected Int or String for \(key)")
    }
}

public struct Recording: Codable {
    public let recordingUrl: String
    public let playlist: [PlaylistItem]
    
    enum CodingKeys: String, CodingKey {
        case recordingUrl = "recording_url"
        case playlist
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recordingUrl = try c.decodeIfPresent(String.self, forKey: .recordingUrl) ?? ""
        playlist = try c.decodeIfPresent([PlaylistItem].self, forKey: .playlist) ?? []
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(recordingUrl, forKey: .recordingUrl)
        try c.encode(playlist, forKey: .playlist)
    }
}

public struct PlaylistItem: Codable, Identifiable {
    public var id: String { "\(artist)-\(title)-\(time)" }
    public let artist: String
    public let title: String
    public let time: Int

    enum CodingKeys: String, CodingKey {
        case artist
        case title
        case time
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        if let t = try? c.decode(Int.self, forKey: .time) {
            time = t
        } else if let d = try? c.decode(Double.self, forKey: .time) {
            time = Int(d.rounded())
        } else if let s = try? c.decode(String.self, forKey: .time), let v = Int(s) {
            time = v
        } else {
            time = 0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(artist, forKey: .artist)
        try c.encode(title, forKey: .title)
        try c.encode(time, forKey: .time)
    }
    
    var timeString: String {
        let minutes = time / 60
        let seconds = time % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension BroadcastDetail {
    /// Best-effort start offset in seconds by matching the favorited track title to the episode playlist.
    func startSeconds(matchingFavoriteTrackTitle favoriteTitle: String) -> Int? {
        let want = Self.normalizeTitle(favoriteTitle)
        guard !want.isEmpty else { return nil }
        var bestScore = 0
        var bestTime: Int?
        for rec in recordings {
            for pl in rec.playlist {
                let t = Self.normalizeTitle(pl.title)
                let combinedDash = Self.normalizeTitle("\(pl.artist) - \(pl.title)")
                let combinedSpace = Self.normalizeTitle("\(pl.artist) \(pl.title)")
                let score: Int
                if t == want {
                    score = 100
                } else if combinedDash == want || combinedSpace == want {
                    score = 95
                } else if t.count >= 3, want.contains(t) {
                    score = 85
                } else if want.count >= 3, t.contains(want) {
                    score = 82
                } else if combinedDash.contains(want) || combinedSpace.contains(want) {
                    score = 75
                } else {
                    score = 0
                }
                if score > bestScore {
                    bestScore = score
                    bestTime = pl.time
                }
            }
        }
        return bestTime
    }
    
    private static func normalizeTitle(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

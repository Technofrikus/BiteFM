import Foundation

enum StreamType: String, Codable, CaseIterable, Identifiable {
    case nurmusik = "nurmusik"
    case hh = "hh"
    case web = "web"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .nurmusik: return "Nur Musik"
        case .hh: return "Hamburg"
        case .web: return "Web"
        }
    }
    
    var streamURL: URL? {
        switch self {
        case .nurmusik:
            return URL(string: "https://uplink.byte.fm/bytefm-nurmusikhq/mp3-192/?ar-distributor=ffa0")
        case .hh:
            return URL(string: "https://www.byte.fm/live/hh-mp3-192/HQ?ar-distributor=ffa7")
        case .web:
            return URL(string: "https://uplink.byte.fm/bytefm-mainhq/mp3-192/?ar-distributor=ffa7")
        }
    }
}

struct LiveMetadataResponse: Codable {
    let tracks: [String: [String]]
    let artistImageURL: [String: String]
    let currentShowTitle: [String: String]
    let currentShowSubtitle: [String: String]
    let currentShowTime: [String: String]
    
    enum CodingKeys: String, CodingKey {
        case tracks
        case artistImageURL = "artistImageURL"
        case currentShowTitle = "current_show_title"
        case currentShowSubtitle = "current_show_subtitle"
        case currentShowTime = "current_show_time"
    }
}

struct LiveMetadata {
    let type: StreamType
    let currentTrack: String?
    let recentTracks: [String]
    let artistImageURL: URL?
    let showTitle: String
    let showSubtitle: String
    let showTime: String
    
    init(from response: LiveMetadataResponse, for type: StreamType) {
        self.type = type
        let key = type.rawValue
        
        let trackList = response.tracks[key] ?? []
        self.currentTrack = trackList.first
        self.recentTracks = Array(trackList.dropFirst())
        
        if let imageString = response.artistImageURL[key], !imageString.isEmpty {
            self.artistImageURL = URL(string: imageString)
        } else {
            self.artistImageURL = nil
        }
        
        self.showTitle = response.currentShowTitle[key] ?? ""
        self.showSubtitle = response.currentShowSubtitle[key] ?? ""
        self.showTime = response.currentShowTime[key] ?? ""
    }
}

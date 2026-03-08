import Foundation

struct BroadcastDetail: Codable {
    let id: Int
    let broadcastTitle: String
    let showSubtitle: String
    let showTime: String
    let showDate: String
    let moderator: String
    let moderatorImage: String?
    let showDescription: String
    let recordings: [Recording]
    
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
}

struct Recording: Codable {
    let recordingUrl: String
    let playlist: [PlaylistItem]
    
    enum CodingKeys: String, CodingKey {
        case recordingUrl = "recording_url"
        case playlist
    }
}

struct PlaylistItem: Codable, Identifiable {
    var id: String { "\(artist)-\(title)-\(time)" }
    let artist: String
    let title: String
    let time: Int
    
    var timeString: String {
        let minutes = time / 60
        let seconds = time % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

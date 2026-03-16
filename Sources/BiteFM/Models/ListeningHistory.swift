import Foundation

struct ListeningHistoryResponse: Codable {
    let error: Int
    let data: [ListeningHistoryEntry]
}

struct ListeningHistoryEntry: Codable {
    let showID: Int
    let date: String
    
    enum CodingKeys: String, CodingKey {
        case showID = "show_id"
        case date
    }
}

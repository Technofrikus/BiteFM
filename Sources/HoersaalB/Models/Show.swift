import Foundation

struct Show: Codable, Identifiable {
    let id: Int
    let titel: String
    let untertitel: String
    
    enum CodingKeys: String, CodingKey {
        case id = "id_sendung"
        case titel
        case untertitel
    }
    
    var slug: String {
        let base = titel.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "ä", with: "ae")
            .replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue")
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
        
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let filtered = base.unicodeScalars.filter { allowed.contains($0) }
        var result = String(String.UnicodeScalarView(filtered))
        
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        
        if result.hasSuffix("-") {
            result.removeLast()
        }
        if result.hasPrefix("-") {
            result.removeFirst()
        }
        
        return result
    }
}

struct PaginatedBroadcasts: Codable {
    let results: [BroadcastSummary]
    let pageNum: Int
    let pageSize: Int
    let pageCount: Int
}

struct BroadcastSummary: Codable, Identifiable {
    let id: Int
    let subtitle: String
    let description: String?
    let slug: String
    let date: String
    let image: String?
    let moderator: String?
    let isPlayable: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case subtitle
        case description
        case slug
        case date
        case image
        case moderator
        case isPlayable = "is_playable"
    }
    
    // Convert to ArchiveItem for reuse in existing views/player
    func toArchiveItem(showTitle: String, showSlug: String) -> ArchiveItem {
        return ArchiveItem(
            audioFile1: "", // Will be filled from detail if needed, or we need another way
            audioFile2: "",
            audioFile3: "",
            sendungTitel: showTitle,
            untertitelSendung: "",
            terminID: id,
            terminSlug: slug,
            sendungSlug: showSlug,
            datum: "", // We only have date as "06.08.2025"
            datumDe: date,
            startTime: "",
            endTime: "",
            untertitelTermin: subtitle
        )
    }
}

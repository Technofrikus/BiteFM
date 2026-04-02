import Foundation

struct Show: Codable, Identifiable, Hashable {
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
    func toArchiveItem(showTitle: String, showSlug: String, sendungID: Int? = nil) -> ArchiveItem {
        let rawDate = date.trimmingCharacters(in: .whitespacesAndNewlines)
        let isoDatum: String
        if rawDate.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            isoDatum = rawDate
        } else {
            let parts = rawDate.split(separator: ".")
            if parts.count == 3,
               let d = Int(parts[0]), let m = Int(parts[1]), let y = Int(parts[2]) {
                isoDatum = String(format: "%04d-%02d-%02d", y, m, d)
            } else {
                isoDatum = ""
            }
        }
        return ArchiveItem(
            audioFile1: "", // Will be filled from detail if needed, or we need another way
            audioFile2: "",
            audioFile3: "",
            sendungTitel: showTitle,
            untertitelSendung: "",
            terminID: id,
            terminSlug: slug,
            sendungSlug: showSlug,
            sendungID: sendungID,
            datum: isoDatum,
            datumDe: date,
            startTime: "",
            endTime: "",
            untertitelTermin: subtitle
        )
    }
}

import Foundation

struct ArchiveItem: Codable, Identifiable {
    var id: Int { terminID }
    
    let audioFile1: String
    let audioFile2: String
    let audioFile3: String
    let sendungTitel: String
    let untertitelSendung: String
    let terminID: Int
    let terminSlug: String
    let sendungSlug: String
    /// Sendungs-ID (`id_sendung`) — gleiche ID wie in der Sendungsliste; für die REST-URL wird der Slug der Sendung benötigt (z. B. `bytefm-mixtape`).
    let sendungID: Int?
    let datum: String
    let datumDe: String
    let startTime: String
    let endTime: String
    let untertitelTermin: String
    
    enum CodingKeys: String, CodingKey {
        case audioFile1 = "audio_file_1"
        case audioFile2 = "audio_file_2"
        case audioFile3 = "audio_file_3"
        case sendungTitel
        case untertitelSendung = "untertitel_sendung"
        case terminID
        case terminSlug
        case sendungSlug
        case sendungID = "id_sendung"
        case datum
        case datumDe = "datum_de"
        case startTime
        case endTime
        case untertitelTermin = "untertitel_termin"
    }
    
    var subtitle: String {
        if !untertitelTermin.isEmpty {
            return untertitelTermin
        }
        return untertitelSendung
    }
    
    /// Termin-Slug wie in der REST-API (ASCII-Bindestriche; typografische Striche aus `termin_slug` ersetzen).
    var terminSlugForBroadcastAPI: String {
        terminSlug
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2212}", with: "-")
    }
}

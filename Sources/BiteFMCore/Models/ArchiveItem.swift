import Foundation

public struct ArchiveItem: Codable, Identifiable {
    public var id: Int { terminID }

    public let audioFile1: String
    public let audioFile2: String
    public let audioFile3: String
    public let sendungTitel: String
    public let untertitelSendung: String
    public let terminID: Int
    public let terminSlug: String
    public let sendungSlug: String
    /// Sendungs-ID (`id_sendung`) — gleiche ID wie in der Sendungsliste; für die REST-URL wird der Slug der Sendung benötigt (z. B. `bytefm-mixtape`).
    public let sendungID: Int?
    public let datum: String
    public let datumDe: String
    public let startTime: String
    public let endTime: String
    public let untertitelTermin: String

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
    
    public var subtitle: String {
        if !untertitelTermin.isEmpty {
            return untertitelTermin
        }
        return untertitelSendung
    }
    
    /// Termin-Slug wie in der REST-API (ASCII-Bindestriche; typografische Striche aus `termin_slug` ersetzen).
    public var terminSlugForBroadcastAPI: String {
        terminSlug
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2212}", with: "-")
    }
}

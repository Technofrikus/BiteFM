import Foundation
import SwiftData

@Model
final class StoredArchiveItem {
    @Attribute(.unique) var terminID: Int
    var audioFile1: String
    var audioFile2: String
    var audioFile3: String
    var sendungTitel: String
    var untertitelSendung: String
    var terminSlug: String
    var sendungSlug: String
    var datum: String
    var datumDe: String
    var startTime: String
    var endTime: String
    var untertitelTermin: String
    var broadcastDate: Date
    var createdAt: Date = Date()
    
    init(from item: ArchiveItem) {
        self.terminID = item.terminID
        self.audioFile1 = item.audioFile1
        self.audioFile2 = item.audioFile2
        self.audioFile3 = item.audioFile3
        self.sendungTitel = item.sendungTitel
        self.untertitelSendung = item.untertitelSendung
        self.terminSlug = item.terminSlug
        self.sendungSlug = item.sendungSlug
        self.datum = item.datum
        self.datumDe = item.datumDe
        self.startTime = item.startTime
        self.endTime = item.endTime
        self.untertitelTermin = item.untertitelTermin
        self.createdAt = Date()
        
        // Parse datum (YYYY-MM-DD)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.broadcastDate = formatter.date(from: item.datum) ?? Date()
    }
    
    // Helper to convert back to ArchiveItem if needed
    func toArchiveItem() -> ArchiveItem {
        return ArchiveItem(
            audioFile1: audioFile1,
            audioFile2: audioFile2,
            audioFile3: audioFile3,
            sendungTitel: sendungTitel,
            untertitelSendung: untertitelSendung,
            terminID: terminID,
            terminSlug: terminSlug,
            sendungSlug: sendungSlug,
            datum: datum,
            datumDe: datumDe,
            startTime: startTime,
            endTime: endTime,
            untertitelTermin: untertitelTermin
        )
    }

    var subtitle: String {
        if !untertitelTermin.isEmpty {
            return untertitelTermin
        }
        return untertitelSendung
    }
}

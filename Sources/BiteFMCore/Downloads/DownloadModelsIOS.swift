#if os(iOS)
import Foundation
import SwiftData

// MARK: - Download status (persisted as String)

public enum EpisodeDownloadStatus: String, CaseIterable, Sendable {
    case queued
    case preparing
    case downloading
    case downloaded
    case failed
}

// MARK: - Paths

enum DownloadFilesDirectory {
    /// Subfolder under Application Support (same parent as SwiftData store).
    static let folderName = "Downloads"

    static func baseDirectory() throws -> URL {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw DownloadError.missingApplicationSupport
        }
        let bite = appSupport.appendingPathComponent("BiteFM", isDirectory: true)
        let downloads = bite.appendingPathComponent(folderName, isDirectory: true)
        if !fm.fileExists(atPath: downloads.path) {
            try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        }
        return downloads
    }

    /// Stable file name per episode (container binary is MPEG/MP3 — needs `.mp3` for `AVPlayer`).
    static func audioFileURL(terminID: Int) throws -> URL {
        try baseDirectory().appendingPathComponent("episode-\(terminID).mp3", isDirectory: false)
    }
}

enum DownloadError: LocalizedError {
    case missingApplicationSupport
    case noAudioURL
    case notEnoughFreeSpace
    case appDownloadBudgetExceeded
    case networkError(String)
    case fileSystemError(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingApplicationSupport:
            return "Speicherort für Downloads konnte nicht angelegt werden."
        case .noAudioURL:
            return "Für diese Ausgabe wurde keine Audiodatei gefunden."
        case .notEnoughFreeSpace:
            return "Nicht genug freier Speicher auf dem Gerät. Lösche andere Dateien oder ältere Downloads."
        case .appDownloadBudgetExceeded:
            return "Das Download-Speicherlimit der App ist erreicht."
        case .networkError(let s):
            return s
        case .fileSystemError(let s):
            return s
        case .saveFailed(let s):
            return s
        }
    }
}

// MARK: - SwiftData: downloaded episode row

@Model
final class StoredDownloadedEpisode {
    @Attribute(.unique) var terminID: Int

    /// Raw `EpisodeDownloadStatus.rawValue`
    var statusRaw: String
    /// 0...1 while downloading
    var progress: Double
    /// Relative to `DownloadFilesDirectory.baseDirectory()` file name only, e.g. `episode-123.mp3`
    var localFileName: String?
    /// Cached moderator portrait from `BroadcastDetail.moderatorImage` (e.g. `moderator-123.jpg`).
    var moderatorImageLocalFileName: String?
    var expectedSizeBytes: Int64
    var fileSizeBytes: Int64
    var errorMessage: String?

    var createdAt: Date
    var downloadedAt: Date?
    var lastPlayedAt: Date?

    // ArchiveItem mirror (offline list + playback metadata)
    var audioFile1: String
    var audioFile2: String
    var audioFile3: String
    var sendungTitel: String
    var untertitelSendung: String
    var terminSlug: String
    var sendungSlug: String
    var sendungID: Int?
    var datum: String
    var datumDe: String
    var startTime: String
    var endTime: String
    var untertitelTermin: String
    var broadcastDate: Date

    var status: EpisodeDownloadStatus {
        get { EpisodeDownloadStatus(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }

    init(
        item: ArchiveItem,
        status: EpisodeDownloadStatus = .queued,
        progress: Double = 0
    ) {
        self.terminID = item.terminID
        self.statusRaw = status.rawValue
        self.progress = progress
        self.localFileName = nil
        self.moderatorImageLocalFileName = nil
        self.expectedSizeBytes = 0
        self.fileSizeBytes = 0
        self.errorMessage = nil
        self.createdAt = Date()
        self.downloadedAt = nil
        self.lastPlayedAt = nil

        self.audioFile1 = item.audioFile1
        self.audioFile2 = item.audioFile2
        self.audioFile3 = item.audioFile3
        self.sendungTitel = item.sendungTitel
        self.untertitelSendung = item.untertitelSendung
        self.terminSlug = item.terminSlug
        self.sendungSlug = item.sendungSlug
        self.sendungID = item.sendungID
        self.datum = item.datum
        self.datumDe = item.datumDe
        self.startTime = item.startTime
        self.endTime = item.endTime
        self.untertitelTermin = item.untertitelTermin
        self.broadcastDate = Self.parseBroadcastDate(item.datum)
    }

    func applyArchiveMetadata(from item: ArchiveItem) {
        audioFile1 = item.audioFile1
        audioFile2 = item.audioFile2
        audioFile3 = item.audioFile3
        sendungTitel = item.sendungTitel
        untertitelSendung = item.untertitelSendung
        terminSlug = item.terminSlug
        sendungSlug = item.sendungSlug
        sendungID = item.sendungID
        datum = item.datum
        datumDe = item.datumDe
        startTime = item.startTime
        endTime = item.endTime
        untertitelTermin = item.untertitelTermin
        broadcastDate = Self.parseBroadcastDate(item.datum)
    }

    func toArchiveItem() -> ArchiveItem {
        ArchiveItem(
            audioFile1: audioFile1,
            audioFile2: audioFile2,
            audioFile3: audioFile3,
            sendungTitel: sendungTitel,
            untertitelSendung: untertitelSendung,
            terminID: terminID,
            terminSlug: terminSlug,
            sendungSlug: sendungSlug,
            sendungID: sendungID,
            datum: datum,
            datumDe: datumDe,
            startTime: startTime,
            endTime: endTime,
            untertitelTermin: untertitelTermin
        )
    }

    func resolvedLocalModeratorImageURL() -> URL? {
        guard let name = moderatorImageLocalFileName, !name.isEmpty else { return nil }
        guard let base = try? DownloadFilesDirectory.baseDirectory() else { return nil }
        let url = base.appendingPathComponent(name, isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Resolved local file URL if completed and file exists.
    func resolvedLocalAudioURL() -> URL? {
        guard status == .downloaded, let name = localFileName, !name.isEmpty else { return nil }
        guard let base = try? DownloadFilesDirectory.baseDirectory() else { return nil }
        let url = base.appendingPathComponent(name, isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func parseBroadcastDate(_ dateString: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: dateString) ?? Date()
    }
}

// MARK: - Offline broadcast detail JSON

@Model
final class StoredOfflineBroadcastDetail {
    @Attribute(.unique) var terminID: Int
    var jsonData: Data

    init(terminID: Int, jsonData: Data) {
        self.terminID = terminID
        self.jsonData = jsonData
    }

    func decodeDetail() throws -> BroadcastDetail {
        try JSONDecoder().decode(BroadcastDetail.self, from: jsonData)
    }

    static func upsert(terminID: Int, detail: BroadcastDetail, context: ModelContext) throws {
        let encoded = try JSONEncoder().encode(detail)
        let fd = FetchDescriptor<StoredOfflineBroadcastDetail>(
            predicate: #Predicate<StoredOfflineBroadcastDetail> { $0.terminID == terminID }
        )
        if let existing = try context.fetch(fd).first {
            existing.jsonData = encoded
        } else {
            context.insert(StoredOfflineBroadcastDetail(terminID: terminID, jsonData: encoded))
        }
    }
}

// MARK: - Settings (singleton row)

@Model
final class StoredDownloadSettings {
    /// Always 0 — single row.
    @Attribute(.unique) var singletonKey: Int

    /// Maximum bytes for downloaded audio files (not including SwiftData).
    var maxDownloadStorageBytes: Int64
    /// 0 = never auto-delete by age; 1...4 = delete downloads older than N weeks.
    var retentionWeeks: Int

    init() {
        self.singletonKey = 0
        self.maxDownloadStorageBytes = 500 * 1024 * 1024
        self.retentionWeeks = 0
    }

    static func fetchOrCreate(context: ModelContext) throws -> StoredDownloadSettings {
        let fd = FetchDescriptor<StoredDownloadSettings>(
            predicate: #Predicate<StoredDownloadSettings> { $0.singletonKey == 0 }
        )
        if let row = try context.fetch(fd).first {
            return row
        }
        let row = StoredDownloadSettings()
        context.insert(row)
        try context.save()
        return row
    }
}
#endif

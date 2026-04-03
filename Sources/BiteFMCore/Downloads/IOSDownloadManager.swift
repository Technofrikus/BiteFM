#if os(iOS)
import Foundation
import SwiftData
import SwiftUI

// MARK: - UI helpers (observed by rows)

public struct EpisodeDownloadUISnapshot: Equatable, Sendable {
    public var status: EpisodeDownloadStatus
    public var progress: Double
    /// Größe aus HTTP HEAD (oder 0); für Anzeige „~… MB“ vor Abschluss des Downloads.
    public var expectedSizeBytes: Int64

    public init(status: EpisodeDownloadStatus, progress: Double, expectedSizeBytes: Int64 = 0) {
        self.status = status
        self.progress = progress
        self.expectedSizeBytes = expectedSizeBytes
    }
}

/// iOS-only: background-friendly downloads, disk/budget checks, SwiftData sync.
@MainActor
public final class IOSDownloadManager: ObservableObject {
    public static let shared = IOSDownloadManager()

    public static let backgroundSessionIdentifier = "fm.byte.bitefm.downloads"

    /// Browser-like UA; many CDNs block custom mobile app strings for media.
    nonisolated private static let safariLikeDownloadUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    nonisolated private static let archivPathAllowed: CharacterSet = {
        var c = CharacterSet.urlPathAllowed
        c.remove(charactersIn: "/")
        return c
    }()

    private var modelContainer: ModelContainer?
    private var bridge: DownloadSessionBridge?
    private var urlSession: URLSession?

    /// In-memory task id → terminID (not persisted; progress is reloaded from DB on demand).
    private var taskToTerminID: [Int: Int] = [:]
    private var terminIDToTask: [Int: Int] = [:]
    /// Source URL for active tasks — used to pick a **correct file extension** (AVPlayer rejects `.bin` for MP3).
    private var taskToRemoteURL: [Int: URL] = [:]

    /// Fast path for SwiftUI lists.
    @Published private(set) public var snapshotByTerminID: [Int: EpisodeDownloadUISnapshot] = [:]

    /// Gleichzeitig laufende Downloads (Bandbreite); weitere bleiben `.queued`.
    private let maxConcurrentDownloads = 2
    /// Für App-Speicher-Budget, wenn `Content-Length` per HEAD nicht ermittelt werden kann (~Ausgaben 100–200 MB).
    private static let fallbackBudgetBytesPerEpisode: Int64 = 200 * 1024 * 1024

    /// One-shot alert flows (budget / device space).
    @Published public var budgetPrompt: DownloadBudgetPrompt?
    @Published public var deviceSpaceError: String?

    /// Last operation user message (optional).
    @Published public var lastErrorMessage: String?

    private var pendingRetry: (item: ArchiveItem, detail: BroadcastDetail?)?
    private var pendingExpectedBytes: Int64 = 0

    nonisolated(unsafe) private static var backgroundCompletionHandler: (() -> Void)?

    public func setBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
        Self.backgroundCompletionHandler = handler
    }

    private init() {}

    public func setup(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        if bridge == nil {
            let b = DownloadSessionBridge(manager: self)
            bridge = b
            // Background configuration so transfers continue after the app is suspended (not force-quit).
            // `UIApplicationDelegate.handleEventsForBackgroundURLSession` + `urlSessionDidFinishEvents`
            // complete the system handshake; `UIBackgroundModes` includes `fetch` (Info-iOS.plist).
            let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
            config.isDiscretionary = false
            config.sessionSendsLaunchEvents = true
            config.waitsForConnectivity = true
            config.allowsExpensiveNetworkAccess = true
            config.allowsConstrainedNetworkAccess = true
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 86_400
            config.httpCookieStorage = HTTPCookieStorage.shared
            config.httpCookieAcceptPolicy = .always
            config.httpShouldSetCookies = true
            config.httpAdditionalHeaders = [
                "User-Agent": Self.safariLikeDownloadUserAgent,
                "Accept": "*/*",
                "Accept-Language": "de-DE,de;q=0.9,en;q=0.8"
            ]
            let session = URLSession(configuration: config, delegate: b, delegateQueue: .main)
            urlSession = session
        }
        urlSession?.getAllTasks { tasks in
            Task { @MainActor in
                self.reconnectRunningTasks(activeTasks: tasks)
            }
        }
        Task { await refreshSnapshotFromStore() }
        Task { await applyRetentionIfNeeded() }
        Task { await reconcileOrphans() }
        Task { await migrateLegacyBinDownloadFilenamesIfNeeded() }
        Self.purgeOrphanStagedDownloadTempFilesOnLaunch()
    }

    /// Nach App-Start: Reste von abgestürzten Sessions (`bitefm-download-*.tmp`). Normalerweise räumt `downloadDidFinish` sofort auf.
    private static func purgeOrphanStagedDownloadTempFilesOnLaunch() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        guard let items = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        for url in items {
            let name = url.lastPathComponent
            guard name.hasPrefix("bitefm-download-"), url.pathExtension == "tmp" else { continue }
            try? fm.removeItem(at: url)
        }
    }

    /// Die vom Delegate nach `temporaryDirectory` verschobene Datei — ohne Löschen liegt sie **zusätzlich** zur Kopie unter Library nochmals vollständig im Temp (schnell mehrere GB).
    private static func removeStagedDownloadTempFileIfNeeded(at localURL: URL) {
        let fm = FileManager.default
        let norm = localURL.standardizedFileURL
        let path = norm.path
        let tmpRoot = fm.temporaryDirectory.standardizedFileURL.path
        guard path.hasPrefix(tmpRoot), norm.lastPathComponent.hasPrefix("bitefm-download-") else { return }
        guard fm.fileExists(atPath: path) else { return }
        try? fm.removeItem(at: norm)
    }

    private func reconnectRunningTasks(activeTasks: [URLSessionTask]) {
        let downloadTasks = activeTasks.compactMap { $0 as? URLSessionDownloadTask }
        for t in downloadTasks {
            if let desc = t.taskDescription, let terminID = Int(desc) {
                let ident = t.taskIdentifier
                taskToTerminID[ident] = terminID
                terminIDToTask[terminID] = ident
                if taskToRemoteURL[ident] == nil {
                    let u = t.originalRequest?.url ?? t.currentRequest?.url
                    if let u { taskToRemoteURL[ident] = u }
                }
            }
        }
        Task { await refreshSnapshotFromStore() }
    }

    // MARK: - Public API

    public func uiSnapshot(for terminID: Int) -> EpisodeDownloadUISnapshot? {
        snapshotByTerminID[terminID]
    }

    /// Start or resume conceptual download: fetches detail if needed, stores offline JSON, downloads audio.
    public func startDownload(for item: ArchiveItem, preloadedDetail: BroadcastDetail? = nil) async {
        lastErrorMessage = nil
        deviceSpaceError = nil
        budgetPrompt = nil

        guard let container = modelContainer else {
            lastErrorMessage = "Downloads nicht initialisiert."
            return
        }

        if let existing = localFileURL(for: item.terminID, container: container), FileManager.default.fileExists(atPath: existing.path) {
            await refreshSnapshotFromStore()
            return
        }

        snapshotByTerminID[item.terminID] = EpisodeDownloadUISnapshot(status: .preparing, progress: 0, expectedSizeBytes: 0)

        let context = ModelContext(container)
        let row = try? fetchOrCreateRow(for: item, context: context)
        guard let row else {
            snapshotByTerminID.removeValue(forKey: item.terminID)
            lastErrorMessage = "Download konnte nicht angelegt werden."
            await refreshSnapshotFromStore()
            return
        }
        if row.status == .downloading || row.status == .queued || row.status == .preparing {
            if terminIDToTask[item.terminID] != nil { return }
        }

        row.status = .preparing
        row.progress = 0
        row.errorMessage = nil
        try? context.save()

        let detail: BroadcastDetail?
        if let p = preloadedDetail {
            detail = p
        } else {
            detail = await APIClient.shared.fetchBroadcastDetail(for: item)
        }

        guard let detail else {
            row.status = .failed
            row.errorMessage = "Details nicht verfügbar (Offline?)."
            try? context.save()
            await refreshSnapshotFromStore()
            lastErrorMessage = row.errorMessage
            return
        }

        do {
            try StoredOfflineBroadcastDetail.upsert(terminID: item.terminID, detail: detail, context: context)
            try context.save()
        } catch {
            LogManager.shared.log("Offline detail save failed: \(error)", type: .error)
        }

        let candidates = Self.resolveRemoteAudioURLCandidates(for: item, detail: detail)
        guard !candidates.isEmpty else {
            row.status = .failed
            row.errorMessage = DownloadError.noAudioURL.localizedDescription
            try? context.save()
            await refreshSnapshotFromStore()
            lastErrorMessage = row.errorMessage
            return
        }
        let remoteURL = await selectReachableDownloadURL(candidates: candidates) ?? candidates[0]
        LogManager.shared.log("Download URL selected for terminID \(item.terminID): \(remoteURL.absoluteString)", type: .debug)

        let expected: Int64
        do {
            expected = try await fetchExpectedContentLength(url: remoteURL)
        } catch {
            expected = 0
        }
        row.expectedSizeBytes = expected
        try? context.save()
        snapshotByTerminID[item.terminID] = EpisodeDownloadUISnapshot(
            status: .preparing,
            progress: 0,
            expectedSizeBytes: expected
        )

        let budgetBytes = expected > 0 ? expected : Self.fallbackBudgetBytesPerEpisode
        let reserve = budgetBytes + 32 * 1024 * 1024
        do {
            try Self.ensureDeviceHasFreeSpace(forBytes: UInt64(reserve))
        } catch {
            row.status = .failed
            let msg = error.localizedDescription
            row.errorMessage = msg
            try? context.save()
            await refreshSnapshotFromStore()
            deviceSpaceError = msg
            return
        }

        let settings: StoredDownloadSettings
        do {
            settings = try StoredDownloadSettings.fetchOrCreate(context: context)
        } catch {
            row.status = .failed
            row.errorMessage = "Einstellungen konnten nicht geladen werden."
            try? context.save()
            await refreshSnapshotFromStore()
            lastErrorMessage = row.errorMessage
            return
        }

        let budgetOK = await ensureUnderAppBudget(
            context: context,
            settings: settings,
            additionalBytes: budgetBytes,
            excludingTerminID: item.terminID
        )

        if !budgetOK {
            pendingRetry = (item, detail)
            pendingExpectedBytes = budgetBytes
            budgetPrompt = DownloadBudgetPrompt(
                message: "Das Download-Speicherlimit ist erreicht (laufende und wartende Downloads zählen mit). Es werden nacheinander die ältesten fertigen Downloads gelöscht, bis wieder Platz ist — das können eine oder mehrere Sendungen sein. Fortfahren?",
                terminIDToDownload: item.terminID
            )
            row.status = .queued
            row.progress = 0
            try? context.save()
            await refreshSnapshotFromStore()
            return
        }

        await enqueueDownloadTask(remoteURL: remoteURL, item: item, context: context, row: row)
    }

    public func cancelDownload(for terminID: Int) {
        guard let tid = terminIDToTask[terminID], let session = urlSession else { return }
        session.getAllTasks { tasks in
            tasks.filter { $0.taskIdentifier == tid }.forEach { $0.cancel() }
        }
        Task { @MainActor in
            terminIDToTask[terminID] = nil
            taskToTerminID.removeValue(forKey: tid)
            taskToRemoteURL.removeValue(forKey: tid)
            if let container = modelContainer {
                let ctx = ModelContext(container)
                let fd = FetchDescriptor<StoredDownloadedEpisode>(
                    predicate: #Predicate<StoredDownloadedEpisode> { $0.terminID == terminID }
                )
                if let row = try? ctx.fetch(fd).first, row.status != .downloaded {
                    row.status = .failed
                    row.errorMessage = "Abgebrochen."
                    try? ctx.save()
                }
            }
            await refreshSnapshotFromStore()
        }
    }

    /// User confirmed: delete oldest downloaded episode(s) until budget fits, then retry pending download.
    public func confirmDeleteOldestForBudgetAndRetry() async {
        guard let pending = pendingRetry, let container = modelContainer else {
            budgetPrompt = nil
            return
        }
        // `mainContext` wie die SwiftUI-`@Query`/Umgebung — gleicher Kontext vermeidet Stände, in denen Löschen in einem Ephemeral-Context nicht sichtbar wird.
        let context = container.mainContext
        guard let settings = try? StoredDownloadSettings.fetchOrCreate(context: context) else {
            budgetPrompt = nil
            return
        }

        await deleteOldestDownloadedEpisodesUntilBudgetFits(
            context: context,
            settings: settings,
            additionalBytes: pendingExpectedBytes,
            excludingTerminID: pending.item.terminID
        )

        let ok = await ensureUnderAppBudget(
            context: context,
            settings: settings,
            additionalBytes: pendingExpectedBytes,
            excludingTerminID: pending.item.terminID
        )
        budgetPrompt = nil
        pendingRetry = nil
        pendingExpectedBytes = 0

        if ok {
            await startDownload(for: pending.item, preloadedDetail: pending.detail)
            await processDownloadQueue()
        } else {
            lastErrorMessage = "Nicht genug Platz im Download-Speicher. Keine weiteren Downloads zum Entfernen oder Limit zu niedrig."
        }
    }

    /// Nur die sichtbare Alert-Flagge löschen (SwiftUI schließt das Sheet). **Wichtig:** `pendingRetry` bleibt erhalten, bis die Bestätigung verarbeitet ist — sonst würde `dismissBudgetPrompt()` das Pending vor `confirmDeleteOldestForBudgetAndRetry` zerstören.
    public func clearBudgetPromptBannerOnly() {
        budgetPrompt = nil
    }

    public func dismissBudgetPrompt() {
        if let pending = pendingRetry, let container = modelContainer {
            let ctx = ModelContext(container)
            let tid = pending.item.terminID
            let fd = FetchDescriptor<StoredDownloadedEpisode>(
                predicate: #Predicate<StoredDownloadedEpisode> { $0.terminID == tid }
            )
            if let row = try? ctx.fetch(fd).first, row.status == .queued {
                row.status = .failed
                row.errorMessage = "Download abgebrochen (Speicherlimit)."
                try? ctx.save()
            }
        }
        budgetPrompt = nil
        pendingRetry = nil
        pendingExpectedBytes = 0
        Task {
            await refreshSnapshotFromStore()
        }
    }

    private static func downloadErrorDescription(_ error: Error, response: URLResponse?) -> String {
        var parts: [String] = [error.localizedDescription]
        let ns = error as NSError
        parts.append("NSError \(ns.domain)#\(ns.code)")
        if let urlErr = error as? URLError {
            parts.append("URLError \(urlErr.code.rawValue)")
        }
        if let http = response as? HTTPURLResponse {
            parts.append("HTTP \(http.statusCode)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Session events (called from bridge on arbitrary queue)

    fileprivate func downloadDidFinish(
        taskIdentifier: Int,
        localURL: URL,
        response: URLResponse?,
        error: Error?
    ) {
        Task { @MainActor in
            defer { Self.removeStagedDownloadTempFileIfNeeded(at: localURL) }
            defer { Task { @MainActor [weak self] in await self?.processDownloadQueue() } }
            let remoteSourceURL = taskToRemoteURL.removeValue(forKey: taskIdentifier)
            guard let terminID = taskToTerminID.removeValue(forKey: taskIdentifier) else { return }
            terminIDToTask.removeValue(forKey: terminID)
            guard let container = modelContainer else { return }
            let ctx = ModelContext(container)
            let fd = FetchDescriptor<StoredDownloadedEpisode>(
                predicate: #Predicate<StoredDownloadedEpisode> { $0.terminID == terminID }
            )
            guard let row = try? ctx.fetch(fd).first else { return }

            if let error {
                row.status = .failed
                row.errorMessage = Self.downloadErrorDescription(error, response: response)
                lastErrorMessage = row.errorMessage
                LogManager.shared.log(
                    "Download failed for terminID \(terminID): \(row.errorMessage ?? "unknown error")",
                    type: .error
                )
                try? ctx.save()
                await refreshSnapshotFromStore()
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                row.status = .failed
                row.errorMessage = "Server hat die Datei nicht geliefert (HTTP \(http.statusCode))."
                try? ctx.save()
                await refreshSnapshotFromStore()
                lastErrorMessage = row.errorMessage
                LogManager.shared.log("Download HTTP \(http.statusCode) for terminID \(terminID)", type: .error)
                return
            }

            let ext = Self.preferredLocalFileExtension(remoteURL: remoteSourceURL, response: response)
            let destName = "episode-\(terminID).\(ext)"
            let fm = FileManager.default
            do {
                guard fm.fileExists(atPath: localURL.path) else {
                    row.status = .failed
                    row.errorMessage = "Download-Datei konnte nicht gelesen werden."
                    try? ctx.save()
                    await refreshSnapshotFromStore()
                    return
                }
                let base = try DownloadFilesDirectory.baseDirectory()
                let dest = base.appendingPathComponent(destName, isDirectory: false)
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.copyItem(at: localURL, to: dest)
                let sz = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
                row.localFileName = destName
                row.fileSizeBytes = sz
                row.status = .downloaded
                row.progress = 1
                row.downloadedAt = Date()
                row.errorMessage = nil
                try ctx.save()
                await cacheModeratorImageIfNeeded(terminID: terminID, context: ctx)
            } catch {
                if let base = try? DownloadFilesDirectory.baseDirectory() {
                    let partial = base.appendingPathComponent(destName, isDirectory: false)
                    if fm.fileExists(atPath: partial.path) {
                        try? fm.removeItem(at: partial)
                    }
                }
                row.status = .failed
                row.errorMessage = error.localizedDescription
                lastErrorMessage = row.errorMessage
                LogManager.shared.log(
                    "Download file copy failed for terminID \(terminID): \(error.localizedDescription)",
                    type: .error
                )
                try? ctx.save()
            }
            await refreshSnapshotFromStore()
        }
    }

    /// Persists moderator portrait next to offline detail so detail UI works offline.
    private func cacheModeratorImageIfNeeded(terminID: Int, context: ModelContext) async {
        let tid = terminID
        let odFd = FetchDescriptor<StoredOfflineBroadcastDetail>(
            predicate: #Predicate<StoredOfflineBroadcastDetail> { $0.terminID == tid }
        )
        guard let od = try? context.fetch(odFd).first,
              let detail = try? od.decodeDetail(),
              let raw = detail.moderatorImage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let remote = URL(string: raw),
              let scheme = remote.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return }
        let rowFd = FetchDescriptor<StoredDownloadedEpisode>(
            predicate: #Predicate<StoredDownloadedEpisode> { $0.terminID == tid }
        )
        guard let row = try? context.fetch(rowFd).first else { return }
        do {
            var request = URLRequest(url: remote)
            Self.applyArchivDownloadHeaders(to: &request)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !data.isEmpty else { return }
            let mime = (response as? HTTPURLResponse)?.mimeType?.lowercased() ?? ""
            let ext: String
            if mime.contains("png") { ext = "png" }
            else if mime.contains("webp") { ext = "webp" }
            else if mime.contains("gif") { ext = "gif" }
            else { ext = "jpg" }
            let name = "moderator-\(terminID).\(ext)"
            let base = try DownloadFilesDirectory.baseDirectory()
            let dest = base.appendingPathComponent(name, isDirectory: false)
            let fm = FileManager.default
            if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
            try data.write(to: dest, options: .atomic)
            row.moderatorImageLocalFileName = name
            try context.save()
        } catch {
            LogManager.shared.log("Moderator image cache failed for terminID \(terminID): \(error.localizedDescription)", type: .debug)
        }
    }

    fileprivate func downloadDidProgress(
        taskIdentifier: Int,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            guard let terminID = taskToTerminID[taskIdentifier] else { return }
            let p: Double
            if totalBytesExpectedToWrite > 0 {
                p = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
            } else {
                p = 0
            }
            var expectedSnap: Int64 = 0
            if let container = modelContainer {
                let ctx = ModelContext(container)
                let fd = FetchDescriptor<StoredDownloadedEpisode>(
                    predicate: #Predicate<StoredDownloadedEpisode> { $0.terminID == terminID }
                )
                if let row = try? ctx.fetch(fd).first {
                    expectedSnap = row.expectedSizeBytes
                    row.progress = p
                    row.status = .downloading
                    try? ctx.save()
                }
            }
            snapshotByTerminID[terminID] = EpisodeDownloadUISnapshot(
                status: .downloading,
                progress: p,
                expectedSizeBytes: expectedSnap
            )
        }
    }

    fileprivate func sessionDidFinishBackgroundEvents() {
        DispatchQueue.main.async {
            Self.backgroundCompletionHandler?()
            Self.backgroundCompletionHandler = nil
        }
    }

    // MARK: - Internals

    private func enqueueDownloadTask(
        remoteURL: URL,
        item: ArchiveItem,
        context: ModelContext,
        row: StoredDownloadedEpisode
    ) async {
        guard let session = urlSession else { return }
        if terminIDToTask.count >= maxConcurrentDownloads {
            row.status = .queued
            row.progress = 0
            row.applyArchiveMetadata(from: item)
            try? context.save()
            await refreshSnapshotFromStore()
            return
        }
        row.status = .downloading
        row.progress = 0
        row.applyArchiveMetadata(from: item)
        try? context.save()

        var request = URLRequest(url: remoteURL)
        Self.applyArchivDownloadHeaders(to: &request)
        let task = session.downloadTask(with: request)
        task.taskDescription = String(item.terminID)
        taskToTerminID[task.taskIdentifier] = item.terminID
        terminIDToTask[item.terminID] = task.taskIdentifier
        taskToRemoteURL[task.taskIdentifier] = remoteURL
        LogManager.shared.log(
            "Starting download task \(task.taskIdentifier) for terminID \(item.terminID) @ \(remoteURL.absoluteString)",
            type: .info
        )
        task.resume()
        await refreshSnapshotFromStore()
    }

    private func fetchOrCreateRow(for item: ArchiveItem, context: ModelContext) throws -> StoredDownloadedEpisode {
        let itemTerminID = item.terminID
        let fd = FetchDescriptor<StoredDownloadedEpisode>(
            predicate: #Predicate<StoredDownloadedEpisode> { $0.terminID == itemTerminID }
        )
        if let existing = try context.fetch(fd).first {
            existing.applyArchiveMetadata(from: item)
            return existing
        }
        let row = StoredDownloadedEpisode(item: item, status: .queued)
        context.insert(row)
        try context.save()
        return row
    }

    /// Startet wartende `.queued`-Zeilen, solange noch Download-Slots frei sind (FIFO nach `createdAt`).
    private func processDownloadQueue() async {
        guard let container = modelContainer else { return }
        while terminIDToTask.count < maxConcurrentDownloads {
            let ctx = ModelContext(container)
            let fd = FetchDescriptor<StoredDownloadedEpisode>(
                // SwiftData `#Predicate` kann Enum-Cases manchmal als „KeyPath auf Enum-Case“ interpretieren.
                // Darum vergleichen wir stabil gegen das gespeicherte RawValue.
                predicate: #Predicate<StoredDownloadedEpisode> { $0.statusRaw == "queued" },
                sortBy: [SortDescriptor(\.createdAt, order: .forward)]
            )
            guard let rows = try? ctx.fetch(fd), !rows.isEmpty else { break }
            var anyStarted = false
            for row in rows {
                let before = terminIDToTask.count
                await startDownload(for: row.toArchiveItem(), preloadedDetail: nil)
                if terminIDToTask.count > before {
                    anyStarted = true
                    break
                }
            }
            if !anyStarted { break }
        }
    }

    public func refreshSnapshotFromStore() async {
        guard let container = modelContainer else { return }
        let ctx = ModelContext(container)
        let fd = FetchDescriptor<StoredDownloadedEpisode>()
        guard let rows = try? ctx.fetch(fd) else { return }
        var map: [Int: EpisodeDownloadUISnapshot] = [:]
        for r in rows {
            map[r.terminID] = EpisodeDownloadUISnapshot(
                status: r.status,
                progress: r.progress,
                expectedSizeBytes: r.expectedSizeBytes
            )
        }
        snapshotByTerminID = map
    }

    public func runForegroundMaintenance() async {
        await applyRetentionIfNeeded()
        await reconcileOrphans()
        urlSession?.getAllTasks { tasks in
            Task { @MainActor in
                self.reconnectRunningTasks(activeTasks: tasks)
                await self.refreshSnapshotFromStore()
                await self.processDownloadQueue()
            }
        }
        if urlSession == nil {
            await refreshSnapshotFromStore()
            await processDownloadQueue()
        }
    }

    public func markLastPlayed(terminID: Int) {
        guard let container = modelContainer else { return }
        let ctx = ModelContext(container)
        let fd = FetchDescriptor<StoredDownloadedEpisode>(
            predicate: #Predicate<StoredDownloadedEpisode> { $0.terminID == terminID }
        )
        guard let row = try? ctx.fetch(fd).first else { return }
        row.lastPlayedAt = Date()
        try? ctx.save()
    }

    /// Local cached moderator image for a downloaded episode (detail screen offline).
    public static func resolvedModeratorImageURL(terminID: Int, context: ModelContext) -> URL? {
        let tid = terminID
        let fd = FetchDescriptor<StoredDownloadedEpisode>(
            predicate: #Predicate<StoredDownloadedEpisode> { $0.terminID == tid }
        )
        guard let row = try? context.fetch(fd).first else { return nil }
        return row.resolvedLocalModeratorImageURL()
    }

    func localFileURL(for terminID: Int, container: ModelContainer) -> URL? {
        let ctx = ModelContext(container)
        let fd = FetchDescriptor<StoredDownloadedEpisode>(
            predicate: #Predicate<StoredDownloadedEpisode> { $0.terminID == terminID }
        )
        guard let row = try? ctx.fetch(fd).first else { return nil }
        return row.resolvedLocalAudioURL()
    }

    /// Beitrag einer Zeile zum App-Download-Budget. Nutzt Dateigröße auf der Platte, wenn `fileSizeBytes` nie gesetzt wurde (sonst schlägt „Älteste löschen“ fehl).
    static func effectiveDownloadedAudioBytes(for row: StoredDownloadedEpisode) -> Int64 {
        guard row.status == .downloaded else { return 0 }
        if row.fileSizeBytes > 0 { return row.fileSizeBytes }
        if let url = row.resolvedLocalAudioURL(),
           let n = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            return Int64(n)
        }
        return max(0, row.expectedSizeBytes)
    }

    /// Alles, was gegen das App-Download-Limit zählt: fertige Dateien plus Reservierung für laufende/wartende Downloads (`expectedSizeBytes` bzw. Fallback), damit parallele Starts das Limit nicht überschreiten.
    static func budgetReservedBytes(for row: StoredDownloadedEpisode) -> Int64 {
        switch row.status {
        case .downloaded:
            return effectiveDownloadedAudioBytes(for: row)
        case .downloading, .queued, .preparing:
            if row.expectedSizeBytes > 0 { return row.expectedSizeBytes }
            return fallbackBudgetBytesPerEpisode
        case .failed:
            return 0
        }
    }

    private func ensureUnderAppBudget(
        context: ModelContext,
        settings: StoredDownloadSettings,
        additionalBytes: Int64,
        excludingTerminID: Int
    ) async -> Bool {
        let fd = FetchDescriptor<StoredDownloadedEpisode>()
        guard let rows = try? context.fetch(fd) else { return true }
        let sum = rows
            .filter { $0.terminID != excludingTerminID }
            .reduce(Int64(0)) { $0 + Self.budgetReservedBytes(for: $1) }
        return sum + additionalBytes <= settings.maxDownloadStorageBytes
    }

    private func deleteOldestDownloadedEpisodesUntilBudgetFits(
        context: ModelContext,
        settings: StoredDownloadSettings,
        additionalBytes: Int64,
        excludingTerminID: Int
    ) async {
        let limit = settings.maxDownloadStorageBytes
        while true {
            let fd = FetchDescriptor<StoredDownloadedEpisode>()
            guard let all = try? context.fetch(fd) else { break }
            let sumReserved = all
                .filter { $0.terminID != excludingTerminID }
                .reduce(Int64(0)) { $0 + Self.budgetReservedBytes(for: $1) }
            if sumReserved + additionalBytes <= limit { break }
            // Ältester **Download** (Zeitpunkt des Ladens), nicht Ausstrahlungsdatum der Sendung.
            let candidates = all.filter { $0.terminID != excludingTerminID && $0.status == .downloaded }
                .sorted { lhs, rhs in
                    let l = lhs.downloadedAt ?? lhs.createdAt
                    let r = rhs.downloadedAt ?? rhs.createdAt
                    if l != r { return l < r }
                    return lhs.terminID < rhs.terminID
                }
            guard let victim = candidates.first else { break }
            Self.deleteEpisodeFiles(victim, context: context)
            let tid = victim.terminID
            context.delete(victim)
            // Avoid `Predicate` capturing `terminID` from SwiftData model (`StoredDownloadedEpisode`) — breaks macro type inference.
            if let allOd = try? context.fetch(FetchDescriptor<StoredOfflineBroadcastDetail>()),
               let o = allOd.first(where: { $0.terminID == tid }) {
                context.delete(o)
            }
            try? context.save()
        }
        try? context.save()
        await refreshSnapshotFromStore()
    }

    /// Delete downloaded episode + offline detail + file on disk.
    public static func deleteDownloadedEpisode(terminID: Int, context: ModelContext) throws {
        let fd = FetchDescriptor<StoredDownloadedEpisode>(
            predicate: #Predicate<StoredDownloadedEpisode> { $0.terminID == terminID }
        )
        if let row = try context.fetch(fd).first {
            deleteEpisodeFiles(row, context: context)
            context.delete(row)
        }
        let od = FetchDescriptor<StoredOfflineBroadcastDetail>(
            predicate: #Predicate<StoredOfflineBroadcastDetail> { $0.terminID == terminID }
        )
        if let o = try context.fetch(od).first {
            context.delete(o)
        }
        try context.save()
    }

    private static func deleteEpisodeFiles(_ row: StoredDownloadedEpisode, context: ModelContext) {
        guard let base = try? DownloadFilesDirectory.baseDirectory() else { return }
        let fm = FileManager.default
        var audioNames: [String] = []
        if let name = row.localFileName, !name.isEmpty { audioNames.append(name) }
        // Auch ohne gesetzten `localFileName`: übliche Ziele (ältere Builds / Kopierfehler).
        audioNames.append("episode-\(row.terminID).mp3")
        audioNames.append("episode-\(row.terminID).m4a")
        var seen = Set<String>()
        for n in audioNames where seen.insert(n).inserted {
            let u = base.appendingPathComponent(n, isDirectory: false)
            if fm.fileExists(atPath: u.path) { try? fm.removeItem(at: u) }
        }
        if let m = row.moderatorImageLocalFileName, !m.isEmpty {
            let u = base.appendingPathComponent(m, isDirectory: false)
            try? fm.removeItem(at: u)
        }
    }

    private func reconcileOrphans() async {
        guard let container = modelContainer else { return }
        let ctx = ModelContext(container)
        let fd = FetchDescriptor<StoredDownloadedEpisode>()
        guard let rows = try? ctx.fetch(fd) else { return }
        var changed = false
        for row in rows where row.status == .downloaded {
            guard let url = row.resolvedLocalAudioURL() else {
                row.status = .failed
                row.errorMessage = "Datei fehlt."
                changed = true
                continue
            }
            if row.fileSizeBytes <= 0,
               let n = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                row.fileSizeBytes = Int64(n)
                changed = true
            }
        }
        if changed { try? ctx.save() }
        await refreshSnapshotFromStore()
    }

    private func applyRetentionIfNeeded() async {
        guard let container = modelContainer else { return }
        let ctx = ModelContext(container)
        guard let settings = try? StoredDownloadSettings.fetchOrCreate(context: ctx) else { return }
        let weeks: Int = settings.retentionWeeks
        guard weeks > 0, weeks <= 4 else { return }
        guard let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: Date()) else { return }
        let fd = FetchDescriptor<StoredDownloadedEpisode>()
        guard let rows = try? ctx.fetch(fd) else { return }
        var changed = false
        let nowPlayingID = AudioPlayerManager.shared.currentItem?.terminID
        for row in rows where row.status == .downloaded {
            if let nowPlayingID, row.terminID == nowPlayingID { continue }
            let ref = row.downloadedAt ?? row.createdAt
            if ref < cutoff {
                Self.deleteEpisodeFiles(row, context: ctx)
                let tidToRemove = row.terminID
                ctx.delete(row)
                if let allOd = try? ctx.fetch(FetchDescriptor<StoredOfflineBroadcastDetail>()),
                   let o = allOd.first(where: { $0.terminID == tidToRemove }) {
                    ctx.delete(o)
                }
                changed = true
            }
        }
        if changed { try? ctx.save() }
        await refreshSnapshotFromStore()
    }

    static func resolveRemoteAudioURL(for item: ArchiveItem, detail: BroadcastDetail?) -> URL? {
        resolveRemoteAudioURLCandidates(for: item, detail: detail).first
    }

    static func resolveRemoteAudioURLCandidates(for item: ArchiveItem, detail: BroadcastDetail?) -> [URL] {
        var urls: [URL] = []
        if let rec = detail?.recordings.first {
            let u = rec.recordingUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            if !u.isEmpty {
                if u.hasPrefix("http://") || u.hasPrefix("https://") {
                    if let absolute = URL(string: u) { urls.append(absolute) }
                } else if let absolute = makeArchivAudioURL(relativePath: u) {
                    urls.append(absolute)
                }
            }
        }
        if !item.audioFile1.isEmpty, let fromArchiveItem = makeArchivAudioURL(relativePath: item.audioFile1) {
            urls.append(fromArchiveItem)
        }
        // Preserve order but avoid duplicate retries for the same URL.
        var seen: Set<String> = []
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    private func selectReachableDownloadURL(candidates: [URL]) async -> URL? {
        guard !candidates.isEmpty else { return nil }
        for url in candidates {
            if await canProbeDownloadURL(url: url) {
                return url
            }
        }
        return nil
    }

    private func canProbeDownloadURL(url: URL) async -> Bool {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpAdditionalHeaders = [
            "User-Agent": Self.safariLikeDownloadUserAgent,
            "Accept": "*/*",
            "Accept-Language": "de-DE,de;q=0.9,en;q=0.8"
        ]
        let session = URLSession(configuration: config)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        Self.applyArchivDownloadHeaders(to: &req)
        do {
            let (_, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode) || http.statusCode == 206
        } catch {
            return false
        }
    }

    /// Builds `https://archiv.bytefm.com/…` with percent-encoded path segments (spaces, umlauts, etc.).
    nonisolated fileprivate static func makeArchivAudioURL(relativePath: String) -> URL? {
        var path = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        while path.hasPrefix("/") { path.removeFirst() }
        let segments = path.split(separator: "/").map { substr -> String in
            String(substr).addingPercentEncoding(withAllowedCharacters: archivPathAllowed) ?? String(substr)
        }
        guard !segments.isEmpty else { return nil }
        return URL(string: "https://archiv.bytefm.com/" + segments.joined(separator: "/"))
    }

    /// HEAD uses a delegate-free session so it never interferes with the download `URLSession` delegate.
    private func fetchExpectedContentLength(url: URL) async throws -> Int64 {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpAdditionalHeaders = [
            "User-Agent": Self.safariLikeDownloadUserAgent,
            "Accept": "*/*",
            "Accept-Language": "de-DE,de;q=0.9,en;q=0.8"
        ]
        let session = URLSession(configuration: config)
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        Self.applyArchivDownloadHeaders(to: &req)
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { return 0 }
        if !(200...299).contains(http.statusCode) {
            return 0
        }
        let cl = http.value(forHTTPHeaderField: "Content-Length") ?? ""
        return Int64(cl) ?? 0
    }

    /// AVPlayer uses the file extension / type hint — `.bin` breaks MP3 playback even when bytes are correct.
    nonisolated fileprivate static func preferredLocalFileExtension(remoteURL: URL?, response: URLResponse?) -> String {
        if let http = response as? HTTPURLResponse, let mime = http.mimeType?.lowercased() {
            if mime.contains("mpeg") || mime == "audio/mp3" || mime.contains("mp3") { return "mp3" }
            if mime.contains("mp4") || mime.contains("m4a") || mime.contains("aac") { return "m4a" }
            if mime.contains("wav") { return "wav" }
        }
        if let u = remoteURL {
            var ext = u.pathExtension.lowercased()
            if ext == "bin" { ext = "" }
            if !ext.isEmpty, ext.count <= 5 { return ext }
        }
        return "mp3"
    }

    /// Renames legacy `episode-*.bin` files saved before extension fix (one-time per row).
    private func migrateLegacyBinDownloadFilenamesIfNeeded() async {
        guard let container = modelContainer else { return }
        guard let base = try? DownloadFilesDirectory.baseDirectory() else { return }
        let ctx = ModelContext(container)
        let fd = FetchDescriptor<StoredDownloadedEpisode>()
        guard let rows = try? ctx.fetch(fd) else { return }
        var changed = false
        for row in rows where row.status == .downloaded {
            guard let name = row.localFileName, name.hasSuffix(".bin") else { continue }
            let oldURL = base.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: oldURL.path) else { continue }
            let newName = "episode-\(row.terminID).mp3"
            let newURL = base.appendingPathComponent(newName)
            do {
                if FileManager.default.fileExists(atPath: newURL.path) {
                    try FileManager.default.removeItem(at: newURL)
                }
                try FileManager.default.moveItem(at: oldURL, to: newURL)
                row.localFileName = newName
                changed = true
            } catch {
                LogManager.shared.log(
                    "Legacy .bin download migrate failed terminID \(row.terminID): \(error.localizedDescription)",
                    type: .error
                )
            }
        }
        if changed {
            try? ctx.save()
            await refreshSnapshotFromStore()
        }
    }

    /// CDNs often expect browser-like context and may challenge bare mobile clients.
    /// `nonisolated`: URLSession delegates run off the main actor; this helper only sets headers.
    nonisolated fileprivate static func applyArchivDownloadHeaders(to request: inout URLRequest) {
        request.setValue(safariLikeDownloadUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("de-DE,de;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        if #available(iOS 16.0, *) {
            request.assumesHTTP3Capable = false
        }
        if let host = request.url?.host?.lowercased(), host.contains("bytefm.com") {
            request.setValue("https://www.bytefm.de/", forHTTPHeaderField: "Referer")
        }
    }

    private static func ensureDeviceHasFreeSpace(forBytes: UInt64) throws {
        let fm = FileManager.default
        guard let doc = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw DownloadError.notEnoughFreeSpace
        }
        let vals = try doc.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let avail = vals.volumeAvailableCapacityForImportantUsage, UInt64(avail) >= forBytes else {
            throw DownloadError.notEnoughFreeSpace
        }
    }

    public static func totalDownloadedBytes(context: ModelContext) throws -> Int64 {
        let fd = FetchDescriptor<StoredDownloadedEpisode>()
        let rows = try context.fetch(fd)
        return rows.reduce(0) { $0 + effectiveDownloadedAudioBytes(for: $1) }
    }

    /// Clears all download rows, offline detail JSON, settings, and files (e.g. on logout).
    public static func purgeAllOnLogout(container: ModelContainer) {
        let ctx = ModelContext(container)
        if let episodes = try? ctx.fetch(FetchDescriptor<StoredDownloadedEpisode>()) {
            for row in episodes {
                deleteEpisodeFiles(row, context: ctx)
                ctx.delete(row)
            }
        }
        if let details = try? ctx.fetch(FetchDescriptor<StoredOfflineBroadcastDetail>()) {
            for row in details {
                ctx.delete(row)
            }
        }
        if let settings = try? ctx.fetch(FetchDescriptor<StoredDownloadSettings>()) {
            for row in settings {
                ctx.delete(row)
            }
        }
        try? ctx.save()
        if let base = try? DownloadFilesDirectory.baseDirectory(),
           FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.removeItem(at: base)
            _ = try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
    }
}

// MARK: - Budget prompt model

public struct DownloadBudgetPrompt: Identifiable, Equatable {
    public let id = UUID()
    public var message: String
    public var terminIDToDownload: Int

    public init(message: String, terminIDToDownload: Int) {
        self.message = message
        self.terminIDToDownload = terminIDToDownload
    }
}

// MARK: - URLSession bridge

private final class DownloadSessionBridge: NSObject, URLSessionDownloadDelegate {
    weak var manager: IOSDownloadManager?

    init(manager: IOSDownloadManager) {
        self.manager = manager
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        LogManager.shared.log(
            "Download redirect task \(task.taskIdentifier): HTTP \(response.statusCode) -> \(request.url?.absoluteString ?? "nil")",
            type: .info
        )
        var redirected = request
        IOSDownloadManager.applyArchivDownloadHeaders(to: &redirected)
        completionHandler(redirected)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let tid = downloadTask.taskIdentifier
        Task { @MainActor in
            manager?.downloadDidProgress(
                taskIdentifier: tid,
                totalBytesWritten: totalBytesWritten,
                totalBytesExpectedToWrite: totalBytesExpectedToWrite
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let tid = downloadTask.taskIdentifier
        let resp = downloadTask.response
        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
        LogManager.shared.log(
            "didFinishDownloadingTo for task \(tid) HTTP=\(status) temp=\(location.lastPathComponent)",
            type: .info
        )

        // IMPORTANT: `location` is only guaranteed while this delegate callback is active.
        // Stage the file synchronously to a durable temp URL before hopping to MainActor.
        let stagedURL: URL
        do {
            let fm = FileManager.default
            let stagedName = "bitefm-download-\(tid)-\(UUID().uuidString).tmp"
            stagedURL = fm.temporaryDirectory.appendingPathComponent(stagedName, isDirectory: false)
            if fm.fileExists(atPath: stagedURL.path) {
                try fm.removeItem(at: stagedURL)
            }
            try fm.moveItem(at: location, to: stagedURL)
        } catch {
            let ns = error as NSError
            LogManager.shared.log(
                "Failed to stage download temp file for task \(tid): \(error.localizedDescription) [\(ns.domain)#\(ns.code)]",
                type: .error
            )
            Task { @MainActor in
                manager?.downloadDidFinish(
                    taskIdentifier: tid,
                    localURL: URL(fileURLWithPath: "/"),
                    response: resp,
                    error: error
                )
            }
            return
        }

        Task { @MainActor in
            manager?.downloadDidFinish(
                taskIdentifier: tid,
                localURL: stagedURL,
                response: resp,
                error: nil
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        guard task is URLSessionDownloadTask else { return }
        let tid = task.taskIdentifier
        let resp = task.response
        let ns = error as NSError
        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
        LogManager.shared.log(
            "URLSession download task \(tid) didCompleteWithError: \(error.localizedDescription) [\(ns.domain)#\(ns.code)] HTTP=\(status)",
            type: .error
        )
        Task { @MainActor in
            manager?.downloadDidFinish(
                taskIdentifier: tid,
                localURL: URL(fileURLWithPath: "/"),
                response: resp,
                error: error
            )
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            manager?.sessionDidFinishBackgroundEvents()
        }
    }
}
#endif

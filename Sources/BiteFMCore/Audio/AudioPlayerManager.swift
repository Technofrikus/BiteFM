import Foundation
import AVFoundation
import MediaPlayer
import SwiftData
#if os(iOS)
import UIKit
#endif

@MainActor
public class AudioPlayerManager: NSObject, ObservableObject {
    public static let shared = AudioPlayerManager()
    
    private var player: AVPlayer?
    private var didSetupRemoteTransportControls = false
    private var playCommandToken: Any?
    private var pauseCommandToken: Any?
    private var togglePlayPauseCommandToken: Any?
    private var nextTrackCommandToken: Any?
    private var previousTrackCommandToken: Any?
    #if os(iOS)
    private var audioInterruptionObserver: NSObjectProtocol?
    private var wasPlayingBeforeInterruption = false
    #endif
    @Published public var isPlaying = false
    @Published public var isStalled = false
    @Published public var currentItem: ArchiveItem?
    @Published public var currentPlaylist: [PlaylistItem]?
    @Published public var currentTime: Double = 0
    @Published public var duration: Double = 0
    @Published public var isLive = false
    @Published public var currentStreamType: StreamType?
    /// Shown in alerts (e.g. Live offline, playback failure); cleared when starting new playback or by the UI.
    @Published public var userFacingPlaybackError: String?

    private var hasMarkedCurrentItemAsPlayed = false
    private var lastMarkedTerminID: Int?
    
    var modelContainer: ModelContainer?
    
    private var timeObserver: Any?
    private var lastUpdatedSongId: String?
    private var lastSavedPosition: Double = 0

    /// Wenn die gespeicherte Position im letzten Intervall liegt, sonst startet Wiedergabe „am Ende“ ohne Ton.
    private let nearEndPlaybackThreshold: Double = 5.0
    
    /// Nur in diesem Fall Position am Ende auf Anfang setzen (nicht bei explizitem `initialPosition`, z. B. Playlist).
    private var resumeWasFromSavedPositionOnly = false

    #if os(iOS)
    /// Lock Screen / Dynamic Island zeigen ohne Artwork nur ein generisches Symbol; das App-Icon ist nicht per API ladbar — wir nutzen das Marken-Logo aus dem Asset-Katalog.
    private static let brandNowPlayingArtwork: MPMediaItemArtwork? = {
        guard let image = UIImage(named: "Logo", in: Bundle.module, compatibleWith: nil) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { size in
            guard size.width > 0, size.height > 0 else { return image }
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = image.scale
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }()

    private static func applyBrandArtworkToNowPlayingInfo(_ info: inout [String: Any]) {
        if let artwork = brandNowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
    }
    #endif

    public override init() {
        super.init()
        setupAudioSession()
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
        setupRemoteTransportControls()
    }
    
    func setup(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        
        // Initial cleanup of old playback positions
        Task {
            await cleanupOldPlaybackPositions()
        }
    }
    
    private func cleanupOldPlaybackPositions() async {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        
        let fourWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<StoredPlaybackPosition>()
        
        do {
            let positions = try context.fetch(descriptor)
            let oldPositions = positions.filter { $0.lastPlayed < fourWeeksAgo }
            
            if !oldPositions.isEmpty {
                LogManager.shared.log("Cleaning up \(oldPositions.count) old playback positions", type: .info)
                for pos in oldPositions {
                    context.delete(pos)
                }
                try context.save()
            }
        } catch {
            LogManager.shared.log("Failed to cleanup old playback positions: \(error)", type: .error)
        }
    }
    
    private func savePlaybackPosition() {
        guard let item = currentItem, !isLive, let container = modelContainer else { return }
        let currentPos = currentTime
        
        if duration > 0, currentPos >= duration - nearEndPlaybackThreshold {
            clearStoredPlaybackPosition(for: item.terminID)
            return
        }
        
        // Only save if position changed significantly (more than 1 second)
        guard abs(currentPos - lastSavedPosition) > 1.0 else { return }
        
        let terminID = item.terminID
        let context = ModelContext(container)
        
        Task {
            do {
                let descriptor = FetchDescriptor<StoredPlaybackPosition>(predicate: #Predicate<StoredPlaybackPosition> { $0.terminID == terminID })
                let existing = try context.fetch(descriptor).first
                
                if let existing = existing {
                    existing.position = currentPos
                    existing.lastPlayed = Date()
                } else {
                    let newPos = StoredPlaybackPosition(terminID: terminID, position: currentPos)
                    context.insert(newPos)
                }
                
                try context.save()
                lastSavedPosition = currentPos
            } catch {
                // Silently fail or log to LogManager
            }
        }
    }
    
    private func loadPlaybackPosition(for terminID: Int) async -> Double? {
        guard let container = modelContainer else { return nil }
        let context = ModelContext(container)
        
        do {
            let descriptor = FetchDescriptor<StoredPlaybackPosition>(predicate: #Predicate<StoredPlaybackPosition> { $0.terminID == terminID })
            let existing = try context.fetch(descriptor).first
            return existing?.position
        } catch {
            return nil
        }
    }
    
    private func setupAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            LogManager.shared.log("AudioSession configured successfully", type: .info)
        } catch {
            LogManager.shared.log("Failed to setup AVAudioSession: \(error)", type: .error)
        }
        registerAudioInterruptionObserver()
        #endif
    }

    #if os(iOS)
    private func registerAudioInterruptionObserver() {
        guard audioInterruptionObserver == nil else { return }
        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioSessionInterruption(notification)
            }
        }
    }

    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying {
                pause()
            }
        case .ended:
            let shouldResume: Bool = {
                guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return false }
                return AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume)
            }()
            if wasPlayingBeforeInterruption && shouldResume {
                wasPlayingBeforeInterruption = false
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    LogManager.shared.log("Failed to reactivate AVAudioSession: \(error)", type: .error)
                }
                player?.play()
                updatePlaybackRate(1.0)
            } else {
                wasPlayingBeforeInterruption = false
            }
        @unknown default:
            break
        }
    }
    #endif
    
    public func play(item: ArchiveItem, playlist: [PlaylistItem]? = nil, initialPosition: Double? = nil) {
        isLive = false
        currentStreamType = nil
        lastUpdatedSongId = nil
        resumeWasFromSavedPositionOnly = false
        hasMarkedCurrentItemAsPlayed = lastMarkedTerminID == item.terminID
        
        Task {
            await APIClient.shared.refreshListeningHistoryIfStale()
        }
        
        // Save previous item's position if any
        if let _ = currentItem {
            savePlaybackPosition()
        }

        #if os(iOS)
        if let container = modelContainer,
           let localURL = IOSDownloadManager.shared.localFileURL(for: item.terminID, container: container) {
            self.currentItem = item
            self.currentPlaylist = playlist
            Task {
                let startAt: Double
                if let initialPosition = initialPosition {
                    startAt = initialPosition
                } else {
                    startAt = await self.loadPlaybackPosition(for: item.terminID) ?? 0
                    self.resumeWasFromSavedPositionOnly = true
                }
                self.play(url: localURL, startAt: startAt)
                self.setupNowPlaying(item: item)
                self.updatePlaybackRate(1.0)
                IOSDownloadManager.shared.markLastPlayed(terminID: item.terminID)
                if playlist == nil {
                    if let detail = await APIClient.shared.fetchBroadcastDetail(for: item) {
                        if self.currentItem?.id == item.id {
                            self.currentPlaylist = detail.recordings.first?.playlist
                            self.updateNowPlayingForArchive()
                        }
                    }
                }
            }
            return
        }
        #endif
        
        // If we don't have an audio file, we MUST fetch detail first
        if item.audioFile1.isEmpty {
            Task { @MainActor in
                #if os(iOS)
                guard await NetworkPathProbe.isPathSatisfied() else {
                    userFacingPlaybackError = "Keine Internetverbindung. Für diese Ausgabe liegt keine lokale Datei vor."
                    return
                }
                #endif
                if let detail = await APIClient.shared.fetchBroadcastDetail(for: item) {
                    // detail.recordings.first?.recordingUrl is the audio file
                    if let firstRecording = detail.recordings.first {
                        let recordingUrl = firstRecording.recordingUrl
                        // The recordingUrl might be full or partial
                        let fullUrl: URL? = {
                            if recordingUrl.hasPrefix("http") {
                                return URL(string: recordingUrl)
                            } else {
                                return URL(string: "https://archiv.bytefm.com/" + recordingUrl)
                            }
                        }()
                        
                        if let url = fullUrl {
                            self.currentItem = item
                            self.currentPlaylist = firstRecording.playlist
                            
                            // Use initialPosition if provided, otherwise load saved position
                            let startAt: Double
                            if let initialPosition = initialPosition {
                                startAt = initialPosition
                            } else {
                                startAt = await self.loadPlaybackPosition(for: item.terminID) ?? 0
                                self.resumeWasFromSavedPositionOnly = true
                            }
                            
                            self.play(url: url, startAt: startAt)
                            
                            self.setupNowPlaying(item: item)
                            self.updatePlaybackRate(1.0)
                            
                        }
                    }
                }
            }
            return
        }
        
        let baseUrlString = "https://archiv.bytefm.com/"
        guard let url = URL(string: baseUrlString + item.audioFile1) else { return }

        Task { @MainActor in
            #if os(iOS)
            guard await NetworkPathProbe.isPathSatisfied() else {
                userFacingPlaybackError = "Keine Internetverbindung. Für diese Ausgabe liegt keine lokale Datei vor."
                return
            }
            #endif
            self.currentItem = item
            self.currentPlaylist = playlist

            let startAt: Double
            if let initialPosition = initialPosition {
                startAt = initialPosition
            } else {
                startAt = await self.loadPlaybackPosition(for: item.terminID) ?? 0
                self.resumeWasFromSavedPositionOnly = true
            }

            self.play(url: url, startAt: startAt)

            setupNowPlaying(item: item)
            updatePlaybackRate(1.0)

            if playlist == nil {
                if let detail = await APIClient.shared.fetchBroadcastDetail(for: item) {
                    if self.currentItem?.id == item.id {
                        self.currentPlaylist = detail.recordings.first?.playlist
                        self.updateNowPlayingForArchive()
                    }
                }
            }
        }
    }

    private func setupTimeObserver() {
        guard let player = player else { return }
        
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
        
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] time in
            // Use Task to hop back to the MainActor if needed, but since we are on queue: .main
            // it's enough to let the compiler know.
            Task { @MainActor in
                guard let self = self else { return }
                let pos = time.seconds
                guard pos.isFinite else { return }
                self.currentTime = pos
                
                // „Gehört“: Server via `markAsPlayed` (Broadcast-GET ohne listen=no) + Hörhistorie. Schwelle: 5 Min. in der Datei;
                // kürzere Ausgaben (< 5 Min. Länge): nahe am Ende.
                let listenedThresholdSeconds: Double = 300 // 5 Minuten
                if !self.isLive, let item = self.currentItem, !self.hasMarkedCurrentItemAsPlayed {
                    let dur: Double = {
                        if self.duration > 0 { return self.duration }
                        if let d = self.player?.currentItem?.duration.seconds, d.isFinite, d > 0 { return d }
                        return 0
                    }()
                    let shouldMark: Bool
                    if dur > 0, dur < listenedThresholdSeconds {
                        shouldMark = pos >= dur - 1.0
                    } else {
                        shouldMark = pos > listenedThresholdSeconds
                    }
                    if shouldMark {
                        self.hasMarkedCurrentItemAsPlayed = true
                        self.lastMarkedTerminID = item.terminID
                        Task {
                            await APIClient.shared.markAsPlayed(item: item)
                        }
                    }
                }
                
                // Update Now Playing if song changed
                if !self.isLive && self.currentItem != nil && self.currentPlaylist != nil {
                    let currentSong = self.currentPlaylist?.last(where: { Double($0.time) <= time.seconds + 1 })
                    if currentSong?.id != self.lastUpdatedSongId {
                        self.updateNowPlayingForArchive()
                    }
                }
                
                // Save position periodically (every 10 seconds or so)
                if !self.isLive && self.currentItem != nil && abs(self.currentTime - self.lastSavedPosition) > 10.0 {
                    self.savePlaybackPosition()
                }
            }
        }
    }

    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "timeControlStatus", let player = object as? AVPlayer {
            DispatchQueue.main.async {
                self.isStalled = (player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
                if player.timeControlStatus == .playing {
                    self.isPlaying = true
                    self.updatePlaybackRate(1.0)
                } else if player.timeControlStatus == .paused {
                    self.isPlaying = false
                    self.updatePlaybackRate(0.0)
                }
            }
        } else if keyPath == "status" {
            if let player = object as? AVPlayer {
                if player.status == .failed {
                    LogManager.shared.log("AVPlayer failed with error: \(String(describing: player.error))", type: .error)
                    DispatchQueue.main.async { [weak self] in
                        Task { @MainActor in
                            self?.handleStreamOrPlaybackFailure(wasLive: self?.isLive ?? false, error: player.error)
                        }
                    }
                }
            } else if let item = object as? AVPlayerItem {
                if item.status == .failed {
                    let err = item.error
                    LogManager.shared.log("AVPlayerItem failed with error: \(String(describing: err))", type: .error)
                    DispatchQueue.main.async { [weak self] in
                        Task { @MainActor in
                            self?.handleStreamOrPlaybackFailure(wasLive: self?.isLive ?? false, error: err)
                        }
                    }
                }
            }
        } else if keyPath == "duration", let item = object as? AVPlayerItem {
            DispatchQueue.main.async {
                let durationSeconds = item.duration.seconds
                if durationSeconds.isFinite, durationSeconds > 0 {
                    self.duration = durationSeconds
                    if !self.isLive, self.currentItem != nil, self.resumeWasFromSavedPositionOnly {
                        let t = self.player?.currentTime().seconds ?? self.currentTime
                        if t >= durationSeconds - self.nearEndPlaybackThreshold {
                            if let terminID = self.currentItem?.terminID {
                                self.clearStoredPlaybackPosition(for: terminID)
                            }
                            self.resumeWasFromSavedPositionOnly = false
                            self.seek(to: 0)
                        }
                    }
                }
            }
        }
    }

    private func updateNowPlayingForArchive() {
        guard let item = currentItem, !isLive else { return }
        
        var nowPlayingInfo = [String: Any]()
        
        if let playlist = currentPlaylist {
            let currentTime = self.currentTime
            let currentSong = playlist.last(where: { Double($0.time) <= currentTime + 1 })
            
            if let song = currentSong {
                nowPlayingInfo[MPMediaItemPropertyTitle] = song.title
                nowPlayingInfo[MPMediaItemPropertyArtist] = "\(song.artist) — \(item.sendungTitel)"
                lastUpdatedSongId = song.id
            } else {
                nowPlayingInfo[MPMediaItemPropertyTitle] = item.sendungTitel
                nowPlayingInfo[MPMediaItemPropertyArtist] = item.subtitle
                lastUpdatedSongId = nil
            }
        } else {
            nowPlayingInfo[MPMediaItemPropertyTitle] = item.sendungTitel
            nowPlayingInfo[MPMediaItemPropertyArtist] = item.subtitle
            lastUpdatedSongId = nil
        }
        
        if let currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo {
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = currentInfo[MPNowPlayingInfoPropertyPlaybackRate]
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        } else {
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        }
        #if os(iOS)
        Self.applyBrandArtworkToNowPlayingInfo(&nowPlayingInfo)
        #endif

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    func seek(to seconds: Double) {
        guard let player = player else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 1000)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        self.currentTime = seconds
        updatePlaybackRate(isPlaying ? 1.0 : 0.0)
        
        if !isLive && currentItem != nil {
            updateNowPlayingForArchive()
        }
    }

    public func skipNext() {
        guard let player = player, let playlist = currentPlaylist else { return }
        let currentTime = player.currentTime().seconds
        
        if let nextSong = playlist.first(where: { Double($0.time) > currentTime + 1 }) {
            seek(to: Double(nextSong.time))
        }
    }

    public func skipPrevious() {
        guard let player = player, let playlist = currentPlaylist else { return }
        let currentTime = player.currentTime().seconds
        
        // If we are more than 3 seconds into a song, jump to the start of that song
        // Otherwise jump to the previous song
        let currentSongIndex = playlist.lastIndex(where: { Double($0.time) <= currentTime + 1 }) ?? 0
        
        if currentTime > Double(playlist[currentSongIndex].time) + 3 {
            seek(to: Double(playlist[currentSongIndex].time))
        } else if currentSongIndex > 0 {
            seek(to: Double(playlist[currentSongIndex - 1].time))
        } else {
            seek(to: 0)
        }
    }
    
    public func playLive(streamType: StreamType) async {
        #if os(iOS)
        let online = await NetworkPathProbe.isPathSatisfied()
        if !online {
            userFacingPlaybackError = "Keine Internetverbindung. Der Livestream kann nicht gestartet werden."
            return
        }
        #endif
        userFacingPlaybackError = nil
        isLive = true
        currentItem = nil
        currentPlaylist = nil
        duration = 0
        currentTime = 0
        currentStreamType = streamType
        guard let url = streamType.streamURL else { return }

        play(url: url, startAt: 0)

        // Initial setup for now playing, will be updated by metadata poll
        setupNowPlayingLive()
        updatePlaybackRate(1.0)
    }

    public func clearPlaybackError() {
        userFacingPlaybackError = nil
    }

    private func handleStreamOrPlaybackFailure(wasLive: Bool, error: Error?) {
        let detail = error?.localizedDescription ?? ""
        if wasLive {
            userFacingPlaybackError = "Livestream konnte nicht gestartet werden. Prüfe deine Internetverbindung.\(detail.isEmpty ? "" : " (\(detail))")"
            isLive = false
            currentStreamType = nil
        } else {
            userFacingPlaybackError = "Wiedergabe fehlgeschlagen.\(detail.isEmpty ? "" : " \(detail)")"
        }
        isPlaying = false
        player?.pause()
        updatePlaybackRate(0.0)
    }
    
    func updateNowPlayingWithMetadata(_ metadata: LiveMetadataResponse?) {
        guard isLive, let streamType = currentStreamType else { return }
        
        var nowPlayingInfo = [String: Any]()
        
        let tracks = metadata?.tracks[streamType.rawValue] ?? []
        let currentTrack = tracks.first?.decodedBasicHTMLEntities ?? streamType.displayName
        let currentShow = metadata?.currentShowTitle[streamType.rawValue] ?? "BiteFM Live"
        
        nowPlayingInfo[MPMediaItemPropertyTitle] = currentTrack
        nowPlayingInfo[MPMediaItemPropertyArtist] = currentShow
        #if os(iOS)
        Self.applyBrandArtworkToNowPlayingInfo(&nowPlayingInfo)
        #endif

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func play(url: URL, startAt: Double = 0) {
        userFacingPlaybackError = nil
        if let oldPlayer = player {
            oldPlayer.removeObserver(self, forKeyPath: "timeControlStatus")
            oldPlayer.removeObserver(self, forKeyPath: "status")
            oldPlayer.currentItem?.removeObserver(self, forKeyPath: "status")
            oldPlayer.currentItem?.removeObserver(self, forKeyPath: "duration")
            if let oldItem = oldPlayer.currentItem {
                NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: oldItem)
                NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: oldItem)
            }
        }
        
        duration = 0 // Reset duration for new item
        currentTime = startAt // Reset current time to startAt for new item
        lastSavedPosition = startAt
        
        let playerItem = AVPlayerItem(url: url)
        if player == nil {
            player = AVPlayer(playerItem: playerItem)
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }
        
        // Seek to start position if needed
        if startAt > 0 {
            let time = CMTime(seconds: startAt, preferredTimescale: 1000)
            player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        
        player?.addObserver(self, forKeyPath: "timeControlStatus", options: [.new], context: nil)
        player?.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
        playerItem.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
        playerItem.addObserver(self, forKeyPath: "duration", options: [.new], context: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(handlePlaybackError), name: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePlaybackEnded), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        
        setupTimeObserver()
        player?.play()
        isPlaying = true
        isStalled = false
    }
    
    @objc private func handlePlaybackError(notification: Notification) {
        if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
            LogManager.shared.log("Playback failed with error: \(error.localizedDescription)", type: .error)
            Task { @MainActor in
                handleStreamOrPlaybackFailure(wasLive: isLive, error: error)
            }
        }
    }
    
    @objc private func handlePlaybackEnded(notification: Notification) {
        Task { @MainActor in
            guard let item = self.currentItem, !self.isLive else { return }
            self.clearStoredPlaybackPosition(for: item.terminID)
            self.hasMarkedCurrentItemAsPlayed = true
            self.lastMarkedTerminID = item.terminID
            // Hörhistorie vom Server laden — UI aktualisiert sich über `listenedShowIDs`.
            await APIClient.shared.markAsPlayed(item: item)
        }
    }
    
    private func clearStoredPlaybackPosition(for terminID: Int) {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        do {
            let descriptor = FetchDescriptor<StoredPlaybackPosition>(predicate: #Predicate<StoredPlaybackPosition> { $0.terminID == terminID })
            if let existing = try context.fetch(descriptor).first {
                context.delete(existing)
                try context.save()
            }
            lastSavedPosition = 0
        } catch {
            // Silently fail
        }
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        updatePlaybackRate(0.0)
        savePlaybackPosition()
    }
    
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            userFacingPlaybackError = nil
            player?.play()
            isPlaying = true
            updatePlaybackRate(1.0)
        }
    }
    
    private func setupRemoteTransportControls() {
        guard !didSetupRemoteTransportControls else { return }
        didSetupRemoteTransportControls = true

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        
        playCommandToken = commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.userFacingPlaybackError = nil
                self.player?.play()
                self.isPlaying = true
                self.updatePlaybackRate(1.0)
            }
            return .success
        }

        pauseCommandToken = commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.pause()
            }
            return .success
        }

        togglePlayPauseCommandToken = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.togglePlayPause()
            }
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        nextTrackCommandToken = commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.skipNext()
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        previousTrackCommandToken = commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.skipPrevious()
            return .success
        }
    }
    
    private func setupNowPlayingLive() {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = "BiteFM Live"
        nowPlayingInfo[MPMediaItemPropertyArtist] = "Radio für gute Musik"
        #if os(iOS)
        Self.applyBrandArtworkToNowPlayingInfo(&nowPlayingInfo)
        #endif

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func setupNowPlaying(item: ArchiveItem) {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = item.sendungTitel
        nowPlayingInfo[MPMediaItemPropertyArtist] = item.subtitle
        #if os(iOS)
        Self.applyBrandArtworkToNowPlayingInfo(&nowPlayingInfo)
        #endif

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func updatePlaybackRate(_ rate: Float) {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { 
            var newInfo = [String: Any]()
            newInfo[MPNowPlayingInfoPropertyPlaybackRate] = rate
            #if os(iOS)
            Self.applyBrandArtworkToNowPlayingInfo(&newInfo)
            #endif
            MPNowPlayingInfoCenter.default().nowPlayingInfo = newInfo
            #if os(macOS)
            MPNowPlayingInfoCenter.default().playbackState = rate > 0 ? .playing : .paused
            #endif
            return 
        }
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = rate
        if let player {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = rate > 0 ? .playing : .paused
        #endif
    }
}


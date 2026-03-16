import Foundation
import AVFoundation
import MediaPlayer
import SwiftData

@MainActor
class AudioPlayerManager: NSObject, ObservableObject {
    static let shared = AudioPlayerManager()
    
    private var player: AVPlayer?
    private var didSetupRemoteTransportControls = false
    private var playCommandToken: Any?
    private var pauseCommandToken: Any?
    private var togglePlayPauseCommandToken: Any?
    private var nextTrackCommandToken: Any?
    private var previousTrackCommandToken: Any?
    @Published var isPlaying = false
    @Published var isStalled = false
    @Published var currentItem: ArchiveItem?
    @Published var currentPlaylist: [PlaylistItem]?
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isLive = false
    @Published var currentStreamType: StreamType?
    
    private var hasMarkedCurrentItemAsPlayed = false
    private var lastMarkedTerminID: Int?
    
    var modelContainer: ModelContainer?
    
    private var timeObserver: Any?
    private var lastUpdatedSongId: String?
    private var lastSavedPosition: Double = 0
    
    override init() {
        super.init()
        setupAudioSession()
        MPNowPlayingInfoCenter.default().playbackState = .stopped
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
        #endif
    }
    
    func play(item: ArchiveItem, playlist: [PlaylistItem]? = nil, initialPosition: Double? = nil) {
        isLive = false
        currentStreamType = nil
        lastUpdatedSongId = nil
        hasMarkedCurrentItemAsPlayed = lastMarkedTerminID == item.terminID
        
        // Save previous item's position if any
        if let _ = currentItem {
            savePlaybackPosition()
        }
        
        // If we don't have an audio file, we MUST fetch detail first
        if item.audioFile1.isEmpty {
            Task {
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
        
        self.currentItem = item
        self.currentPlaylist = playlist

        Task {
            // Use initialPosition if provided, otherwise load saved position
            let startAt: Double
            if let initialPosition = initialPosition {
                startAt = initialPosition
            } else {
                startAt = await self.loadPlaybackPosition(for: item.terminID) ?? 0
            }
            
            self.play(url: url, startAt: startAt)
            
            setupNowPlaying(item: item)
            updatePlaybackRate(1.0)
            
            // Fetch playlist in background if not provided
            if playlist == nil {
                if let detail = await APIClient.shared.fetchBroadcastDetail(for: item) {
                    // Only update if we're still playing the same item
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
                self.currentTime = time.seconds
                
                // Mark as played if we've listened for more than 15 seconds
                if !self.isLive, let item = self.currentItem, !self.hasMarkedCurrentItemAsPlayed {
                    // Check if we've been playing for at least 15 seconds or are significantly through
                    // (Handle cases where saved position starts at the very end, but usually 15s is good)
                    if time.seconds > 15.0 {
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

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
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
                }
            } else if let item = object as? AVPlayerItem {
                if item.status == .failed {
                    LogManager.shared.log("AVPlayerItem failed with error: \(String(describing: item.error))", type: .error)
                }
            }
        } else if keyPath == "duration", let item = object as? AVPlayerItem {
            DispatchQueue.main.async {
                let durationSeconds = item.duration.seconds
                if durationSeconds.isFinite {
                    self.duration = durationSeconds
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

    func skipNext() {
        guard let player = player, let playlist = currentPlaylist else { return }
        let currentTime = player.currentTime().seconds
        
        if let nextSong = playlist.first(where: { Double($0.time) > currentTime + 1 }) {
            seek(to: Double(nextSong.time))
        }
    }

    func skipPrevious() {
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
    
    func playLive(streamType: StreamType) {
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
    
    func updateNowPlayingWithMetadata(_ metadata: LiveMetadataResponse?) {
        guard isLive, let streamType = currentStreamType else { return }
        
        var nowPlayingInfo = [String: Any]()
        
        let tracks = metadata?.tracks[streamType.rawValue] ?? []
        let currentTrack = tracks.first?.unescapedHTML ?? streamType.displayName
        let currentShow = metadata?.currentShowTitle[streamType.rawValue] ?? "BiteFM Live"
        
        nowPlayingInfo[MPMediaItemPropertyTitle] = currentTrack
        nowPlayingInfo[MPMediaItemPropertyArtist] = currentShow
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func play(url: URL, startAt: Double = 0) {
        if let oldPlayer = player {
            oldPlayer.removeObserver(self, forKeyPath: "timeControlStatus")
            oldPlayer.removeObserver(self, forKeyPath: "status")
            oldPlayer.currentItem?.removeObserver(self, forKeyPath: "status")
            oldPlayer.currentItem?.removeObserver(self, forKeyPath: "duration")
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: oldPlayer.currentItem)
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
        }
    }
    
    @objc private func handlePlaybackEnded(notification: Notification) {
        // Clear saved position when finished
        guard let item = currentItem, !isLive, let container = modelContainer else { return }
        let terminID = item.terminID
        let context = ModelContext(container)
        
        Task {
            do {
                let descriptor = FetchDescriptor<StoredPlaybackPosition>(predicate: #Predicate<StoredPlaybackPosition> { $0.terminID == terminID })
                if let existing = try context.fetch(descriptor).first {
                    context.delete(existing)
                    try context.save()
                    lastSavedPosition = 0
                }
            } catch {
                // Silently fail
            }
        }
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        updatePlaybackRate(0.0)
        savePlaybackPosition()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            player?.play()
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
            self.player?.play()
            return .success
        }
        
        pauseCommandToken = commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.player?.pause()
            return .success
        }

        togglePlayPauseCommandToken = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.togglePlayPause()
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
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func setupNowPlaying(item: ArchiveItem) {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = item.sendungTitel
        nowPlayingInfo[MPMediaItemPropertyArtist] = item.subtitle
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func updatePlaybackRate(_ rate: Float) {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { 
            var newInfo = [String: Any]()
            newInfo[MPNowPlayingInfoPropertyPlaybackRate] = rate
            MPNowPlayingInfoCenter.default().nowPlayingInfo = newInfo
            MPNowPlayingInfoCenter.default().playbackState = rate > 0 ? .playing : .paused
            return 
        }
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = rate
        if let player {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        MPNowPlayingInfoCenter.default().playbackState = rate > 0 ? .playing : .paused
    }
}

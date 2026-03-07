import Foundation
import AVFoundation
import MediaPlayer

@MainActor
class AudioPlayerManager: ObservableObject {
    static let shared = AudioPlayerManager()
    
    private var player: AVPlayer?
    private var didSetupRemoteTransportControls = false
    private var playCommandToken: Any?
    private var pauseCommandToken: Any?
    @Published var isPlaying = false
    @Published var currentItem: ArchiveItem?
    
    init() {
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        setupRemoteTransportControls()
    }
    
    func play(item: ArchiveItem) {
        let baseUrlString = "https://archiv.bytefm.com/" 
        guard let url = URL(string: baseUrlString + item.audioFile1) else { return }
        
        if player == nil {
            player = AVPlayer(url: url)
        } else {
            let playerItem = AVPlayerItem(url: url)
            player?.replaceCurrentItem(with: playerItem)
        }
        
        player?.play()
        isPlaying = true
        currentItem = item

        setupNowPlaying(item: item)
        updatePlaybackRate(1.0)
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        updatePlaybackRate(0.0)
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
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
            if !self.isPlaying {
                self.player?.play()
                self.isPlaying = true
                self.updatePlaybackRate(1.0)
                return .success
            }
            return .commandFailed
        }
        
        pauseCommandToken = commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.isPlaying {
                self.player?.pause()
                self.isPlaying = false
                self.updatePlaybackRate(0.0)
                return .success
            }
            return .commandFailed
        }
    }
    
    private func setupNowPlaying(item: ArchiveItem) {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = item.sendungTitel
        nowPlayingInfo[MPMediaItemPropertyArtist] = item.subtitle
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func updatePlaybackRate(_ rate: Float) {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = rate
        if let player {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        MPNowPlayingInfoCenter.default().playbackState = rate > 0 ? .playing : .paused
    }
}

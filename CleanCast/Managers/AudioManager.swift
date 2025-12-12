import SwiftUI
import AVFoundation
import SwiftData

@Observable
class AudioManager {
    static let shared = AudioManager()
    
    var currentEpisode: Episode?
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    private var timeObserver: Any?
    
    private var player = AVPlayer()
    
    // Persistence Key
    private let lastPlayedKey = "lastPlayedEpisodeURL"
    
    func play(episode: Episode) {
        if currentEpisode?.id == episode.id {
            if !isPlaying {
                player.play()
                isPlaying = true
            }
            return
        }
        
        // Check for local download first
        let url: URL
        if episode.isDownloaded, let path = episode.localFilePath {
             // Validate file existence
             if FileManager.default.fileExists(atPath: path) {
                 url = URL(fileURLWithPath: path)
                 print("AudioManager: Playing local file: \(path)")
             } else {
                 print("AudioManager: Local file missing, falling back to restart/redownload if possible")
                 // Fallback to remote if possible
                 if let remoteUrl = URL(string: episode.url) {
                      url = remoteUrl
                 } else { return }
             }
        } else {
             guard let remoteUrl = URL(string: episode.url) else {
                print("AudioManager Error: Invalid URL string: \(episode.url)")
                return
            }
            url = remoteUrl
            print("AudioManager: Streaming URL: \(remoteUrl.absoluteString)")
        }
        
        print("AudioManager: Playing episode: \(episode.title)")

        currentEpisode = episode
        isPlaying = true
        
        // Save state
        UserDefaults.standard.set(episode.url, forKey: lastPlayedKey)
        
        let playerItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: playerItem)
        
        // Restore progress if needed (though seek checks current time)
        if episode.progress > 0 && episode.progress < episode.duration * 0.95 {
             let cmTime = CMTime(seconds: episode.progress, preferredTimescale: 1)
             player.seek(to: cmTime)
        }

        player.play()
        
        setupTimeObserver()
    }
    
    func pause() {
        player.pause()
        isPlaying = false
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if let currentEpisode {
            play(episode: currentEpisode)
        } else {
            // Resume if nothing selected?
            if player.currentItem != nil {
                player.play()
                isPlaying = true
            }
        }
    }
    
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1)
        player.seek(to: cmTime)
    }
    
    // Resume session from disk
    func restoreSession(context: ModelContext) {
        guard let urlString = UserDefaults.standard.string(forKey: lastPlayedKey) else { return }
        
        do {
            var descriptor = FetchDescriptor<Episode>(
                predicate: #Predicate { $0.url == urlString }
            )
            descriptor.fetchLimit = 1
            
            if let episode = try context.fetch(descriptor).first {
                print("AudioManager: Restoring session for \(episode.title)")
                self.currentEpisode = episode
                self.currentTime = episode.progress
                self.duration = episode.duration
                self.isPlaying = false
                
                // Do NOT auto-play. Just prepare the UI.
                // Optionally prepare the player item in paused state:
                 // Check for local download first
                 let url: URL?
                 if episode.isDownloaded, let path = episode.localFilePath {
                      if FileManager.default.fileExists(atPath: path) {
                          url = URL(fileURLWithPath: path)
                      } else { url = URL(string: episode.url) }
                 } else {
                      url = URL(string: episode.url)
                 }
                 
                 if let validUrl = url {
                     let playerItem = AVPlayerItem(url: validUrl)
                     player.replaceCurrentItem(with: playerItem)
                     let cmTime = CMTime(seconds: episode.progress, preferredTimescale: 1)
                     player.seek(to: cmTime)
                 }
            }
        } catch {
            print("AudioManager: Failed to restore session: \(error)")
        }
    }
    
    private func setupTimeObserver() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            if let duration = self.player.currentItem?.duration.seconds, !duration.isNaN {
                self.duration = duration
                
                // Update Model state
                if let episode = self.currentEpisode {
                    episode.progress = self.currentTime
                    episode.duration = self.duration // Update duration from actual audio file if valid
                    
                    // Mark as in-progress or played
                    if self.currentTime >= self.duration * 0.95 {
                         episode.playStateRaw = 2 // Played
                    } else {
                         episode.playStateRaw = 1 // In Progress
                    }
                }
            }
        }
    }
}

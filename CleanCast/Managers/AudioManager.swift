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
    
    private init() {
        configureAudioSession()
    }
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
            print("AudioManager: Audio session configured successfully")
        } catch {
            print("AudioManager: Failed to configure audio session: \(error)")
        }
    }
    
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
             let cmTime = CMTime(seconds: episode.progress, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
             player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        player.play()
        setupTimeObserver()
        
        // Trigger Groq Ad Detection (fire and forget)
        Task {
            if episode.adSegments?.isEmpty ?? true, episode.adDetectionStatus != "completed", episode.adDetectionStatus != "processing" {
                if URL(string: episode.url) != nil {
                    let context = EpisodeDetectionContext(
                        id: episode.id,
                        title: episode.title,
                        audioURL: episode.url,
                        isDownloaded: episode.isDownloaded,
                        localFilePath: episode.localFilePath
                    )
                    
                    do {
                         // Check first 5 minutes (300 seconds) for intro ads
                         // This is fast (~5s) because it only processes a small chunk
                         _ = try await AdDetectionService.shared.analyzeChunk(
                            context: context, 
                            startTime: 0, 
                            duration: 300, 
                            episode: episode
                         )
                         
                         // If ad detected at the very start (0s), we might want to skip it?
                         // UI will show it. Ad skipping logic resides in detecting playback time.
                    } catch {
                        print("AudioManager: Ad detection failed: \(error)")
                    }
                }
            }
        }
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
    
    private var isSeeking: Bool = false
    
    func seek(to time: TimeInterval) {
        // Prevent multiple simultaneous seeks
        guard !isSeeking else { return }
        
        // Clamp time to valid range
        let clampedTime = max(0, min(time, duration > 0 ? duration : time))
        
        // Skip seek if already very close to target (prevents unnecessary seeks)
        if abs(clampedTime - currentTime) < 0.2 {
            return
        }
        
        isSeeking = true
        currentTime = clampedTime // Update immediately for UI responsiveness
        
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        // Use small tolerance for smoother seeking (zero tolerance can cause audio glitches)
        player.seek(to: cmTime, toleranceBefore: CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), 
                    toleranceAfter: CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))) { [weak self] finished in
            DispatchQueue.main.async {
                self?.isSeeking = false
                if finished {
                    // Let time observer take over from here
                }
            }
        }
    }
    
    // Resume session from disk
    func restoreSession(context: ModelContext) {
        guard let urlString = UserDefaults.standard.string(forKey: lastPlayedKey) else { return }
        
        Task { @MainActor in
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
                    
                    // Prepare player asynchronously to avoid blocking UI startup
                    let url: URL?
                    if episode.isDownloaded, let path = episode.localFilePath, FileManager.default.fileExists(atPath: path) {
                         url = URL(fileURLWithPath: path)
                    } else {
                         url = URL(string: episode.url)
                    }
                    
                    if let validUrl = url {
                        let playerItem = AVPlayerItem(url: validUrl)
                        self.player.replaceCurrentItem(with: playerItem)
                        
                        // Seek to saved position with high tolerance for performance (snap to nearest keyframe)
                        if episode.progress > 0 {
                            let cmTime = CMTime(seconds: episode.progress, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                            // Use positiveInfinity tolerance for fastest seek (no decoding required)
                            self.player.seek(to: cmTime, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
                        }
                        
                        // Set up time observer so slider works even when paused
                        self.setupTimeObserver()
                    }
                }
            } catch {
                print("AudioManager: Failed to restore session: \(error)")
            }
        }
    }
    
    private var lastModelUpdateTime: TimeInterval = 0
    private let modelUpdateInterval: TimeInterval = 5.0 // Update model every 5 seconds
    
    private func setupTimeObserver() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Use reasonable interval to avoid audio system overload
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, !self.isSeeking else { return }
            
            let newTime = time.seconds
            guard !newTime.isNaN && !newTime.isInfinite && newTime >= 0 else { return }
            
            self.currentTime = newTime
            
            // Update duration if available and valid (only check occasionally)
            if let itemDuration = self.player.currentItem?.duration.seconds,
               !itemDuration.isNaN && !itemDuration.isInfinite && itemDuration > 0,
               abs(self.duration - itemDuration) > 0.5 {
                self.duration = itemDuration
            }
            
            // Only update model state periodically to avoid performance issues
            let timeSinceLastUpdate = abs(newTime - self.lastModelUpdateTime)
            if timeSinceLastUpdate >= self.modelUpdateInterval, let episode = self.currentEpisode {
                self.lastModelUpdateTime = newTime
                episode.progress = newTime
                
                // Update duration if it changed significantly
                if abs(episode.duration - self.duration) > 1.0 {
                    episode.duration = self.duration
                }
                
                // Mark as in-progress or played
                if self.duration > 0 && newTime >= self.duration * 0.95 {
                    episode.playStateRaw = 2 // Played
                } else if newTime > 0 {
                    episode.playStateRaw = 1 // In Progress
                }
            }
        }
    }
}

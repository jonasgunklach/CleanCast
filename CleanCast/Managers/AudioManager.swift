
import SwiftUI
import AVFoundation
import SwiftData
import MediaPlayer

@Observable
class AudioManager {
    static let shared = AudioManager()
    
    var currentEpisode: Episode?
    var upNextQueue: [Episode] = []
    var isPlaying: Bool = false
    var isBuffering: Bool = false  // Loading state while detecting ads
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    private var timeObserver: Any?
    
    // Playback Rate
    var playbackRate: Float = 1.0 {
        didSet {
            if isPlaying {
                player.rate = playbackRate
            }
            updateNowPlayingInfo()
        }
    }
    
    // Sleep Timer
    var sleepTimer: Timer?
    var sleepTimerEndDate: Date?
    
    private var player = AVPlayer()
    
    // Persistence Key
    private let lastPlayedKey = "lastPlayedEpisodeURL"
    
    private init() {
        configureAudioSession()
        setupRemoteTransportControls()
        
        // Add end of playback observer
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
            print("AudioManager: Audio session configured successfully")
            
            // Listen for audio interruptions (calls, Siri, other apps)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioInterruption),
                name: AVAudioSession.interruptionNotification,
                object: session
            )
            
            // Listen for route changes (headphones unplugged, Bluetooth disconnect)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRouteChange),
                name: AVAudioSession.routeChangeNotification,
                object: session
            )
        } catch {
            print("AudioManager: Failed to configure audio session: \(error)")
        }
    }
    
    /// Handle audio interruptions (phone calls, Siri, other audio apps)
    @objc private func handleAudioInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // Audio was interrupted - pause playback
            print("AudioManager: Audio interrupted (call/Siri/other app)")
            // Player auto-pauses, but update our state
            isPlaying = false
            updateNowPlayingInfo()
            
        case .ended:
            // Interruption ended - check if we should resume
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            if options.contains(.shouldResume) {
                // System says we should resume playback
                print("AudioManager: Interruption ended, resuming playback")
                
                // Small delay to let the system settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.player.play()
                    self?.player.rate = self?.playbackRate ?? 1.0
                    self?.isPlaying = true
                    self?.updateNowPlayingInfo()
                }
            } else {
                print("AudioManager: Interruption ended, not resuming (shouldResume = false)")
            }
            
        @unknown default:
            break
        }
    }
    
    /// Handle audio route changes (headphones unplugged)
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones were unplugged - pause playback (standard iOS behavior)
            print("AudioManager: Audio route changed (device disconnected), pausing")
            player.pause()
            isPlaying = false
            updateNowPlayingInfo()
            
        case .newDeviceAvailable:
            // New device connected (e.g., headphones plugged in) - no auto-resume
            print("AudioManager: New audio device available")
            
        default:
            break
        }
    }

    // MARK: - System Integration
    
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play/Pause
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if !self.isPlaying {
                self.togglePlayPause()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.isPlaying {
                self.pause()
                return .success
            }
            return .commandFailed
        }
        
        // Skip Intervals
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            self.seek(to: self.currentTime - interval)
            return .success
        }
        
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 30
            self.seek(to: self.currentTime + interval)
            return .success
        }
        
        // Scrubbing
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: event.positionTime)
            return .success
        }
        
        // Next Track (Queue)
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self, !self.upNextQueue.isEmpty else { return .commandFailed }
            self.playNext()
            return .success
        }
    }
    
    private var currentArtwork: MPMediaItemArtwork?
    private var currentArtworkUrl: URL?

    func updateNowPlayingInfo() {
        guard let episode = currentEpisode else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            currentArtwork = nil
            currentArtworkUrl = nil
            return
        }
        
        // Start with existing info to preserve artwork while we update metadata
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
        
        // Update Metadata
        nowPlayingInfo[MPMediaItemPropertyTitle] = episode.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = episode.podcast?.title ?? "CleanCast"
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0
        
        // Handle Artwork
        if let url = episode.podcast?.imageURL {
            if url != currentArtworkUrl {
                // New artwork needed
                currentArtworkUrl = url
                currentArtwork = nil // Clear old while loading
                
                Task {
                    if let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) {
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        
                        await MainActor.run {
                            // Verify we're still playing the same thing
                            if self.currentArtworkUrl == url {
                                self.currentArtwork = artwork
                                
                                // Apply the new artwork to the live info
                                var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
                                currentInfo[MPMediaItemPropertyArtwork] = artwork
                                MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
                            }
                        }
                    }
                }
            } else if let artwork = currentArtwork {
                // Use cached artwork
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
            }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    // MARK: - Queue Management
    
    func play(episode: Episode, queue: [Episode] = []) {
        if currentEpisode?.id == episode.id {
            if !isPlaying {
                player.playImmediately(atRate: playbackRate)
                isPlaying = true
                updateNowPlayingInfo()
            }
            return
        }
        
        // Update queue if provided (replacing existing "context" queue)
        if !queue.isEmpty {
            // Remove the playing episode from the queue if present
            self.upNextQueue = queue.filter { $0.id != episode.id }
        }
        
        startPlayback(for: episode)
    }
    
    func addToQueue(_ episode: Episode, next: Bool = false) {
        guard episode.id != currentEpisode?.id else { return }
        
        // Remove if already in queue to avoid duplicates
        upNextQueue.removeAll { $0.id == episode.id }
        
        if next {
            upNextQueue.insert(episode, at: 0)
        } else {
            upNextQueue.append(episode)
        }
    }
    
    func removeFromQueue(at offsets: IndexSet) {
        upNextQueue.remove(atOffsets: offsets)
    }
    
    func moveInQueue(from source: IndexSet, to destination: Int) {
        upNextQueue.move(fromOffsets: source, toOffset: destination)
    }
    
    func playNext() {
        guard !upNextQueue.isEmpty else {
            // Queue empty, stop playback
            pause()
            return
        }
        
        let nextEpisode = upNextQueue.removeFirst()
        startPlayback(for: nextEpisode)
    }
    
    @objc private func playerDidFinishPlaying(note: NSNotification) {
        print("AudioManager: Playback finished")
        
        // Mark current as played completely
        if let episode = currentEpisode {
             episode.playStateRaw = 2 // Played
             episode.progress = episode.duration
        }
        
        // Play next in queue
        if !upNextQueue.isEmpty {
            playNext()
        } else {
            isPlaying = false
            player.seek(to: .zero) // Reset to start if purely done
            updateNowPlayingInfo()
        }
    }
    
    // MARK: - Internal Playback Logic
    
    private func startPlayback(for episode: Episode) {
        // Check for local download first
        let url: URL
        if episode.isDownloaded, let path = episode.localFilePath {
             // Validate file existence
             if FileManager.default.fileExists(atPath: path) {
                 url = URL(fileURLWithPath: path)
                 print("AudioManager: Playing local file: \(path)")
             } else {
                 print("AudioManager: Local file missing, falling back to restart/redownload if possible")
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
        lastSkippedAdEnd = -1 // Reset ad skip tracking for new episode
        
        // Save state
        UserDefaults.standard.set(episode.url, forKey: lastPlayedKey)
        
        let playerItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: playerItem)
        
        // Restore progress if needed (though seek checks current time)
        if episode.progress > 0 && episode.progress < episode.duration * 0.95 {
             let cmTime = CMTime(seconds: episode.progress, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
             player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        // Determine if we need to block for ad detection
        // Logic: If Intro window (index 0) exists and is DONE, we are good.
        // If not, we block.
        let windows = episode.windowRecords ?? []
        let introWindow = windows.first(where: { $0.windowIndex == 0 })
        let isIntroDone = introWindow?.status == "done"
        
        // Only block if we have NO intro done and Settings say we should skip (implied logic)
        let needsBlockingWait = !isIntroDone && (episode.adSegments?.isEmpty ?? true)
        
        let context = EpisodeDetectionContext(
            id: episode.id,
            title: episode.title,
            audioURL: episode.url,
            isDownloaded: episode.isDownloaded,
            localFilePath: episode.localFilePath
        )
        
        if needsBlockingWait {
            // BLOCKING FLOW: Wait for ad detection before playback
            isBuffering = true
            print("AudioManager: 🛑 Blocking playback - detecting ads in intro window...")
            
            Task {
                // Check first 5 minutes (Intro) - THIS BLOCKS
                await AdDetectionService.shared.analyzeEpisode(context: context, episode: episode, currentPlayhead: 0)
                print("AudioManager: ✅ Ad detection complete/timeout. Starting playback.")
                
                // Clear buffering state and START PLAYING
                await MainActor.run {
                    self.isBuffering = false
                    self.isPlaying = true
                    self.player.playImmediately(atRate: self.playbackRate)
                    self.setupTimeObserver()
                    self.updateNowPlayingInfo()
                    
                    // Skip to after first ad if one was detected at the start
                    if let segments = episode.adSegments, !segments.isEmpty {
                        if let firstAd = segments.first, firstAd.startTime < 5 {
                            print("AudioManager: ⏭️ Skipping intro ad (0-\(firstAd.endTime)s)")
                            let skipTo = CMTime(seconds: firstAd.endTime + 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                            self.player.seek(to: skipTo, toleranceBefore: .zero, toleranceAfter: .zero)
                        }
                    }
                }
            }
        } else {
            // NORMAL FLOW: Play immediately
            isPlaying = true
            player.playImmediately(atRate: playbackRate)
            setupTimeObserver()
            updateNowPlayingInfo()
            
            // Trigger background processing for progressive windows
            print("AudioManager: 🔄 Triggering progressive ad detection...")
            Task.detached {
                await AdDetectionService.shared.analyzeEpisode(context: context, episode: episode, currentPlayhead: episode.progress)
            }
            
            // Skip to after first ad if one was detected at the start
            if let segments = episode.adSegments, !segments.isEmpty {
                if let firstAd = segments.first, firstAd.startTime < 5 {
                    print("AudioManager: ⏭️ Skipping intro ad (0-\(firstAd.endTime)s)")
                    let skipTo = CMTime(seconds: firstAd.endTime + 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                    player.seek(to: skipTo, toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
        }
    }
    
    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
        invalidateSleepTimer() // Cancel timer when manually paused
    }
    
    func startSleepTimer(minutes: Int) {
        invalidateSleepTimer()
        guard minutes > 0 else { return }
        
        let interval = TimeInterval(minutes * 60)
        sleepTimerEndDate = Date().addingTimeInterval(interval)
        
        print("AudioManager: Sleep timer set for \(minutes) minutes")
        
        sleepTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            print("AudioManager: Sleep timer fired. Pausing.")
            self?.togglePlayPause() // Uses existing toggle which handles pause
            self?.sleepTimerEndDate = nil
        }
    }
    
    func invalidateSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerEndDate = nil
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if let currentEpisode {
            play(episode: currentEpisode)
        } else {
            // Resume if nothing selected?
            if player.currentItem != nil {
                player.playImmediately(atRate: playbackRate)
                isPlaying = true
                updateNowPlayingInfo()
            } else if !upNextQueue.isEmpty {
                playNext()
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
        updateNowPlayingInfo() // Optimistic UI update
        
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
                    // Resume background processing if it was paused/in-progress or failed/stuck
                    if episode.adDetectionStatus != "completed" {
                        print("AudioManager: 🔄 Restoring background ad detection (Status: \(episode.adDetectionStatus ?? "nil"))...")
                        let context = EpisodeDetectionContext(
                            id: episode.id,
                            title: episode.title,
                            audioURL: episode.url,
                            isDownloaded: episode.isDownloaded,
                            localFilePath: episode.localFilePath
                        )
                        
                        Task.detached {
                            // 1. Reset any stuck windows from previous session
                            await AdDetectionService.shared.resetStuckWindows(for: episode)
                            
                            // 2. Resume analysis
                            await AdDetectionService.shared.analyzeEpisode(context: context, episode: episode, currentPlayhead: episode.progress)
                        }
                    }
                }
            } catch {
                print("AudioManager: Failed to restore session: \(error)")
            }
        }
    }
    
    private var lastModelUpdateTime: TimeInterval = 0
    private let modelUpdateInterval: TimeInterval = 5.0 // Update model every 5 seconds
    private var lastSkippedAdEnd: TimeInterval = -1 // Track to avoid repeated skips
    
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
            
            // Check if we're entering an ad segment and skip it (based on user preferences)
            if let episode = self.currentEpisode,
               let segments = episode.adSegments {
                let sortedSegments = segments.sorted { $0.startTime < $1.startTime }
                
                for segment in sortedSegments {
                    // Check if we're inside this ad segment (with small buffer)
                    if newTime >= segment.startTime - 0.5 && newTime < segment.endTime {
                        // Check if this ad type should be skipped based on user settings
                        guard SettingsManager.shared.shouldSkip(adType: segment.adType) else {
                            continue // User chose not to skip this type
                        }
                        
                        // Find the furthest end time including adjacent ads (≤15s gap)
                        var finalEndTime = segment.endTime
                        for nextSegment in sortedSegments where nextSegment.startTime > segment.endTime {
                            // If next ad starts within 15s of current end, extend the skip
                            if nextSegment.startTime - finalEndTime <= 15 {
                                // Only extend if this ad type should also be skipped
                                if SettingsManager.shared.shouldSkip(adType: nextSegment.adType) {
                                    finalEndTime = nextSegment.endTime
                                } else {
                                    break // Don't skip past an ad type user wants to hear
                                }
                            } else {
                                break // Gap too large, stop extending
                            }
                        }
                        
                        // Avoid skipping the same ad chain repeatedly
                        if self.lastSkippedAdEnd != finalEndTime {
                            self.lastSkippedAdEnd = finalEndTime
                            let typeLabel = segment.adType ?? "ad"
                            if finalEndTime != segment.endTime {
                                print("AudioManager: ⏭️ Skipping \(typeLabel) chain at \(String(format: "%.0f", segment.startTime))-\(String(format: "%.0f", finalEndTime))s (merged)")
                            } else {
                                print("AudioManager: ⏭️ Skipping \(typeLabel) at \(String(format: "%.0f", segment.startTime))-\(String(format: "%.0f", segment.endTime))s")
                            }
                            let skipTo = CMTime(seconds: finalEndTime + 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                            self.player.seek(to: skipTo, toleranceBefore: .zero, toleranceAfter: .zero)
                        }
                        break
                    }
                }
            }
            
            // Update duration if available and valid (only check occasionally)
            if let itemDuration = self.player.currentItem?.duration.seconds,
               !itemDuration.isNaN && !itemDuration.isInfinite && itemDuration > 0,
               abs(self.duration - itemDuration) > 0.5 {
                self.duration = itemDuration
            }
            
            // Update lock screen info periodically (every second)
            // This ensures the slider moves on the lock screen
            if Int(newTime) % 1 == 0 {
                self.updateNowPlayingInfo()
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
                
                // Track usage stats
                if self.isPlaying {
                     episode.podcast?.totalListenedDuration += timeSinceLastUpdate
                }
                
                // Save context occasionally
                 try? episode.modelContext?.save()
                
                // --- Periodic Ad Detection Check (Every 30s) ---
                if Int(newTime) % 30 == 0 {
                    let context = EpisodeDetectionContext(
                        id: episode.id,
                        title: episode.title,
                        audioURL: episode.url,
                        isDownloaded: episode.isDownloaded,
                        localFilePath: episode.localFilePath
                    )
                    Task.detached {
                        // This won't do anything if windows are already processed, very cheap check
                        await AdDetectionService.shared.analyzeEpisode(context: context, episode: episode, currentPlayhead: newTime)
                    }
                }
            }
        }
    }
}

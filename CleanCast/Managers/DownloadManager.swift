import Foundation
import SwiftData

@Observable
class DownloadManager: NSObject {
    static let shared = DownloadManager()
    
    var activeDownloads: Set<UUID> = []
    
    // Track active downloads if needed (simple implementation for now)
    
    func download(episode: Episode) async throws {
        await MainActor.run {
             activeDownloads.insert(episode.id)
        }
        
        defer {
            Task { @MainActor in
                activeDownloads.remove(episode.id)
            }
        }
        
        guard let url = URL(string: episode.url) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "\(episode.id.uuidString).mp3"
        let fileURL = documents.appendingPathComponent(fileName)
        
        try data.write(to: fileURL)
        
        await MainActor.run {
            episode.isDownloaded = true
            episode.localFilePath = fileURL.path
            try? episode.modelContext?.save()
        }
    }
    
    func removeDownload(episode: Episode) {
        guard let path = episode.localFilePath else { return }
        let fileURL = URL(fileURLWithPath: path)
        
        do {
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            print("Error deleting file: \(error)")
        }
        
        episode.isDownloaded = false
        episode.localFilePath = nil
    }
    
    func checkExistingDownloads(for episodes: [Episode]) {
       // logic to verify if files still exist would go here
    }
    
    // Auto Download Logic
    func triggerAutoDownload(for podcasts: [Podcast]) {
        let globalEnabled = UserDefaults.standard.bool(forKey: "autoDownloadNewest")
        let globalLimit = UserDefaults.standard.integer(forKey: "downloadCount")
        let defaultLimit = globalLimit > 0 ? globalLimit : 3
        
        print("DownloadManager: Checking auto-downloads for \(podcasts.count) podcasts...")
        
        for podcast in podcasts {
            if !podcast.isSubscribed {
                print("DownloadManager: Skipping \(podcast.title) - Not subscribed")
                continue
            }
            
            guard let episodes = podcast.episodes else {
                print("DownloadManager: Skipping \(podcast.title) - No episodes")
                continue
            }
            
            // Determine limit: Per-podcast override -> Global Setting
            var effectiveLimit = 0
            
            if let override = podcast.autoDownloadLimit {
                 // Explicit override takes precedence
                 effectiveLimit = override
            } else {
                 // Fallback to global setting
                 if globalEnabled {
                     effectiveLimit = defaultLimit
                 } else {
                     // Auto-download disabled globally and no override
                     print("DownloadManager: Skipping \(podcast.title) - Global disabled and no override")
                     continue
                 }
            }
            
            if effectiveLimit <= 0 {
                print("DownloadManager: Skipping \(podcast.title) - Effective limit is 0")
                continue
            }
            
            // Get unplayed episodes sorted by newest
            // Only consider episodes that are NOT played (playStateRaw == 0) and NOT downloaded
            let sortedEpisodes = episodes.sorted { $0.releaseDate > $1.releaseDate }
            print("DownloadManager: \(podcast.title) - Total episodes: \(sortedEpisodes.count)")
            
            if let topEpisode = sortedEpisodes.first {
                print("DownloadManager: Top episode: \(topEpisode.title) | PlayState: \(topEpisode.playStateRaw) | Downloaded: \(topEpisode.isDownloaded)")
            }

            let candidates = sortedEpisodes
                .filter { $0.playStateRaw != 2 } // 1. Identify all valid candidates (unfinished)
                .prefix(effectiveLimit)          // 2. Take the "Top N" of those
                .filter { !$0.isDownloaded }     // 3. Only download the ones we don't have yet
            
            print("DownloadManager: \(podcast.title) - Found \(candidates.count) candidates (Limit: \(effectiveLimit))")
            
            for episode in candidates {
                print("DownloadManager: Auto-downloading \(episode.title)")
                Task {
                    do {
                        try await download(episode: episode)
                        print("DownloadManager: Successfully downloaded \(episode.title)")
                    } catch {
                        print("DownloadManager: Failed to download \(episode.title) - \(error)")
                    }
                }
            }
        }
    }
}

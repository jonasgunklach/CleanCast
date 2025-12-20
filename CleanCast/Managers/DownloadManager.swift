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
            // Context save handled by caller or view
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
        
        print("DownloadManager: Checking for auto-downloads...")
        
        for podcast in podcasts {
            guard podcast.isSubscribed else { continue }
            guard let episodes = podcast.episodes else { continue }
            
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
                     continue
                 }
            }
            
            if effectiveLimit <= 0 { continue }
            
            // Get unplayed episodes sorted by newest
            let candidates = episodes
                .filter { $0.playStateRaw == 0 && !$0.isDownloaded }
                .sorted { $0.releaseDate > $1.releaseDate }
                .prefix(effectiveLimit)
            
            for episode in candidates {
                print("DownloadManager: Auto-downloading \(episode.title)")
                Task {
                    try? await download(episode: episode)
                }
            }
        }
    }
}

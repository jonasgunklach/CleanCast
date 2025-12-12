import Foundation
import SwiftData

class DownloadManager: NSObject {
    static let shared = DownloadManager()
    
    // Track active downloads if needed (simple implementation for now)
    
    func download(episode: Episode) async throws {
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
}

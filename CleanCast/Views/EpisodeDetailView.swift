
import SwiftUI
import SwiftData

struct EpisodeDetailView: View {
    let episode: Episode
    let artworkColors: ArtworkColors // New property
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioManager.self) private var audioManager
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(\.colorScheme) var colorScheme // Needed for background logic
    
    @State private var isDescriptionExpanded = false
    
    // Derived background color (matching PodcastDetailView)
    private var backgroundColor: Color {
        if colorScheme == .dark {
            return artworkColors.primary.opacity(0.15)
        } else {
            return artworkColors.primary.opacity(0.25)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header: Date and Title
                VStack(alignment: .leading, spacing: 8) {
                    Text(episode.releaseDate.formatted(date: .long, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text(episode.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.leading)
                    
                    if let podcastTitle = episode.podcast?.title {
                        HStack(spacing: 6) {
                            if let url = episode.podcast?.imageURL {
                                AsyncImage(url: url) { image in
                                    image.resizable()
                                        .aspectRatio(contentMode: .fit)
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                }
                                .frame(width: 20, height: 20)
                                .cornerRadius(4)
                            }
                            
                            Text(podcastTitle)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Actions Row
                HStack(spacing: 20) {
                    // Play Button
                    Button {
                        if audioManager.currentEpisode?.id == episode.id && audioManager.isPlaying {
                            audioManager.pause()
                        } else {
                            play(episode)
                        }
                    } label: {
                        HStack {
                            Image(systemName: (audioManager.currentEpisode?.id == episode.id && audioManager.isPlaying) ? "pause.fill" : "play.fill")
                            
                            // Dynamic Text based on state
                            if audioManager.currentEpisode?.id == episode.id && audioManager.isPlaying {
                                // Playing: Show remaining time
                                let left = max(0, episode.duration - episode.progress)
                                Text(format(left))
                            } else if episode.playStateRaw == 2 {
                                // Played: Show total duration (or 0m?) - usually total duration is informative
                                Text(format(episode.duration))
                            } else if episode.playStateRaw == 1 && episode.duration > 0 {
                                // In Progress: Show remaining
                                let left = max(0, episode.duration - episode.progress)
                                Text(format(left))
                            } else {
                                // Unplayed: Show total
                                Text(format(episode.duration))
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(Color(UIColor.systemBackground))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .frame(minWidth: 160) // Ensure it has some width
                        .background(artworkColors.primary) // Use artwork primary
                        .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    // Download
                    Button {
                        toggleDownload(episode)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: episode.isDownloaded ? "arrow.down.circle.fill" : "arrow.down.circle")
                                .font(.title2)
                            //Text(episode.isDownloaded ? "Downloaded" : "Download")
                                //.font(.caption2)
                        }
                    }
                    .foregroundStyle(episode.isDownloaded ? .green : artworkColors.primary)
                    
                    // Save
                    Button {
                        toggleSaved(episode)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: episode.isSaved ? "bookmark.fill" : "bookmark")
                                .font(.title2)
                            //Text(episode.isSaved ? "Saved" : "Save")
                                //.font(.caption2)
                        }
                    }
                    .foregroundStyle(episode.isSaved ? .orange : artworkColors.primary)
                    
                    // Played
                    Button {
                        togglePlayed(episode)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: episode.playStateRaw == 2 ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                            //Text(episode.playStateRaw == 2 ? "Played" : "Unplayed")
                                //.font(.caption2)
                        }
                    }
                    .foregroundStyle(episode.playStateRaw == 2 ? .green : artworkColors.primary)
                }
                .padding(.vertical, 10)
                
                Divider()
                
                // Description
                VStack(alignment: .leading, spacing: 10) {
                    Text("Episode Notes")
                        .font(.headline)
                    
                    Text(sanitizedDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(backgroundColor.ignoresSafeArea()) // Apply background
    }
    
    // Logic (Duplicate from PodcastDetailView mostly, but good to have local for the view)
    private func play(_ episode: Episode) {
        // Simple play for now, queue logic might be needed but starting playback is key
        audioManager.play(episode: episode, queue: [])
    }
    
    private func toggleDownload(_ episode: Episode) {
        if episode.isDownloaded {
            DownloadManager.shared.removeDownload(episode: episode)
        } else {
            Task {
                try? await DownloadManager.shared.download(episode: episode)
            }
        }
    }
    
    private func toggleSaved(_ episode: Episode) {
        episode.isSaved.toggle()
        try? modelContext.save()
    }
    
    private func togglePlayed(_ episode: Episode) {
        if episode.playStateRaw == 2 {
            episode.playStateRaw = 0
            episode.progress = 0
        } else {
            episode.playStateRaw = 2
            episode.progress = episode.duration
        }
        try? modelContext.save()
    }
    
    private var sanitizedDescription: String {
        // 1. Strip HTML tags (simple regex approach)
        let noHtml = episode.desc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
        
        let trimmedTitle = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = noHtml.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 2. Check for Title Prefix (Case Insensitive)
        if let range = trimmedDesc.range(of: trimmedTitle, options: [.caseInsensitive, .anchored]) {
            var rest = String(trimmedDesc[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 3. Strip separators
            let separators = ["-", ":", "–", "—", "|"] // hyphen, colon, en-dash, em-dash, pipe
            
            // Loop to remove multiple separators if present (e.g. " : ")
            // We check only the start
            var foundSeparator = true
            while foundSeparator {
                foundSeparator = false
                if let char = rest.first, separators.contains(String(char)) {
                    rest.removeFirst()
                    foundSeparator = true
                }
                rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            return rest
        }
        
        // Fallback: Return html-stripped description
        return trimmedDesc
    }
    
    private func format(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? ""
    }
}

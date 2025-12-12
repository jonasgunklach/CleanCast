import SwiftUI
import SwiftData

struct AllEpisodesView: View {
    let episodes: [Episode]
    let artworkColors: ArtworkColors
    @Environment(AudioManager.self) private var audioManager
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        List {
            ForEach(episodes) { episode in
                Button {
                    play(episode)
                } label: {
                    EpisodeRow(episode: episode, artworkColors: artworkColors)
                }
                .swipeActions(edge: .trailing) {
                    Button {
                        togglePlayed(episode)
                    } label: {
                        Label(episode.playStateRaw == 2 ? "Mark Unplayed" : "Mark Played",
                              systemImage: episode.playStateRaw == 2 ? "circle" : "checkmark.circle")
                    }
                    .tint(episode.playStateRaw == 2 ? .gray : .green)
                }
                .swipeActions(edge: .leading) {
                    Button {
                        toggleDownload(episode)
                    } label: {
                        Label(episode.isDownloaded ? "Remove" : "Download",
                              systemImage: episode.isDownloaded ? "trash" : "arrow.down.circle")
                    }
                    .tint(episode.isDownloaded ? .red : artworkColors.primary)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(artworkColors.primary.opacity(0.15).ignoresSafeArea())
        .navigationTitle("All Episodes")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func play(_ episode: Episode) {
        audioManager.play(episode: episode)
    }
    
    private func togglePlayed(_ episode: Episode) {
        if episode.playStateRaw == 2 {
            episode.playStateRaw = 0 // Unplayed
        } else {
            episode.playStateRaw = 2 // Played
        }
        try? modelContext.save()
    }
    
    private func toggleDownload(_ episode: Episode) {
        Task {
            if episode.isDownloaded {
                DownloadManager.shared.removeDownload(episode: episode)
            } else {
                try? await DownloadManager.shared.download(episode: episode)
            }
            try? modelContext.save()
        }
    }
}

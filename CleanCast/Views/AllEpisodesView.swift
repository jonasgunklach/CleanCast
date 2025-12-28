import SwiftUI
import SwiftData

struct AllEpisodesView: View {
    let episodes: [Episode]
    let artworkColors: ArtworkColors
    @Environment(AudioManager.self) private var audioManager
    @Environment(\.modelContext) private var modelContext
    
    @State private var filterMode: PodcastDetailView.FilterMode = .all
    @State private var sortOrder: PodcastDetailView.SortOrder = .newestFirst
    
    // Sort logic identical to PodcastDetailView
    private var filteredEpisodes: [Episode] {
        let filtered = episodes.filter { episode in
            switch filterMode {
            case .all: return true
            case .unplayed: return episode.playStateRaw == 0
            case .played: return episode.playStateRaw == 2
            case .downloaded: return episode.isDownloaded
            }
        }
        
        switch sortOrder {
        case .newestFirst:
            return filtered.sorted { $0.releaseDate > $1.releaseDate }
        case .oldestFirst:
            return filtered.sorted { $0.releaseDate < $1.releaseDate }
        }
    }
    
    var body: some View {
        List {
            Section {
                 // Interactive Header
                 HStack {
                     Menu {
                         Section {
                             ForEach(PodcastDetailView.FilterMode.allCases, id: \.self) { mode in
                                 Button {
                                     filterMode = mode
                                 } label: {
                                     if filterMode == mode {
                                         Label(mode.rawValue, systemImage: "checkmark")
                                     } else {
                                         Text(mode.rawValue)
                                     }
                                 }
                             }
                         }
                         
                         Section {
                             Button {
                                 sortOrder = .newestFirst
                             } label: {
                                 if sortOrder == .newestFirst {
                                     Label("Newest First", systemImage: "checkmark")
                                 } else {
                                     Text("Newest First")
                                 }
                             }
                             Button {
                                 sortOrder = .oldestFirst
                             } label: {
                                 if sortOrder == .oldestFirst {
                                     Label("Oldest First", systemImage: "checkmark")
                                 } else {
                                     Text("Oldest First")
                                 }
                             }
                         }
                     } label: {
                         HStack(spacing: 4) {
                             Text(filterMode == .all ? "All Episodes" : filterMode.rawValue)
                                 .font(.system(size: 22, weight: .bold, design: .rounded))
                                 .foregroundStyle(artworkColors.primary)
                                 .fixedSize(horizontal: true, vertical: false)
                                 .animation(.none, value: filterMode)
                             
                             Image(systemName: "chevron.down.circle.fill")
                                 .font(.headline)
                                 .foregroundStyle(artworkColors.primary)
                         }
                     }

                     Spacer()
                     
                     Text("\(filteredEpisodes.count)")
                         .font(.system(size: 15, design: .rounded))
                         .foregroundStyle(.secondary)
                 }
                 .padding(.vertical, 8)
                 .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                 .listRowSeparator(.hidden)
                 .listRowBackground(Color.clear)
            }
            .listSectionSeparator(.hidden)

            ForEach(filteredEpisodes) { episode in
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
        // Auto-fill queue with subsequent episodes from the list
        var queue: [Episode] = []
        if let index = episodes.firstIndex(where: { $0.id == episode.id }) {
            let subsequent = episodes.suffix(from: index + 1)
            queue = Array(subsequent)
        }
        audioManager.play(episode: episode, queue: queue)
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

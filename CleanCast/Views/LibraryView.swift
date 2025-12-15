import SwiftUI
import SwiftData

struct LibraryView: View {
    @State private var sortOption: SortOption = .lastUpdated
    
    enum SortOption {
        case lastUpdated
        case newestSubscribed
        
        var descriptor: SortDescriptor<Podcast> {
            switch self {
            case .lastUpdated:
                return SortDescriptor(\Podcast.lastUpdate, order: .reverse)
            case .newestSubscribed:
                return SortDescriptor(\Podcast.subscribedDate, order: .reverse)
            }
        }
    }

    @State private var selectedTab = 0 // 0: Library, 1: Downloaded, 2: Saved
    @Environment(AudioManager.self) private var audioManager

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Library Section", selection: $selectedTab) {
                    Text("Library").tag(0)
                    Text("Downloaded").tag(1)
                    Text("Saved").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                if selectedTab == 0 {
                    PodcastLibraryGrid(sort: sortOption.descriptor)
                } else if selectedTab == 1 {
                    DownloadedEpisodesList()
                } else {
                    SavedEpisodesList()
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if selectedTab == 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Sort By", selection: $sortOption) {
                                Label("Last Updated", systemImage: "clock").tag(SortOption.lastUpdated)
                                Label("Recently Subscribed", systemImage: "calendar").tag(SortOption.newestSubscribed)
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
            }
        }
    }
}

struct DownloadedEpisodesList: View {
    @Query(filter: #Predicate<Episode> { $0.isDownloaded == true }, sort: \Episode.releaseDate, order: .reverse)
    private var episodes: [Episode]
    @Environment(AudioManager.self) private var audioManager
    
    var body: some View {
        if episodes.isEmpty {
            ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle", description: Text("Episodes you download will appear here."))
        } else {
            List {
                ForEach(episodes) { episode in
                     Button {
                         // Build queue
                         let all = episodes
                         var queue: [Episode] = []
                         if let index = all.firstIndex(where: { $0.id == episode.id }) {
                             queue = Array(all.suffix(from: index + 1))
                         }
                         audioManager.play(episode: episode, queue: queue)
                     } label: {
                         EpisodeListRow(episode: episode)
                     }
                     .listRowInsets(EdgeInsets())
                     .listRowSeparator(.hidden)
                     .swipeActions(edge: .trailing) {
                         Button(role: .destructive) {
                             DownloadManager.shared.removeDownload(episode: episode)
                         } label: {
                             Label("Delete", systemImage: "trash")
                         }
                     }
                }
            }
            .listStyle(.plain)
        }
    }
}

struct SavedEpisodesList: View {
    @Query(filter: #Predicate<Episode> { $0.isSaved == true }, sort: \Episode.releaseDate, order: .reverse)
    private var episodes: [Episode]
    @Environment(AudioManager.self) private var audioManager
    
    var body: some View {
        if episodes.isEmpty {
            ContentUnavailableView("No Saved Episodes", systemImage: "bookmark", description: Text("Episodes you save will appear here."))
        } else {
            List {
                ForEach(episodes) { episode in
                     Button {
                         // Build queue
                         let all = episodes
                         var queue: [Episode] = []
                         if let index = all.firstIndex(where: { $0.id == episode.id }) {
                             queue = Array(all.suffix(from: index + 1))
                         }
                         audioManager.play(episode: episode, queue: queue)
                     } label: {
                         EpisodeListRow(episode: episode)
                     }
                     .listRowInsets(EdgeInsets())
                     .listRowSeparator(.hidden)
                     .swipeActions(edge: .trailing) {
                         Button(role: .destructive) {
                             episode.isSaved = false
                         } label: {
                             Label("Unsave", systemImage: "bookmark.slash")
                         }
                     }
                }
            }
            .listStyle(.plain)
        }
    }
}

struct PodcastLibraryGrid: View {
    @Query private var podcasts: [Podcast]
    
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    init(sort: SortDescriptor<Podcast>) {
        // Filter remains the same (subscribed only), sort is dynamic
        _podcasts = Query(filter: #Predicate<Podcast> { $0.isSubscribed == true }, sort: [sort])
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(podcasts) { podcast in
                    NavigationLink {
                        PodcastDetailView(podcast: podcast)
                    } label: {
                        VStack(alignment: .leading) {
                            if let url = podcast.imageURL {
                                AsyncImage(url: url) { image in
                                    image.resizable()
                                        .aspectRatio(contentMode: .fit)
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                }
                                .cornerRadius(12)
                            }
                            
                            Text(podcast.title)
                                .font(.headline)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            
                            Text(statusText(for: podcast))
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .buttonStyle(.plain)
        }
    }
    
    private func statusText(for podcast: Podcast) -> String {
        var components: [String] = []
        
        // Last Updated
        if let date = podcast.lastUpdate {
            components.append(date.compactTimeAgo())
        } else {
            components.append("-")
        }
        
        // New Episodes Count (Consecutive unplayed from newest)
        if let episodes = podcast.episodes {
            let sortedEpisodes = episodes.sorted { $0.releaseDate > $1.releaseDate }
            var newCount = 0
            
            for episode in sortedEpisodes {
                if episode.playStateRaw == 0 { // Unplayed
                    newCount += 1
                } else {
                    break
                }
            }
            
            if newCount > 0 {
                components.append("\(newCount) new")
            }
        }
        
        return components.joined(separator: " - ")
    }
}


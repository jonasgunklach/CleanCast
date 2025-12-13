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

    var body: some View {
        NavigationStack {
            PodcastLibraryGrid(sort: sortOption.descriptor)
                .navigationTitle("Library")
                .navigationBarTitleDisplayMode(.large) // Explicitly set to large
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Sort By", selection: $sortOption) {
                                Label("Last Updated", systemImage: "clock").tag(SortOption.lastUpdated)
                                Label("Recently Subscribed", systemImage: "calendar").tag(SortOption.newestSubscribed)
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .font(.system(size: 16, weight: .semibold)) // Matches title weight roughly
                        }
                    }
                }
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
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            components.append(formatter.localizedString(for: date, relativeTo: Date()))
        } else {
            components.append("Unknown")
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


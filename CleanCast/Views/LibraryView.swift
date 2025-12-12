import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(filter: #Predicate<Podcast> { $0.isSubscribed == true }, sort: \Podcast.lastUpdate, order: .reverse) private var podcasts: [Podcast]
    
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
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
                                
                                Text(podcast.author)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    }
                }
                .padding()
            }
            .buttonStyle(.plain) // Ensure text colors are not overridden by link tint
            .navigationTitle("Library")
        }
    }


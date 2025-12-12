import SwiftUI
import SwiftData

struct SearchView: View {
    @Binding var searchText: String
    @State private var results: [iTunesSearchResult] = []
    @State private var isSearching = false
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    ProgressView()
                } else if results.isEmpty {
                    if searchText.isEmpty {
                        ContentUnavailableView("Search Podcasts", systemImage: "magnifyingglass", description: Text("Find your next favorite show"))
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                } else {
                    List(results) { result in
                        NavigationLink {
                            PodcastDetailView(podcast: podcast(from: result))
                        } label: {
                            HStack {
                                AsyncImage(url: URL(string: result.artworkUrl600 ?? "")) { image in
                                    image.resizable()
                                } placeholder: {
                                    Color.gray
                                }
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                                
                                VStack(alignment: .leading) {
                                    Text(result.collectionName)
                                        .font(.headline)
                                    Text(result.artistName)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Podcasts, Artists, Episodes")
        .onSubmit(of: .search) {
            performSearch()
        }
        .submitLabel(.search)
        .onChange(of: searchText) { oldValue, newValue in
            if newValue.isEmpty {
                results = []
                isSearching = false
            } else {
                // Debounce search
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s debounce
                    if !Task.isCancelled && searchText == newValue {
                        performSearch()
                    }
                }
            }
        }
    }
    
    private func podcast(from result: iTunesSearchResult) -> Podcast {
        Podcast(
            title: result.collectionName,
            author: result.artistName,
            feedUrl: result.feedUrl ?? "",
            imageURL: URL(string: result.artworkUrl600 ?? "")
        )
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        isSearching = true
        Task {
            do {
                results = try await PodcastService.shared.searchPodcasts(term: searchText)
            } catch {
                print("Search failed: \(error)")
            }
            isSearching = false
        }
    }
}

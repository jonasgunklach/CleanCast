import SwiftUI
import SwiftData

struct PodcastDetailView: View {
    @State var podcast: Podcast
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @Environment(AudioManager.self) private var audioManager
    @Environment(DownloadManager.self) private var downloadManager


    private func setAutoDownloadLimit(_ limit: Int?) {
        if podcast.modelContext == nil {
             modelContext.insert(podcast)
        }
        
        // Setting an auto-download limit implies subscription
        if limit != nil {
            podcast.isSubscribed = true
        }
        
        // Ensure episodes are persisted for the DownloadManager
        if !displayedEpisodes.isEmpty {
            podcast.episodes = displayedEpisodes
        }
        
        podcast.autoDownloadLimit = limit
        try? modelContext.save()
        
        // Trigger check immediately
        Task {
            await MainActor.run {
                downloadManager.triggerAutoDownload(for: [podcast])
            }
        }
    }
    
    @State private var isRefreshing = false
    @State private var artworkColors: ArtworkColors = .default
    @State private var hasExtractedColors = false
    @State private var displayedEpisodes: [Episode] = []
    
    init(podcast: Podcast) {
        self._podcast = State(initialValue: podcast)
        if let existing = podcast.episodes {
            self._displayedEpisodes = State(initialValue: existing.sorted { $0.releaseDate > $1.releaseDate })
        }
    }
    
    // Derived background color based on scheme and extraction
    private var backgroundColor: Color {
        if colorScheme == .dark {
            return artworkColors.primary.opacity(0.15)
        } else {
            return artworkColors.primary.opacity(0.25)
        }
    }
    
    private var separatorGradient: LinearGradient {
        LinearGradient(
            colors: [
                artworkColors.primary.opacity(0.3),
                artworkColors.secondary.opacity(0.2)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    var body: some View {
        List {
            Section {
                headerSection
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                
                if !displayedEpisodes.isEmpty {
                    episodesHeaderSection
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .padding(.top, 10)
                }
            }
            .listSectionSeparator(.hidden)
            
            if !displayedEpisodes.isEmpty {
                ForEach(displayedEpisodes.prefix(25)) { episode in
                     Button {
                         play(episode)
                     } label: {
                         EpisodeRow(episode: episode, artworkColors: artworkColors)
                             .contentShape(Rectangle())
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
                     .swipeActions(edge: .leading) {
                         Button {
                             toggleSaved(episode)
                         } label: {
                             Label(episode.isSaved ? "Unsave" : "Save",
                                   systemImage: episode.isSaved ? "bookmark.fill" : "bookmark")
                         }
                         .tint(episode.isSaved ? .orange : .blue)
                     }

                     .listRowSeparator(.visible)
                     .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                     .listRowBackground(Color.clear)
                }
                
                if displayedEpisodes.count > 25 {
                    NavigationLink {
                        AllEpisodesView(episodes: displayedEpisodes, artworkColors: artworkColors)
                    } label: {
                        Text("See All Episodes")
                            .font(.headline)
                            .foregroundStyle(artworkColors.primary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            } else {
                 ContentUnavailableView("No Episodes", systemImage: "microphone", description: Text("Loading episodes..."))
                     .frame(maxWidth: .infinity)
                     .padding(.top, 40)
                     .listRowSeparator(.hidden)
                     .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(backgroundColor.ignoresSafeArea())
        .onAppear {
            resolvePodcast()
            if podcast.modelContext == nil {
                podcast.isSubscribed = false
            }
            extractArtworkColors()
            loadPersistedEpisodes()
            loadEpisodes()
        }
        .refreshable {
            // refresh logic
            loadEpisodes()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                 HStack(spacing: 0) {
                     if podcast.isSubscribed { // Subscribed
                         Button {
                             unsubscribe()
                         } label: {
                             Image(systemName: "checkmark.circle.fill")
                                 .font(.title2)
                                 .foregroundStyle(artworkColors.primary)
                                 .padding(8)
                                 .contentShape(Rectangle())
                         }
                     } else { // Not subscribed
                         Button {
                             subscribe()
                         } label: {
                             Image(systemName: "plus.circle")
                                 .font(.title2)
                                 .foregroundStyle(artworkColors.primary)
                                 .padding(8)
                                 .contentShape(Rectangle())
                         }
                     }
                     
                     Menu {
                         if podcast.isSubscribed {
                             Button(role: .destructive) {
                                 unsubscribe()
                             } label: {
                                 Label("Unsubscribe", systemImage: "trash")
                             }
                             Divider()
                         }
                         
                         Menu("Auto-Download") {
                             Button {
                                 setAutoDownloadLimit(nil)
                             } label: {
                                 if podcast.autoDownloadLimit == nil {
                                     Label("Global Default", systemImage: "checkmark")
                                 } else {
                                     Text("Global Default")
                                 }
                             }
                             
                             Button {
                                 setAutoDownloadLimit(1)
                             } label: {
                                 if podcast.autoDownloadLimit == 1 {
                                     Label("Latest 1", systemImage: "checkmark")
                                 } else {
                                     Text("Latest 1")
                                 }
                             }
                             
                             Button {
                                 setAutoDownloadLimit(2)
                             } label: {
                                 if podcast.autoDownloadLimit == 2 {
                                     Label("Latest 2", systemImage: "checkmark")
                                 } else {
                                     Text("Latest 2")
                                 }
                             }
                             
                             Button {
                                 setAutoDownloadLimit(3)
                             } label: {
                                 if podcast.autoDownloadLimit == 3 {
                                     Label("Latest 3", systemImage: "checkmark")
                                 } else {
                                     Text("Latest 3")
                                 }
                             }
                         }
                     } label: {
                         Image(systemName: "ellipsis.circle")
                             .font(.title2)
                             .foregroundStyle(artworkColors.primary)
                             .padding(8)
                             .contentShape(Rectangle())
                     }
                 }
            }
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            artworkView
            podcastInfoView
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 24)
    }
    
    private var episodesHeaderSection: some View {
        HStack {
            Text("Latest Episodes")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Text("\(displayedEpisodes.count)")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Components
    
    @ViewBuilder
    private var artworkView: some View {
        if let url = podcast.imageURL {
            AsyncImage(url: url) { image in
                image.resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: 180, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: artworkColors.primary.opacity(0.3), radius: 15, x: 0, y: 8)
        } else {
             RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 180, height: 180)
        }
    }
    
    private var podcastInfoView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(podcast.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            
            Text(podcast.author)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            
            if let desc = podcast.desc, !desc.isEmpty {
                ExpandableDescriptionView(text: desc, artworkColors: artworkColors)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Logic
    
    private func loadPersistedEpisodes() {
        if let existing = podcast.episodes {
             self.displayedEpisodes = existing.sorted { $0.releaseDate > $1.releaseDate }
        }
    }
    
    private func resolvePodcast() {
        // Attempt to find existing podcast in DB by feedUrl to restore history
        let feedUrl = podcast.feedUrl
        let descriptor = FetchDescriptor<Podcast>(predicate: #Predicate { $0.feedUrl == feedUrl })
        if let existing = try? modelContext.fetch(descriptor).first {
            // Switch to the persisted instance
            self.podcast = existing
        }
    }
    
    private func unsubscribe() {
        // Soft unsubscribe to preserve history
        podcast.isSubscribed = false
        try? modelContext.save()
    }
    
    private func subscribe() {
        if podcast.modelContext == nil {
            modelContext.insert(podcast)
        }
        podcast.isSubscribed = true
        
        // Ensure episodes are persisted
        if !displayedEpisodes.isEmpty {
            podcast.episodes = displayedEpisodes
        }
        
        try? modelContext.save()
    }

    private func loadEpisodes() {
        Task {
            do {
                // Fetch real episodes via PodcastService
                let fetched = try await PodcastService.shared.fetchEpisodes(feedUrl: podcast.feedUrl)
                
                await MainActor.run {
                    // Merge with persisted episodes to preserve state
                    let persistedEpisodes = podcast.episodes ?? []
                    let persistedMap = Dictionary(grouping: persistedEpisodes, by: { $0.url }).compactMapValues { $0.first }
                    
                    let merged = fetched.map { transient -> Episode in
                        if let persisted = persistedMap[transient.url] {
                            return persisted
                        }
                        return transient
                    }
                    
                    self.displayedEpisodes = merged.sorted { $0.releaseDate > $1.releaseDate }
                    
                    // Sync with model if subscribed, so DownloadManager observes them
                    if podcast.isSubscribed {
                        podcast.episodes = merged
                        // Try to trigger auto-download check immediately after saving
                        if podcast.autoDownloadLimit != nil {
                            downloadManager.triggerAutoDownload(for: [podcast])
                        }
                    }
                    
                    try? modelContext.save()
                }
            } catch {
                print("Error loading episodes: \(error)")
            }
        }
    }
    
    // Helper to persist before playing
    private func play(_ episode: Episode) {
        ensurePersisted(episode)
        
        // Auto-fill queue with subsequent episodes from the list
        var queue: [Episode] = []
        if let index = displayedEpisodes.firstIndex(where: { $0.id == episode.id }) {
            let subsequent = displayedEpisodes.suffix(from: index + 1)
            queue = Array(subsequent)
        }
        
        audioManager.play(episode: episode, queue: queue)
    }
    
    private func togglePlayed(_ episode: Episode) {
        ensurePersisted(episode)
        if episode.playStateRaw == 2 {
            episode.playStateRaw = 0 // Unplayed
            episode.progress = 0
        } else {
            episode.playStateRaw = 2 // Played
            episode.progress = episode.duration
        }
        try? modelContext.save()
    }
    
    private func toggleDownload(_ episode: Episode) {
        ensurePersisted(episode)
        
        Task {
            if episode.isDownloaded {
                // Remove
                DownloadManager.shared.removeDownload(episode: episode)
            } else {
                // Download
                do {
                    try await DownloadManager.shared.download(episode: episode)
                } catch {
                    print("Download failed: \(error)")
                }
            }
            try? modelContext.save()
        }
    }


    private func toggleSaved(_ episode: Episode) {
        ensurePersisted(episode)
        episode.isSaved.toggle()
        try? modelContext.save()
    }
    
    private func ensurePersisted(_ episode: Episode) {
        if episode.modelContext == nil {
            episode.podcast = podcast
            modelContext.insert(episode)
            try? modelContext.save()
        }
    }
    
    private func extractArtworkColors() {
        guard !hasExtractedColors, let url = podcast.imageURL else { return }
        
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let uiImage = UIImage(data: data) {
                
                let colors = ArtworkColorExtractor.shared.extractColors(from: uiImage)
                
                await MainActor.run {
                    self.artworkColors = colors
                    self.hasExtractedColors = true
                    
                    // Persist colors for global usage (e.g. mini player accent)
                    // Persist colors for global usage (e.g. mini player accent)
                    if podcast.accentColorHex == nil {
                        podcast.accentColorHex = ColorManager.shared.hexString(from: colors.accent)
                        podcast.backgroundColorHex = ColorManager.shared.hexString(from: colors.primary)
                        try? modelContext.save()
                    }
                }
            }
        }
    }
}


import SwiftUI
import SwiftData

struct PodcastDetailView: View {
    @State var podcast: Podcast
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @Environment(AudioManager.self) private var audioManager
    
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
            headerSection
            
            if !displayedEpisodes.isEmpty {
                episodesHeaderSection
                episodesListSection
                
                if displayedEpisodes.count > 25 {
                    Section {
                        NavigationLink {
                            AllEpisodesView(episodes: displayedEpisodes, artworkColors: artworkColors)
                        } label: {
                            Text("See All Episodes")
                                .font(.headline)
                                .foregroundStyle(artworkColors.primary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            } else {
                 ContentUnavailableView("No Episodes", systemImage: "microphone", description: Text("Loading episodes..."))
                     .listRowSeparator(.hidden)
                     .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(backgroundColor.ignoresSafeArea())
        .environment(\.defaultMinListRowHeight, 0)
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
                             Button("Off", action: {})
                             Button("Latest 1", action: {})
                             Button("Latest 3", action: {})
                             Button("Latest 5", action: {})
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
        Section {
            VStack(spacing: 16) {
                artworkView
                podcastInfoView
            }
            .padding(.horizontal, 12)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
    
    private var episodesHeaderSection: some View {
        Section {
            EmptyView()
        } header: {
            HStack {
                Text("Latest Episodes")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(displayedEpisodes.count)")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .listRowInsets(EdgeInsets())
        }
    }
    
    private var episodesListSection: some View {
        Section {
            ForEach(displayedEpisodes.prefix(25)) { episode in
                EpisodeRow(episode: episode, artworkColors: artworkColors)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        play(episode)
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
            }
        }
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
                }
            } catch {
                print("Error loading episodes: \(error)")
            }
        }
    }
    
    // Helper to persist before playing
    private func play(_ episode: Episode) {
        ensurePersisted(episode)
        audioManager.play(episode: episode)
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

// Updated EpisodeRow to match design
struct EpisodeRow: View {
    let episode: Episode
    let artworkColors: ArtworkColors
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    
                    Text(episode.releaseDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Duration or Progress
                VStack(alignment: .trailing) {
                    if episode.playStateRaw == 2 { // Played
                         Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(artworkColors.accent)
                    } else if episode.playStateRaw == 1 && episode.duration > 0 { // In Progress
                         let left = max(0, episode.duration - episode.progress)
                         Text("\(format(left)) left")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(artworkColors.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(artworkColors.accent.opacity(0.1))
                            .clipShape(Capsule())
                    } else {
                         Text(format(episode.duration))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            
            HStack {
                if episode.isDownloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(artworkColors.primary)
                }
                
                Text(episode.desc)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.5))
        )
    }
    
    func format(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? ""
    }
}

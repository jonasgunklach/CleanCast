import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(filter: #Predicate<Podcast> { $0.isSubscribed == true }, sort: \Podcast.lastUpdate, order: .reverse) 
    private var podcasts: [Podcast]
    
    @Query(filter: #Predicate<Episode> { $0.playStateRaw == 1 }, sort: \Episode.releaseDate, order: .reverse) 
    private var unfinishedEpisodes: [Episode]
    
    @Environment(AudioManager.self) private var audioManager
    
    private var newestUnplayedEpisodes: [Episode] {
        let allEpisodes = podcasts.flatMap { $0.episodes ?? [] }
        return allEpisodes
            .filter { $0.playStateRaw != 2 } // Show Unplayed and In Progress
            .sorted { $0.releaseDate > $1.releaseDate }
            .prefix(25) // Show top 25
            .map { $0 }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if podcasts.isEmpty {
                        ContentUnavailableView("No Subscriptions", systemImage: "music.mic", description: Text("Subscribe to podcasts in Search tab"))
                            .padding(.top, 40)
                    } else {
                        // Newest Unplayed Section
                        if !newestUnplayedEpisodes.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("New Episodes")
                                    .font(.title2.bold())
                                    .padding(.horizontal)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(newestUnplayedEpisodes) { episode in
                                            HomeEpisodeCard(episode: episode)
                                                .onTapGesture {
                                                    audioManager.play(episode: episode)
                                                }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        
                        // Continue Listening
                        if !unfinishedEpisodes.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Continue Listening")
                                    .font(.title2.bold())
                                    .padding(.horizontal)
                                
                                List {
                                    ForEach(Array(unfinishedEpisodes.prefix(10))) { episode in
                                        HomeEpisodeRow(episode: episode)
                                            .onTapGesture {
                                                audioManager.play(episode: episode)
                                            }
                                            .listRowInsets(EdgeInsets())
                                            .listRowSeparator(.hidden)
                                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                Button(role: .destructive) {
                                                    episode.playStateRaw = 2 // Mark as played
                                                } label: {
                                                    Label("Played", systemImage: "checkmark")
                                                }
                                            }
                                            .swipeActions(edge: .leading) {
                                                Button {
                                                    episode.playStateRaw = 0 // Mark as unplayed
                                                } label: {
                                                    Label("Unplayed", systemImage: "circle")
                                                }
                                                .tint(.blue)
                                            }
                                    }
                                }
                                .listStyle(.plain)
                                .frame(height: CGFloat(min(unfinishedEpisodes.prefix(10).count, 10)) * 70)
                                .scrollDisabled(true)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Home")
            .refreshable {
                await refreshPodcasts()
            }
        }
        .onAppear {
            Task {
                await refreshPodcasts()
            }
        }
    }
    
    private func refreshPodcasts() async {
        for podcast in podcasts {
            if podcast.episodes?.isEmpty ?? true {
                do {
                    let fetched = try await PodcastService.shared.fetchEpisodes(feedUrl: podcast.feedUrl)
                    await MainActor.run {
                        if podcast.episodes?.isEmpty ?? true {
                            podcast.episodes = fetched
                            fetched.forEach { $0.podcast = podcast }
                        } else {
                            let existingUrls = Set(podcast.episodes?.map { $0.url } ?? [])
                            let newEpisodes = fetched.filter { !existingUrls.contains($0.url) }
                            if !newEpisodes.isEmpty {
                                newEpisodes.forEach { $0.podcast = podcast }
                                podcast.episodes?.append(contentsOf: newEpisodes)
                            }
                        }
                        podcast.lastUpdate = Date()
                    }
                } catch {
                    print("Home refresh failed for \(podcast.title): \(error)")
                }
            }
        }
    }
}

struct HomeEpisodeCard: View {
    let episode: Episode
    @State private var artworkColors: ArtworkColors = .default
    @State private var hasExtractedColors = false
    @Environment(AudioManager.self) private var audioManager
    
    // Check if *this* episode is currently playing/active
    private var isCurrentEpisode: Bool {
        audioManager.currentEpisode?.id == episode.id
    }
    
    private var isPlaying: Bool {
        isCurrentEpisode && audioManager.isPlaying
    }
    
    private var textColor: Color {
        // Use white text for contrast with dominant color background
        .white
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top 2/3: Full artwork image
            if let url = episode.podcast?.imageURL {
                AsyncImage(url: url) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.3)
                        .overlay {
                            ProgressView()
                        }
                }
                .frame(height: 240)
                .clipped()
            } else {
                Color.gray.opacity(0.3)
                    .frame(height: 240)
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundColor(.gray)
                            .font(.system(size: 60))
                    }
            }
            
            // Bottom 1/3: Dominant color background with episode info
            VStack(alignment: .leading, spacing: 12) {
                // Episode title
                Text(episode.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .foregroundColor(textColor)
                
                // Info Pills Row
                HStack(spacing: 8) {
                    // Podcast name pill
                    if let podcastTitle = episode.podcast?.title {
                        Text(podcastTitle)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(textColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.25))
                            )
                            .lineLimit(1)
                    }
                    
                    // Duration pill
                    if episode.duration > 0 {
                        Text(format(episode.duration))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(textColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.25))
                            )
                    }
                    
                    Spacer()
                    
                    // Play/Pause Play button pill
                    Button {
                        if isPlaying {
                            audioManager.pause()
                        } else if isCurrentEpisode {
                             audioManager.play(episode: episode)
                        } else {
                             audioManager.play(episode: episode)
                        }
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(textColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.3))
                            )
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 130)
            .background(artworkColors.primary) // Dynamic background
        }
        .frame(width: 300)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
        .onAppear {
            extractColors()
        }
        .task(id: episode.id) {
             extractColors()
        }
    }
    
    private func extractColors() {
        guard !hasExtractedColors, let url = episode.podcast?.imageURL else { return }
        
        // Check if podcast already has cached colors
        if let hex = episode.podcast?.backgroundColorHex, let bg = Color(hex: hex) {
             // We can reconstruct ArtworkColors if we strictly only need primary
             // But let's try to get the full object if possible or just use the background
             // For now, let's just use the extractor to be consistent or use cached values if extraction fails?
             // To be robust, let's extract.
        }
        
        Task {
            // Check cache logic or file system? For now simple URL fetch
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let uiImage = UIImage(data: data) {
                
                let colors = ArtworkColorExtractor.shared.extractColors(from: uiImage)
                
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.artworkColors = colors
                        self.hasExtractedColors = true
                    }
                }
            }
        }
    }
    
    func format(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? ""
    }
}

struct PlayCircleButton: View {
    var body: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: "play.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
            .shadow(radius: 5)
    }
}

struct HomeEpisodeRow: View {
    let episode: Episode
    
    var body: some View {
        HStack(spacing: 16) {
            // Tiny Artwork
            if let url = episode.podcast?.imageURL {
                AsyncImage(url: url) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let podcastTitle = episode.podcast?.title {
                    Text(podcastTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Text(episode.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // "XXm left" Badge
            if episode.duration > 0 {
                let left = max(0, episode.duration - episode.progress)
                Text("\(format(left)) left")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    
    func format(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? ""
    }
}

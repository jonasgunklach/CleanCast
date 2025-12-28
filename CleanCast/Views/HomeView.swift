import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(filter: #Predicate<Podcast> { $0.isSubscribed == true }, sort: \Podcast.lastUpdate, order: .reverse) 
    private var podcasts: [Podcast]
    
    @Query(filter: #Predicate<Episode> { $0.playStateRaw == 1 }, sort: \Episode.releaseDate, order: .reverse) 
    private var unfinishedEpisodes: [Episode]
    
    @Environment(AudioManager.self) private var audioManager
    
    // Smart Sorting: Round-Robin (Podcast 1 Ep 1, Podcast 2 Ep 1, P1 Ep 2...)
    private var newestUnplayedEpisodes: [Episode] {
        // 1. Group by Podcast
        let grouped = Dictionary(grouping: podcasts.flatMap { $0.episodes ?? [] }) { $0.podcast }
        
        // 2. Sort Podcasts by recency (stable) instead of usage (volatile during playback)
        // Add title as tie-breaker for deterministic order when dates are equal (e.g. initial import)
        let sortedPodcasts = grouped.keys.sorted {
            let date1 = $0?.lastUpdate ?? Date.distantPast
            let date2 = $1?.lastUpdate ?? Date.distantPast
            if abs(date1.timeIntervalSince(date2)) > 1 {
                return date1 > date2
            }
            return ($0?.title ?? "") < ($1?.title ?? "")
        }
        
        // 3. Prepare queues per podcast (sorted by release date descending)
        var podcastQueues: [[Episode]] = []
        for podcast in sortedPodcasts {
            guard let podcast = podcast, let eps = grouped[podcast] else { continue }
            let unplayed = eps
                .filter { $0.playStateRaw != 2 } // In Progress or Unplayed
                .sorted { $0.releaseDate > $1.releaseDate }
            if !unplayed.isEmpty {
                podcastQueues.append(unplayed)
            }
        }
        
        // 4. Round Robin Interleaving
        var result: [Episode] = []
        
        // Limit total iteration to prevent infinite loops if something goes wrong, though logic is safe
        // Also simpler: loop while queues not empty
        while !podcastQueues.isEmpty {
            var nextQueues: [[Episode]] = []
            
            for var queue in podcastQueues {
                if !queue.isEmpty {
                    // Take the first one (newest for that podcast)
                    result.append(queue.removeFirst())
                    
                    // If more remain, keep the queue
                    if !queue.isEmpty {
                        nextQueues.append(queue)
                    }
                }
            }
            podcastQueues = nextQueues
        }
        
        return Array(result.prefix(25))
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
                                                .scrollTransition { content, phase in
                                                    content
                                                        .opacity(phase.isIdentity ? 1.0 : 0.8)
                                                        .scaleEffect(phase.isIdentity ? 1.0 : 0.95)
                                                }
                                                .onTapGesture {
                                                    // Calculate queue
                                                    let all = newestUnplayedEpisodes
                                                    var queue: [Episode] = []
                                                    if let index = all.firstIndex(where: { $0.id == episode.id }) {
                                                        queue = Array(all.suffix(from: index + 1))
                                                    }
                                                    audioManager.play(episode: episode, queue: queue)
                                                }
                                        }
                                    }
                                    .scrollTargetLayout()
                                    .padding(.horizontal)
                                }
                                .scrollTargetBehavior(.viewAligned)
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
                                                // Calculate queue
                                                let all = Array(unfinishedEpisodes.prefix(10))
                                                var queue: [Episode] = []
                                                if let index = all.firstIndex(where: { $0.id == episode.id }) {
                                                    queue = Array(all.suffix(from: index + 1))
                                                }
                                                audioManager.play(episode: episode, queue: queue)
                                            }
                                            .contextMenu {
                                                Button {
                                                    audioManager.addToQueue(episode, next: true)
                                                } label: {
                                                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                                                }
                                                
                                                Button {
                                                    audioManager.addToQueue(episode, next: false)
                                                } label: {
                                                    Label("Add to Queue", systemImage: "text.append")
                                                }
                                                
                                                Divider()
                                                
                                                Button {
                                                     Task {
                                                         if episode.isDownloaded {
                                                             DownloadManager.shared.removeDownload(episode: episode)
                                                         } else {
                                                             try? await DownloadManager.shared.download(episode: episode)
                                                         }
                                                     }
                                                } label: {
                                                    Label(episode.isDownloaded ? "Remove Download" : "Download", 
                                                          systemImage: episode.isDownloaded ? "trash" : "arrow.down")
                                                }
                                                
                                                Button {
                                                    episode.isSaved.toggle()
                                                } label: {
                                                    Label(episode.isSaved ? "Unsave" : "Save", 
                                                          systemImage: episode.isSaved ? "bookmark.fill" : "bookmark")
                                                }
                                                
                                                Button {
                                                    if episode.playStateRaw == 2 {
                                                        episode.playStateRaw = 0
                                                        episode.progress = 0
                                                    } else {
                                                        episode.playStateRaw = 2
                                                        episode.progress = episode.duration
                                                    }
                                                } label: {
                                                    Label(episode.playStateRaw == 2 ? "Mark Unplayed" : "Mark Played", 
                                                          systemImage: episode.playStateRaw == 2 ? "circle" : "checkmark.circle")
                                                }
                                                
                                                Divider()
                                                
                                                NavigationLink {
                                                    EpisodeDetailView(episode: episode, artworkColors: .default)
                                                } label: {
                                                    Label("See episode", systemImage: "info.circle")
                                                }
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
                .padding(.bottom) // Keep bottom padding, remove top/vertical to match iOS native look
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
                                podcast.lastUpdate = Date()
                            }
                        }
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
    @Environment(DownloadManager.self) private var downloadManager
    
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
    
    private var durationText: String {
        if episode.progress > 0 && episode.playStateRaw == 1 {
             let left = max(0, episode.duration - episode.progress)
             return "\(format(left)) left"
        } else {
             return format(episode.duration)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top 2/3: Full artwork image
            if let url = episode.podcast?.imageURL {
                CachedAsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .padding(12) // Smaller border -> larger image
                .padding(.top, 4)
                .frame(height: 240) // Taller container
            } else {
                Color.gray.opacity(0.3)
                    .frame(height: 220)
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundColor(.gray)
                            .font(.system(size: 60))
                    }
            }
            
            // Bottom 1/3: Episode info
            VStack(alignment: .leading, spacing: 12) {
                // Episode title
                Text(episode.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .foregroundColor(textColor)
                
                // Info Pills Row
                HStack(spacing: 8) {
                    // Download Status Pill (Replaces Podcast Name as requested)
                    if downloadManager.activeDownloads.contains(episode.id) {
                         // Spinner
                         ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.25))
                            )
                            .tint(.white)
                    } else if episode.isDownloaded {
                         // Download Icon
                         Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(textColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.25))
                            )
                    }
                    
                    // Duration or Remaining Time pill
                    if episode.duration > 0 {
                        Text(durationText)
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
                        } else {
                             // Find context to queue subsequent
                             // Note: We don't have easy access to the full list here inside the subview unless passed
                             // But we can just play single for now or assume user plays from list
                             // Ideally we pass the queue closure or list to the card
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
            .padding(.top, -8) // Pull up slightly closer to image
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 130)
        }
        .background(artworkColors.primary) // Dynamic background applied to whole card
        .frame(width: 300)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
        .contextMenu {
            NavigationLink {
                EpisodeDetailView(episode: episode, artworkColors: artworkColors)
            } label: {
                Label("See episode", systemImage: "info.circle")
            }
            
            Divider()
            
            Button {
                audioManager.addToQueue(episode, next: true)
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            
            Button {
                audioManager.addToQueue(episode, next: false)
            } label: {
                Label("Add to Queue", systemImage: "text.append")
            }
            
            Divider()
            
            Button {
                 Task {
                     if episode.isDownloaded {
                         DownloadManager.shared.removeDownload(episode: episode)
                     } else {
                         try? await DownloadManager.shared.download(episode: episode)
                     }
                 }
            } label: {
                Label(episode.isDownloaded ? "Remove Download" : "Download", 
                      systemImage: episode.isDownloaded ? "trash" : "arrow.down")
            }
            
            Button {
                episode.isSaved.toggle()
            } label: {
                Label(episode.isSaved ? "Unsave" : "Save", 
                      systemImage: episode.isSaved ? "bookmark.fill" : "bookmark")
            }
            
            Button {
                if episode.playStateRaw == 2 {
                    episode.playStateRaw = 0
                    episode.progress = 0
                } else {
                    episode.playStateRaw = 2
                    episode.progress = episode.duration
                }
            } label: {
                Label(episode.playStateRaw == 2 ? "Mark Unplayed" : "Mark Played", 
                      systemImage: episode.playStateRaw == 2 ? "circle" : "checkmark.circle")
            }
        }
        .tint(artworkColors.primary)
        .onAppear {
            extractColors()
        }
        .task(id: episode.id) {
             extractColors()
        }
    }
    
    private func extractColors() {
        guard !hasExtractedColors, let url = episode.podcast?.imageURL else { return }
        
        // 1. FAST PATH: Check if podcast already has cached colors
        if let bgHex = episode.podcast?.backgroundColorHex,
           let bg = Color(hex: bgHex) {
            
            let accent: Color
            if let accentHex = episode.podcast?.accentColorHex, let acc = Color(hex: accentHex) {
                accent = acc
            } else {
                accent = .pink // Fallback
            }
            
            // Construct colors from cache (reuse accent as secondary for now to avoid storing 3 hexes)
            let cachedColors = ArtworkColors(primary: bg, secondary: accent, accent: accent)
            
            self.artworkColors = cachedColors
            self.hasExtractedColors = true
            return
        }
        
        // 2. SLOW PATH: Extract from image
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let uiImage = UIImage(data: data) {
                
                // Extract colors (fast operation)
                let colors = ArtworkColorExtractor.shared.extractColors(from: uiImage)
                
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.artworkColors = colors
                        self.hasExtractedColors = true
                        
                        // 3. CACHE: Save back to model
                        if let podcast = episode.podcast {
                            podcast.backgroundColorHex = colors.primary.toHex()
                            podcast.accentColorHex = colors.accent.toHex()
                        }
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
                CachedAsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.gray.opacity(0.3)
                    }
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

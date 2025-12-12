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
                                
                                ForEach(unfinishedEpisodes.prefix(10)) { episode in
                                    HomeEpisodeRow(episode: episode)
                                        .padding(.horizontal)
                                        .onTapGesture {
                                            audioManager.play(episode: episode)
                                        }
                                    
                                    if episode.id != unfinishedEpisodes.prefix(10).last?.id {
                                        Divider().padding(.leading)
                                    }
                                }
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
    
    var body: some View {
        ZStack {
            // Background: Dominant Color or Blurred Image
            if let hex = episode.podcast?.backgroundColorHex, let color = Color(hex: hex) {
                color
            } else if let url = episode.podcast?.imageURL {
                AsyncImage(url: url) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 60)
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
            } else {
                Color.gray.opacity(0.3)
            }
            
            // Background Dim content
            Color.black.opacity(0.2)
            
            // Centered Image
            if let url = episode.podcast?.imageURL {
                AsyncImage(url: url) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                        .shadow(radius: 10)
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 180, height: 180)
                .padding(.bottom, 60) // Shift up slightly to make room for info
            }
            
            // Info Badge Overlay
            VStack(alignment: .leading, spacing: 8) {
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    
                    HStack {
                         Text(episode.releaseDate.formatted(date: .abbreviated, time: .omitted))
                        
                        Spacer()
                        
                        // Status
                        if episode.playStateRaw == 2 {
                            Text("Played")
                                .bold()
                        } else if episode.duration > 0 && episode.progress > 0 {
                             let left = max(0, episode.duration - episode.progress)
                             Text("\(format(left)) left")
                                .bold()
                        } else {
                             Text("Unplayed")
                                .bold()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.ultraThinMaterial)
            }
        }
        .frame(width: 280, height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
        .overlay(alignment: .center) {
            // Optional: Play button in center of image?
            // User didn't explicitly ask for play button "in center", but keeping interactions simple.
            // The card itself is tapped to play in HomeView.
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
        .contentShape(Rectangle())
    }
    
    func format(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? ""
    }
}

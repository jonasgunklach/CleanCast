import SwiftUI

struct FullPlayerView: View {
    @Binding var showFullPlayer: Bool
    @Environment(AudioManager.self) private var audioManager
    @Environment(\.colorScheme) var colorScheme
    @State private var isDragging = false
    @State private var sliderValue: Double = 0.0
    @State private var selectedTab = 0
    @State private var scrollPosition: Int? = 0
    
    // Drag to dismiss state
    @GestureState private var dragOffset: CGFloat = 0
    @State private var committedOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. Dynamic Background
                ZStack {
                    if let colors = artworkColors {
                        // Base gradient
                        LinearGradient(
                            colors: [
                                colors.primary.opacity(colorScheme == .dark ? 0.6 : 0.3),
                                colors.secondary.opacity(colorScheme == .dark ? 0.4 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .ignoresSafeArea()
                        // Minimal blur effect via Material
                        .overlay(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
                    } else {
                        Color(UIColor.systemBackground).ignoresSafeArea()
                    }
                }
                
                // Horizontal Paging ScrollView
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        // Page 0: Player Controls
                        VStack(spacing: 30) {
                            // Draggable Top Area
                            VStack(spacing: 30) {
                                // Drag Handle
                                Capsule()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 60, height: 5)
                                .padding(.top, 10)
                                .padding(.bottom, 20)
                                .padding(.vertical, 25)
                                .contentShape(Rectangle())
                            
                            
                            
                            // Artwork
                            if let url = audioManager.currentEpisode?.podcast?.imageURL {
                                 let size = max(0, geometry.size.width - 60)
                                 AsyncImage(url: url) { image in
                                     image.resizable().aspectRatio(contentMode: .fill)
                                 } placeholder: {
                                     Color.gray.opacity(0.3)
                                 }
                                 .frame(width: size, height: size)
                                 .cornerRadius(12)
                                 .shadow(radius: 20)
                                 .scaleEffect(audioManager.isPlaying ? 1.0 : 0.75)
                                 .animation(.spring(response: 0.5, dampingFraction: 0.7), value: audioManager.isPlaying)
                            } else {
                                 let size = max(0, geometry.size.width - 60)
                                 RoundedRectangle(cornerRadius: 12)
                                     .fill(Color.gray.opacity(0.3))
                                     .frame(width: size, height: size)
                                     .scaleEffect(audioManager.isPlaying ? 1.0 : 0.75)
                                     .animation(.spring(response: 0.5, dampingFraction: 0.7), value: audioManager.isPlaying)
                            }
                            
                            // Info
                            VStack(spacing: 8) {
                                HStack(alignment: .center, spacing: 8) {
                                    Text(audioManager.currentEpisode?.title ?? "Not Playing")
                                        .font(.title2.bold())
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .foregroundStyle(.primary)
                                    
                                    if let status = audioManager.currentEpisode?.adDetectionStatus, 
                                       (status == "processing" || status == "partial_start") {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(.secondary)
                                    }
                                }
                                
                                Text(audioManager.currentEpisode?.podcast?.title ?? "")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            }
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 30, coordinateSpace: .global)
                                    .updating($dragOffset) { value, state, _ in
                                        // Only vertical drags
                                        guard value.translation.height > 0 else { return }
                                        state = value.translation.height
                                    }
                                    .onEnded { value in
                                        let y = max(0, value.translation.height)
                                        let v = value.velocity.height
                                        let shouldDismiss = (y > 120) || (v > 900)
                                        
                                        if shouldDismiss {
                                            committedOffset = y
                                            withAnimation(.easeOut(duration: 0.25)) {
                                                committedOffset = geometry.size.height
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                                showFullPlayer = false
                                                committedOffset = 0
                                            }
                                        } else {
                                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                                committedOffset = 0
                                            }
                                        }
                                    }
                            )
                            
                            // Progress
                            VStack(spacing: 8) {
                                Slider(value: $sliderValue, in: 0...(audioManager.duration > 0 ? audioManager.duration : 1)) { editing in
                                    isDragging = editing
                                    if !editing {
                                        audioManager.seek(to: sliderValue)
                                    }
                                }
                                .tint(artworkColors?.accent ?? .primary) 
                                .overlay(alignment: .topLeading) {
                                    GeometryReader { sliderGeo in
                                        ZStack(alignment: .leading) {
                                            if let segments = audioManager.currentEpisode?.adSegments, audioManager.duration > 0 {
                                                ForEach(segments) { segment in
                                                    let startPercent = segment.startTime / audioManager.duration
                                                    let endPercent = segment.endTime / audioManager.duration
                                                    let markerWidth = max(4, (endPercent - startPercent) * sliderGeo.size.width)
                                                    let startOffset = startPercent * sliderGeo.size.width
                                                    
                                                    RoundedRectangle(cornerRadius: 2)
                                                        .fill(Color.yellow.opacity(0.9))
                                                        .frame(width: markerWidth, height: 6)
                                                        .offset(x: startOffset, y: 12) // Center on slider track
                                                }
                                            }
                                        }
                                        .onAppear {
                                            // Debug: Log segment positions
                                            if let segments = audioManager.currentEpisode?.adSegments, !segments.isEmpty {
                                                print("FullPlayerView: Displaying \(segments.count) ad markers, duration=\(audioManager.duration)")
                                                for seg in segments {
                                                    print("  Ad: \(String(format: "%.0f", seg.startTime))-\(String(format: "%.0f", seg.endTime))s (\(String(format: "%.1f", seg.startTime/audioManager.duration*100))%-\(String(format: "%.1f", seg.endTime/audioManager.duration*100))%)")
                                                }
                                            }
                                        }
                                    }
                                }
                                .onChange(of: audioManager.currentEpisode?.adSegments) { _, newSegments in
                                    if let segments = newSegments, !segments.isEmpty {
                                        print("FullPlayerView: Ad segments updated - \(segments.count) segments")
                                    }
                                }
                                .overlay(alignment: .top) {
                                     if isDragging {
                                         Text(format(sliderValue))
                                             .font(.system(size: 14, weight: .bold))
                                             .foregroundStyle(Color(UIColor.systemBackground)) // Inverse text
                                             .padding(8)
                                             .background(Capsule().fill(Color.primary)) // Inverse bg
                                             .offset(y: -40)
                                             .transition(.opacity)
                                     }
                                }
                                
                                HStack {
                                    Text(format(audioManager.currentTime))
                                    Spacer()
                                    Text(format(audioManager.duration))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 30)
                            
                            // Controls (Merged)
                            HStack(spacing: 30) {
                                // Speed (Left)
                                Menu {
                                    Picker("Speed", selection: Bindable(audioManager).playbackRate) {
                                        ForEach([0.7, 0.8, 0.9, 1.0, 1.2, 1.5, 1.7, 2.0], id: \.self) { rate in
                                            Text("\(String(format: "%.1fx", rate))").tag(Float(rate))
                                        }
                                    }
                                } label: {
                                    Image(systemName: "speedometer")
                                        .font(.title2)
                                        .foregroundStyle(artworkColors?.accent ?? .secondary)
                                        .frame(width: 44, height: 44)
                                }
                                
                                Button {
                                    audioManager.seek(to: audioManager.currentTime - 15)
                                } label: {
                                    Image(systemName: "gobackward.15")
                                        .font(.largeTitle)
                                        .foregroundStyle(artworkColors?.accent ?? .primary)
                                }
                                
                                Button {
                                    audioManager.togglePlayPause()
                                } label: {
                                    Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 70))
                                        .foregroundStyle(artworkColors?.accent ?? .primary)
                                }
                                
                                Button {
                                    audioManager.seek(to: audioManager.currentTime + 30)
                                } label: {
                                    Image(systemName: "goforward.30")
                                        .font(.largeTitle)
                                        .foregroundStyle(artworkColors?.accent ?? .primary)
                                }
                                
                                // Sleep (Right)
                                Menu {
                                    Button("Off") { audioManager.invalidateSleepTimer() }
                                    Button("5 min") { audioManager.startSleepTimer(minutes: 5) }
                                    Button("10 min") { audioManager.startSleepTimer(minutes: 10) }
                                    Button("15 min") { audioManager.startSleepTimer(minutes: 15) }
                                    Button("30 min") { audioManager.startSleepTimer(minutes: 30) }
                                } label: {
                                    Image(systemName: audioManager.sleepTimer != nil ? "moon.fill" : "moon")
                                        .font(.title2)
                                        .foregroundStyle(audioManager.sleepTimer != nil ? .yellow : (artworkColors?.accent ?? .secondary))
                                        .frame(width: 44, height: 44)
                                }
                            }
                            .padding(.bottom, 60)
                        }
                        .containerRelativeFrame(.horizontal)
                        .id(0)
                        
                        // Page 1: Up Next Queue
                        UpNextView(accentColor: artworkColors?.accent)
                            .containerRelativeFrame(.horizontal)
                            .id(1)
                        
                        // Page 2: Transcript
                        TranscriptView(accentColor: artworkColors?.accent)
                            .containerRelativeFrame(.horizontal)
                            .id(2)
                        
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .scrollPosition(id: $scrollPosition)
                
                // Pagination Dots
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Circle()
                            .fill((scrollPosition ?? 0) == 0 ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                        Circle()
                            .fill((scrollPosition ?? 0) == 1 ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                        Circle()
                            .fill((scrollPosition ?? 0) == 2 ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                    .padding(.bottom, 30)
                }
            }
            .offset(y: committedOffset + dragOffset)
            .scaleEffect(1.0 - (dragOffset / geometry.size.height) * 0.15)
            .opacity(1.0 - (dragOffset / geometry.size.height) * 0.5)
        }
        .ignoresSafeArea()
        .onAppear {
            sliderValue = audioManager.currentTime
            extractColors()
        }
        .onChange(of: audioManager.currentTime) { _, newValue in
             if !isDragging {
                 sliderValue = newValue
             }
        }
        .onChange(of: audioManager.currentEpisode) {
            extractColors()
        }
    }
    
    // MARK: - Color Extraction
    @State private var artworkColors: ArtworkColors?
    
    private func extractColors() {
        guard let episode = audioManager.currentEpisode, let url = episode.podcast?.imageURL else { return }
        
        // 1. Check Cache
        if let bgHex = episode.podcast?.backgroundColorHex,
           let bg = Color(hex: bgHex) {
            let accent = (episode.podcast?.accentColorHex).flatMap { Color(hex: $0) } ?? .pink
            self.artworkColors = ArtworkColors(primary: bg, secondary: accent, accent: accent)
            return
        }
        
        // 2. Extract
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let uiImage = UIImage(data: data) {
                let colors = ArtworkColorExtractor.shared.extractColors(from: uiImage)
                
                await MainActor.run {
                    self.artworkColors = colors
                    // Cache
                    episode.podcast?.backgroundColorHex = colors.primary.toHex()
                    episode.podcast?.accentColorHex = colors.accent.toHex()
                }
            }
        }
    }
    
    func format(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        if duration >= 3600 { formatter.allowedUnits.insert(.hour) }
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "0:00"
    }
}



import SwiftUI

struct FullPlayerView: View {
    @Environment(AudioManager.self) private var audioManager
    @Environment(\.dismiss) var dismiss
    @State private var artworkColors: ArtworkColors?
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 30) {
                // Drag Handle
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 60, height: 5)
                    .padding(.top, 20)
                
                Spacer()
                
                // Artwork
                if let url = audioManager.currentEpisode?.podcast?.imageURL {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                    .frame(width: geometry.size.width - 60, height: geometry.size.width - 60)
                    .cornerRadius(12)
                    .shadow(radius: 20)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: geometry.size.width - 60, height: geometry.size.width - 60)
                }
                
                // Info
                VStack(spacing: 8) {
                    Text(audioManager.currentEpisode?.title ?? "Not Playing")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .foregroundStyle(.white)
                    
                    Text(audioManager.currentEpisode?.podcast?.title ?? "")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(.horizontal)
                
                // Progress
                VStack(spacing: 8) {
                    ZStack {
                        CustomSliderView(
                            value: Binding(
                                get: { audioManager.currentTime },
                                set: { _ in }
                            ),
                            range: 0...(audioManager.duration > 0 ? audioManager.duration : 1),
                            accentColor: artworkColors?.accent ?? .white,
                            onDragChanged: { _ in
                                // Visual update only, no seek during drag
                            },
                            onDragEnded: { newValue in
                                // Seek only when drag ends
                                audioManager.seek(to: newValue)
                            }
                        )
                        .padding(.horizontal, 8)
                    }
                    .frame(height: 50) // Extra space for indicator
                    
                    HStack {
                        Text(format(audioManager.currentTime))
                        Spacer()
                        Text(format(audioManager.duration))
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 30)
                
                // Controls
                HStack(spacing: 50) {
                    Button {
                        audioManager.seek(to: audioManager.currentTime - 15)
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.largeTitle)
                    }
                    
                    Button {
                        audioManager.togglePlayPause()
                    } label: {
                        Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 70))
                    }
                    
                    Button {
                        audioManager.seek(to: audioManager.currentTime + 30)
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.largeTitle)
                    }
                }
                .foregroundStyle(.white)
                
                Spacer()
                
                // Volume/AirPlay placeholders could go here
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backgroundView)
            .ignoresSafeArea(edges: .all)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .interactiveDismissDisabled(false)
        .onAppear {
            updateColors()
        }
        .onChange(of: audioManager.currentEpisode) { _, _ in
            updateColors()
        }
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        ZStack {
            if let colors = artworkColors {
                LinearGradient(
                    colors: [colors.primary.opacity(0.6), colors.secondary.opacity(0.4), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .background(Color.black) // Fallback
            } else if let hex = audioManager.currentEpisode?.podcast?.backgroundColorHex,
                      let color = Color(hex: hex) {
                LinearGradient(
                    colors: [color.opacity(0.6), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .background(Color.black)
            } else {
                Color.black.ignoresSafeArea() // Default dark theme
            }
            
            // Glass effect overlay
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.2) // Subtle glass
                .ignoresSafeArea()
        }
    }
    
    private func updateColors() {
        guard let podcast = audioManager.currentEpisode?.podcast else { return }
        
        // Try to use loaded hex first for speed
        if let bgHex = podcast.backgroundColorHex, let accentHex = podcast.accentColorHex {
             // Create mock colors object or simple state
             // For now we just need the SwiftUI Colors to use in view
             // I'll reconstruct ArtworkColors assuming it has init/struct available?
             // ArtworkColors struct definition is likely in ArtworkColorExtractor.swift.
             // I'll try to extract if missing.
        }
        
        // Always try extract to get full palette if possible (or if not in DB yet)
        if let url = podcast.imageURL {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let uiImage = UIImage(data: data) {
                    let colors = ArtworkColorExtractor.shared.extractColors(from: uiImage)
                    await MainActor.run {
                        self.artworkColors = colors
                    }
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



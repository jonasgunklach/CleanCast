import SwiftUI

struct FullPlayerView: View {
    @Environment(AudioManager.self) private var audioManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var isDragging = false
    @State private var sliderValue: Double = 0.0
    @State private var selectedTab = 0
    
    // Derived background color matching PodcastDetailView
    private var backgroundColor: Color {
        guard let hex = audioManager.currentEpisode?.podcast?.backgroundColorHex,
              let color = Color(hex: hex) else {
            return Color(.systemBackground)
        }
        
        if colorScheme == .dark {
            return color.opacity(0.15)
        } else {
            return color.opacity(0.25)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                backgroundColor
                    .ignoresSafeArea()
                    .id(audioManager.currentEpisode?.id) // Force update on episode change
                
                TabView(selection: $selectedTab) {
                    // Page 0: Player Controls
                    VStack(spacing: 30) {
                        // Drag Handle
                        Capsule()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 60, height: 5)
                            .padding(.top, 10)
                        
                        Spacer()
                        
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
                            Text(audioManager.currentEpisode?.title ?? "Not Playing")
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                            
                            Text(audioManager.currentEpisode?.podcast?.title ?? "")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal)
                        
                        // Progress
                        VStack(spacing: 8) {
                            Slider(value: $sliderValue, in: 0...(audioManager.duration > 0 ? audioManager.duration : 1)) { editing in
                                isDragging = editing
                                if !editing {
                                    audioManager.seek(to: sliderValue)
                                }
                            }
                            .tint(.white) // White tint looks better on gradient
                            .background(
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        if let segments = audioManager.currentEpisode?.adSegments, audioManager.duration > 0 {
                                            ForEach(segments) { segment in
                                                let startPercent = segment.startTime / audioManager.duration
                                                let endPercent = segment.endTime / audioManager.duration
                                                let width = (endPercent - startPercent) * geometry.size.width
                                                let startOffset = startPercent * geometry.size.width
                                                
                                                Rectangle()
                                                    .fill(Color.yellow.opacity(0.8))
                                                    .frame(width: max(2, width), height: 4)
                                                    .offset(x: startOffset)
                                            }
                                        }
                                    }
                                    .frame(height: 4)
                                    .offset(y: 14)
                                }
                            )
                            .overlay(alignment: .top) {
                                 if isDragging {
                                     Text(format(sliderValue))
                                         .font(.system(size: 14, weight: .bold))
                                         .foregroundStyle(.black)
                                         .padding(8)
                                         .background(Capsule().fill(Color.white))
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
                        .foregroundStyle(.primary)
                        
                        Spacer()
                        Spacer()
                    }
                    .tag(0)
                    
                    // Page 1: Up Next Queue
                    UpNextView()
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            sliderValue = audioManager.currentTime
        }
        .onChange(of: audioManager.currentTime) { _, newValue in
             if !isDragging {
                 sliderValue = newValue
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



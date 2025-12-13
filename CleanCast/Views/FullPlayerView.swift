import SwiftUI

struct FullPlayerView: View {
    @Environment(AudioManager.self) private var audioManager
    @Environment(\.dismiss) var dismiss
    @State private var artworkColors: ArtworkColors?
    @State private var isDragging = false
    @State private var sliderValue: Double = 0.0
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 30) {
                // Drag Handle
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 60, height: 5)
                    .padding(.top, 10) // Reduced padding
                
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
                    .tint(.blue)
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
                                            .fill(Color.yellow.opacity(0.6))
                                            .frame(width: max(2, width), height: 4) // visible height
                                            .offset(x: startOffset)
                                    }
                                }
                            }
                            .frame(height: 4)
                            .offset(y: 14) // Align roughly with slider track (default slider height is ~30-40, track is center)
                        }
                    )
                    .overlay(alignment: .top) {
                         if isDragging {
                             Text(format(sliderValue))
                                 .font(.system(size: 14, weight: .bold))
                                 .foregroundStyle(.white)
                                 .padding(8)
                                 .background(Capsule().fill(Color.black))
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .ignoresSafeArea() 
        }
        .presentationDragIndicator(.visible)
        // Ensure sheet background is clear so we control it, BUT we are using systemBackground now.
        // User wants "no background" (Step 2011) or "clean background".
        // In Step 2016 I used .background(Color(.systemBackground)).
        // I will stick to systemBackground as it is safe and "new iOS" style.
        .onAppear {
            sliderValue = audioManager.currentTime
            // Trigger color update if we want to go back to gradient later, but system is cleaner
        }
        .onChange(of: audioManager.currentTime) { _, newValue in
             if !isDragging {
                 sliderValue = newValue
             }
        }
        // Remove old Artwork Color code if unused, but keep variable to not break build if I missed something
    }
    
    func format(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        if duration >= 3600 { formatter.allowedUnits.insert(.hour) }
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "0:00"
    }
}



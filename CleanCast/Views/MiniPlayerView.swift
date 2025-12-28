import SwiftUI

struct MiniPlayerView: View {
    @Environment(AudioManager.self) private var audioManager
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Image
                if let url = audioManager.currentEpisode?.podcast?.imageURL {
                    CachedAsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Color.gray
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .frame(width: 40, height: 40)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.secondary)
                }
                
                // Content depends on buffering state
                if audioManager.isBuffering {
                    // LOADING STATE: Show spinner and "Identifying Ads..."
                    VStack(alignment: .leading) {
                        Text("Identifying Ads...")
                            .lineLimit(1)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        
                        Text("Please wait")
                            .lineLimit(1)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding(.trailing, 12)
                } else {
                    // NORMAL STATE: Show episode info and controls
                    VStack(alignment: .leading) {
                        Text(audioManager.currentEpisode?.title ?? "Not Playing")
                            .lineLimit(1)
                            .font(.subheadline.bold())
                            .foregroundStyle(audioManager.currentEpisode == nil ? .secondary : .primary)
                        
                        if let title = audioManager.currentEpisode?.podcast?.title {
                            Text(title)
                                .lineLimit(1)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Select an episode")
                                .lineLimit(1)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button {
                        audioManager.togglePlayPause()
                    } label: {
                        Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundStyle(currentAccentColor)
                    }
                    .disabled(audioManager.currentEpisode == nil)
                    
                    Button {
                        audioManager.seek(to: audioManager.currentTime + 30)
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.title2)
                            .foregroundStyle(currentAccentColor)
                    }
                    .disabled(audioManager.currentEpisode == nil)
                }
            }
            .padding(12)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
    }
    
    private var currentAccentColor: Color {
        if let hex = audioManager.currentEpisode?.podcast?.accentColorHex {
             return ColorManager.shared.color(from: hex)
        }
        return audioManager.currentEpisode == nil ? .gray : .blue
    }
}

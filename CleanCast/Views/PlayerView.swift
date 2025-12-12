import SwiftUI

struct PlayerView: View {
    @Environment(AudioManager.self) private var audioManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 30) {
            // Grabber
            //Capsule()
            //    .fill(Color.secondary)
            //    .frame(width: 40, height: 5)
            //    .padding(.top, 10)
            
            Spacer()
            
            // Artwork
            if let url = audioManager.currentEpisode?.podcast?.imageURL {
                AsyncImage(url: url) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(12)
                        .shadow(radius: 20)
                } placeholder: {
                    Color.gray.frame(width: 300, height: 300)
                }
                .frame(width: 300, height: 300)
            }
            
            // Info
            VStack(spacing: 5) {
                Text(audioManager.currentEpisode?.title ?? "Not Playing")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(audioManager.currentEpisode?.podcast?.title ?? "")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            // Scrubber
            VStack(spacing: 5) {
                Slider(value: .constant(0.3)) // Bind to audioManager.currentTime / duration
                    .tint(.white)
                HStack {
                    Text("12:30").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("-45:00").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 30)
            
            // Controls
            HStack(spacing: 40) {
                Button {
                    // Skip Back
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 30))
                }
                
                Button {
                    audioManager.togglePlayPause()
                } label: {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 50))
                }
                
                Button {
                    // Skip Forward 30
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 30))
                }
            }
            .foregroundStyle(.white)
            
            // Volume
            HStack {
                Image(systemName: "speaker.fill")
                Slider(value: .constant(0.8))
                Image(systemName: "speaker.wave.3.fill")
            }
            .padding(.horizontal, 30)
            //.foregroundStyle(.secondary)
            
            Spacer()
        }
        .background(Color.black.ignoresSafeArea()) // Or extracted color
    }
}

import SwiftUI

struct EpisodeRow: View {
    let episode: Episode
    let artworkColors: ArtworkColors
    
    @Environment(AudioManager.self) private var audioManager
    
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
        .padding(.vertical, 8)
        .contextMenu {
            Button {
                audioManager.addToQueue(episode, next: true)
            } label: {
                Label("Play Next", systemImage: "text.insert")
            }
            
            Button {
                audioManager.addToQueue(episode, next: false)
            } label: {
                Label("Add to Queue", systemImage: "text.append")
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

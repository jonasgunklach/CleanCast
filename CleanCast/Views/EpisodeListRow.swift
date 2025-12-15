import SwiftUI

struct EpisodeListRow: View {
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


import SwiftUI

struct UpNextView: View {
    @Environment(AudioManager.self) private var audioManager
    @Environment(\.dismiss) var dismiss
    @State private var editMode: EditMode = .inactive
    
    var body: some View {
        VStack {
            HStack {
                Text("Up Next")
                    .font(.title2.bold())
                Spacer()
                Button(editMode == .active ? "Done" : "Edit") {
                    withAnimation {
                        editMode = editMode == .active ? .inactive : .active
                    }
                }
            }
            .padding()
            
            if audioManager.upNextQueue.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                    Text("Queue is empty")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Long press episodes to add them here")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else {
                List {
                    ForEach(audioManager.upNextQueue) { episode in
                        HStack(spacing: 12) {
                            if let url = episode.podcast?.imageURL {
                                AsyncImage(url: url) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                }
                                .frame(width: 50, height: 50)
                                .cornerRadius(8)
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 50, height: 50)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(episode.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(2)
                                
                                Text(episode.podcast?.title ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        audioManager.removeFromQueue(at: indexSet)
                    }
                    .onMove { source, destination in
                        audioManager.moveInQueue(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, $editMode)
            }
        }
        .scrollContentBackground(.hidden)
    }
        // Background handled by parent FullPlayerView
        
}


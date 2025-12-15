import SwiftUI

struct TranscriptView: View {
    let episode: Episode
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Transcript")
                    .font(.title2.bold())
                    .padding(.bottom, 8)
                
                if let transcript = episode.transcript, !transcript.isEmpty {
                    Text(transcript)
                        .font(.body)
                        .lineSpacing(4)
                } else {
                    ContentUnavailableView("No Transcript Available", systemImage: "doc.text", description: Text("This episode does not have a transcript."))
                }
            }
            .padding()
        }
    }
}

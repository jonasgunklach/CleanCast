import SwiftUI

/// Displays the transcript synced with playback, highlighting current position and detected ads
struct TranscriptView: View {
    @Environment(AudioManager.self) private var audioManager
    let accentColor: Color?
    
    // Parse transcript into timestamped segments
    private var segments: [TranscriptSegment] {
        guard let transcript = audioManager.currentEpisode?.transcript else { return [] }
        return parseTranscript(transcript)
    }
    
    // Find current segment based on playback time
    private var currentSegmentIndex: Int? {
        let currentTime = audioManager.currentTime
        return segments.firstIndex { seg in
            currentTime >= seg.startTime && currentTime < seg.endTime
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(accentColor ?? .primary)
                Text("Transcript")
                    .font(.title2.bold())
                
                Spacer()
                
                // Status indicator
                if let episode = audioManager.currentEpisode {
                    if let status = episode.adDetectionStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 60)
            
            if segments.isEmpty {
                // No transcript yet
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "waveform")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Transcript will appear here")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Processing audio...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                // Scrollable transcript
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                                TranscriptSegmentRow(
                                    segment: segment,
                                    isCurrentSegment: index == currentSegmentIndex,
                                    isAd: isAdSegment(startTime: segment.startTime, endTime: segment.endTime),
                                    adType: getAdType(at: segment.startTime),
                                    accentColor: accentColor,
                                    onTap: {
                                        audioManager.seek(to: segment.startTime)
                                    }
                                )
                                .id(index)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 100)
                    }
                    .onChange(of: currentSegmentIndex) { _, newIndex in
                        if let index = newIndex {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(index, anchor: .center)
                            }
                        }
                    }
                    .onAppear {
                        // Scroll to current segment when view appears
                        if let index = currentSegmentIndex {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                }
            }
        }
    }
    
    // Check if a line overlaps with an ad segment
    private func isAdSegment(startTime: TimeInterval, endTime: TimeInterval) -> Bool {
        guard let adSegments = audioManager.currentEpisode?.adSegments else { return false }
        return adSegments.contains { ad in
            // Check for overlap: StartA < EndB && EndA > StartB
            startTime < ad.endTime && endTime > ad.startTime
        }
    }
    
    // Get the ad type at a given time
    private func getAdType(at time: TimeInterval) -> String? {
        guard let adSegments = audioManager.currentEpisode?.adSegments else { return nil }
        return adSegments.first { time >= $0.startTime && time < $0.endTime }?.adType
    }
    
    // Parse "[start-end] text" format into segments
    private func parseTranscript(_ transcript: String) -> [TranscriptSegment] {
        let lines = transcript.components(separatedBy: "\n")
        var result: [TranscriptSegment] = []
        
        let pattern = #"\[(\d+)-(\d+)\]\s*(.+)"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        
        for line in lines {
            guard !line.isEmpty else { continue }
            
            if let regex = regex,
               let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
               match.numberOfRanges >= 4 {
                
                let startRange = Range(match.range(at: 1), in: line)!
                let endRange = Range(match.range(at: 2), in: line)!
                let textRange = Range(match.range(at: 3), in: line)!
                
                if let start = Double(line[startRange]),
                   let end = Double(line[endRange]) {
                    let text = String(line[textRange])
                    result.append(TranscriptSegment(startTime: start, endTime: end, text: text))
                }
            } else {
                // Line without timestamp - append to previous or create new
                if !result.isEmpty {
                    result[result.count - 1].text += " " + line
                }
            }
        }
        
        return result
    }
}

struct TranscriptSegment {
    let startTime: TimeInterval
    let endTime: TimeInterval
    var text: String
}

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    let isCurrentSegment: Bool
    let isAd: Bool
    let adType: String?
    let accentColor: Color?
    let onTap: () -> Void
    
    private var adColor: Color {
        switch adType {
        case "paid_ad": return .orange
        case "self_promo": return .purple
        case "cross_promo": return .blue
        case "product_mention": return .gray
        default: return .orange
        }
    }
    
    private var adLabel: String {
        switch adType {
        case "paid_ad": return "💰"
        case "self_promo": return "📢"
        case "cross_promo": return "🎙️"
        case "product_mention": return "📦"
        default: return "💰"
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timestamp
            Text(formatTime(segment.startTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 45, alignment: .trailing)
            
            // Ad indicator
            if isAd {
                Text(adLabel)
                    .font(.caption)
            }
            
            // Text
            Text(segment.text)
                .font(.body)
                .foregroundStyle(isCurrentSegment ? .primary : .secondary)
                .fontWeight(isCurrentSegment ? .medium : .regular)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrentSegment ? (accentColor ?? .blue).opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isAd ? adColor.opacity(0.5) : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    TranscriptView(accentColor: .blue)
        .environment(AudioManager.shared)
}

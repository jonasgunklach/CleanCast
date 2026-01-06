import SwiftUI

/// Displays the transcript synced with playback, highlighting current position and detected ads
struct TranscriptView: View {
    @Environment(AudioManager.self) private var audioManager
    let accentColor: Color?
    
    // Cache segments to avoid re-parsing on every frame
    @State private var segments: [TranscriptSegment] = []
    @State private var lastTranscript: String = ""
    @State private var autoScrollEnabled = true
    
    // Only recalc current index when needed
    // Using a simpler scan or binary search might be better if list is huge,
    // but firstIndex is usually fine for <10k items if efficient.
    // To avoid O(N) every frame, we can memoize or use a heuristic.
    // However, the main lag was likely the string parsing.
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(accentColor ?? .primary)
                Text("Transcript")
                    .font(.title2.bold())
                
                Spacer()
                
                // Toggle autoscroll to allow user freedom
                Button {
                    autoScrollEnabled.toggle()
                } label: {
                    Image(systemName: autoScrollEnabled ? "scroll.fill" : "scroll")
                        .foregroundStyle(autoScrollEnabled ? (accentColor ?? .primary) : .secondary)
                }
                
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
                            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                                TranscriptSegmentRow(
                                    segment: segment,
                                    isCurrentSegment: isCurrent(segment),
                                    isAd: isAdSegment(segment),
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
                    .onChange(of: Int(audioManager.currentTime)) { _, newTime in
                        // Throttle scrolling: only if autoScroll is on
                        if autoScrollEnabled {
                            if let index = segments.firstIndex(where: { Double(newTime) >= $0.startTime && Double(newTime) < $0.endTime }) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(index, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            updateSegments()
        }
        .onChange(of: audioManager.currentEpisode?.id) {
            updateSegments()
        }
        // Poll for transcript updates (if streaming in)
        .onChange(of: audioManager.currentEpisode?.transcript) {
            updateSegments()
        }
    }
    
    private func isCurrent(_ segment: TranscriptSegment) -> Bool {
        let t = audioManager.currentTime
        return t >= segment.startTime && t < segment.endTime
    }
    
    // Optimized check using cached sorted segments potentially, but array scan is ok for lazy render
    // Ad segments are few.
    private func isAdSegment(_ segment: TranscriptSegment) -> Bool {
        guard let adSegments = audioManager.currentEpisode?.adSegments else { return false }
        return adSegments.contains { ad in
            segment.startTime < ad.endTime && segment.endTime > ad.startTime
        }
    }
    
    private func getAdType(at time: TimeInterval) -> String? {
        // Optimize: Don't scan entire array? AdSegments are small usually.
        guard let adSegments = audioManager.currentEpisode?.adSegments else { return nil }
        return adSegments.first { time >= $0.startTime && time < $0.endTime }?.adType
    }
    
    private func updateSegments() {
        guard let transcript = audioManager.currentEpisode?.transcript, transcript != lastTranscript else { return }
        lastTranscript = transcript
        
        // Parse in background to avoid freezing UI
        Task.detached(priority: .userInitiated) {
            let parsed = parseTranscript(transcript)
            await MainActor.run {
                self.segments = parsed
            }
        }
    }
    
    // Parse "[start-end] text" format into segments
    // Using static method to avoid capturing self in Task
    private static func parseTranscript(_ transcript: String) -> [TranscriptSegment] {
        let lines = transcript.components(separatedBy: "\n")
        var result: [TranscriptSegment] = []
        
        let pattern = #"\[(\d+)-(\d+)\]\s*(.+)"#
        // Re-creating regex is expensive, do it once or use simple string manipulation
        // Simple string manipulation is faster than Regex for this simple format
        
        for line in lines {
            guard !line.isEmpty else { continue }
            
            // Expected: "[12-15] Hello world"
            if line.hasPrefix("["), let bracketEnd = line.firstIndex(of: "]") {
                let timestampPart = line[line.index(after: line.startIndex)..<bracketEnd]
                let textPart = line[line.index(after: bracketEnd)...].trimmingCharacters(in: .whitespaces)
                
                let times = timestampPart.split(separator: "-")
                if times.count == 2,
                   let start = Double(times[0]),
                   let end = Double(times[1]) {
                    
                     result.append(TranscriptSegment(startTime: start, endTime: end, text: textPart))
                     continue
                }
            }
            
            // Fallback: Line without timestamp
            if !result.isEmpty {
                result[result.count - 1].text += " " + line
            }
        }
        
        return result
    }
    
    // Wrapper for instance
    private func parseTranscript(_ transcript: String) -> [TranscriptSegment] {
        return Self.parseTranscript(transcript)
    }
}

// Conforming to Equatable/Identifiable can help LazyVStack
struct TranscriptSegment: Identifiable, Equatable {
    let id = UUID()
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

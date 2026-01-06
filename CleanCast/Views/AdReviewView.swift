//
//  AdReviewView.swift
//  CleanCast
//
//  Created by Agency on 26/01.
//

import SwiftUI
import SwiftData

/// A view to review ad detection windows and verify results
struct AdReviewView: View {
    @Environment(AudioManager.self) private var audioManager
    var accentColor: Color?
    
    // For Rating Sheet
    @State private var selectedWindow: WindowRecord?
    @State private var showRatingSheet = false
    @State private var tempRating: Int?
    @State private var tempComment: String = ""
    
    var body: some View {
        VStack {
            // Header (Matches UpNextView)
            HStack {
                Text("Ad Review")
                    .font(.title2.bold())
                Spacer()
                
                // Optional: Helper text or icon
                Image(systemName: "checklist")
                    .foregroundStyle(accentColor ?? .primary)
            }
            .padding()
            .padding(.top, 40)
            
            if let episode = audioManager.currentEpisode,
               let windows = episode.windowRecords?.sorted(by: { $0.startTime < $1.startTime }),
               !windows.isEmpty {
                
                List {
                    ForEach(windows) { window in
                        WindowReviewRow(window: window, episode: episode, accentColor: accentColor)
                            .contentShape(Rectangle()) // Ensure tap area
                            .contextMenu {
                                // Only allow rating if done or failed
                                if window.status == "done" || window.status == "failed" {
                                    Button {
                                        prepareRating(for: window)
                                    } label: {
                                        Label("Rate Detection", systemImage: "star.bubble")
                                    }
                                }
                            }
                            // Only allow long press if done or failed
                            .onLongPressGesture {
                                if window.status == "done" || window.status == "failed" {
                                    prepareRating(for: window)
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                    Text("No ad detection windows")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Analysis hasn't started or is empty")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                Spacer()
            }
        }
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showRatingSheet) {
            RatingSheet(
                rating: $tempRating,
                comment: $tempComment,
                onSubmit: submitRating,
                onCancel: { showRatingSheet = false }
            )
            .presentationDetents([.medium, .fraction(0.6)])
            .presentationDragIndicator(.visible)
        }
    }
    
    private func prepareRating(for window: WindowRecord) {
        selectedWindow = window
        tempRating = window.userRating
        tempComment = window.userComment ?? ""
        showRatingSheet = true
    }
    
    private func submitRating() {
        guard let window = selectedWindow else { return }
        window.userRating = tempRating
        window.userComment = tempComment
        try? window.modelContext?.save()
        showRatingSheet = false
    }
}

// MARK: - Subviews

struct WindowReviewRow: View {
    let window: WindowRecord
    let episode: Episode
    var accentColor: Color?
    
    var adsInWindow: [AdSegment] {
        guard let ads = episode.adSegments else { return [] }
        return ads.filter { ad in
            ad.startTime >= window.startTime && ad.endTime <= window.endTime
        }
        .sorted(by: { $0.startTime < $1.startTime })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Window Header
            HStack {
                Text("Window \(window.windowIndex)")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(formatTimeRange(start: window.startTime, end: window.endTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                StatusBadge(status: window.status)
                
                // Rating Indicator
                if let rating = window.userRating {
                    Image(systemName: rating == 1 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                        .foregroundStyle(rating == 1 ? .green : .red)
                        .font(.caption)
                }
            }
            
            // Content
            if adsInWindow.isEmpty {
                if window.status == "done" {
                    Text("No ads detected")
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else {
                    Text("Analyzing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(adsInWindow) { ad in
                    HStack {
                        Capsule()
                            .fill(accentColor ?? .blue)
                            .frame(width: 4)
                            .padding(.vertical, 2)
                        
                        VStack(alignment: .leading) {
                            Text(ad.brandOrOffer ?? ad.label) // Show Product/Brand if available
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            HStack {
                                Text(ad.adType ?? "Ad")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1), in: Capsule())
                                
                                Text(formatTimeRange(start: ad.startTime, end: ad.endTime))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.leading, 8)
                }
            }
            
            Divider()
                .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }
    
    private func formatTimeRange(start: TimeInterval, end: TimeInterval) -> String {
        return "\(format(start)) - \(format(end))"
    }
    
    private func format(_ seconds: TimeInterval) -> String {
        let min = Int(seconds) / 60
        let sec = Int(seconds) % 60
        return String(format: "%d:%02d", min, sec)
    }
}

struct StatusBadge: View {
    let status: String
    
    var color: Color {
        switch status {
        case "done": return .green
        case "processing": return .orange
        case "failed": return .red
        default: return .gray
        }
    }
    
    var body: some View {
        Text(status.capitalized)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }
}

struct RatingSheet: View {
    @Binding var rating: Int?
    @Binding var comment: String
    let onSubmit: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("How was the detection?") {
                    HStack {
                        Spacer()
                        Button {
                            rating = 1
                        } label: {
                            VStack {
                                Image(systemName: "hand.thumbsup.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(rating == 1 ? .green : .gray.opacity(0.3))
                                Text("Good")
                                    .font(.caption)
                                    .foregroundStyle(rating == 1 ? .green : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Spacer(minLength: 40)
                        
                        Button {
                            rating = 0
                        } label: {
                            VStack {
                                Image(systemName: "hand.thumbsdown.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(rating == 0 ? .red : .gray.opacity(0.3))
                                Text("Bad")
                                    .font(.caption)
                                    .foregroundStyle(rating == 0 ? .red : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.vertical)
                }
                
                Section("Comments (Optional)") {
                    TextField("Any feedback?", text: $comment, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section {
                    Button("Submit Feedback") {
                        onSubmit()
                    }
                    .disabled(rating == nil)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.blue)
                    .foregroundStyle(.white)
                }
            }
            .navigationTitle("Rate Window")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

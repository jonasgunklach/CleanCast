//
//  DetectionConfiguration.swift
//  CleanCast
//
//  Created by Jonas Gunklach on 29.12.25.
//

import Foundation

enum AdDetectionTier: String, CaseIterable, Identifiable {
    case free = "Free"
    case streaming = "Streaming Paid"
    case downloads = "Downloads Paid"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .free: return "Intro processing only (first 5% of episde)"
        case .streaming: return "Progressive ad detection while playing episode"
        case .downloads: return "Full offline ad detection"
        }
    }
}

struct WindowingStrategy {
    let tier: AdDetectionTier
    
    // Window definitions
    static let introWindowPercentage: Double = 0.10
    static let progressiveWindowDuration: TimeInterval = 5 * 60 // 5 minutes
    
    func shouldProcess(windowIndex: Int, totalDuration: TimeInterval, currentPlayhead: TimeInterval? = nil) -> Bool {
        // Intro window (Index 0) - Always processed by all tiers (bootstrapping)
        if windowIndex == 0 { return true }
        
        switch tier {
        case .free:
            // Free tier only does intro
            return false
            
        case .streaming:
            // Streaming tier: Process if within lookahead range
            guard let playhead = currentPlayhead else { return false } // Need playhead for streaming decisions if not initial launch
            
            // Calculate which window the playhead is in
            let playheadWindowIndex = Int(playhead / WindowingStrategy.progressiveWindowDuration)
            
            // Lookahead: Current window + next 2 windows
            let lookaheadRange = playheadWindowIndex...(playheadWindowIndex + 2)
            
            return lookaheadRange.contains(windowIndex)
            
        case .downloads:
            // Download tier: Process everything eventually
            return true
        }
    }
}

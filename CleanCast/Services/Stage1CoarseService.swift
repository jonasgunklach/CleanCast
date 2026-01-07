//
//  Stage1CoarseService.swift
//  CleanCast
//
//  Created by Jonas Gunklach on 29.12.25.
//

import Foundation
import OSLog

/// Output from Stage 1 (Coarse detection)
struct Stage1Result: Sendable {
    let positiveBlocks: [Int] // Indices of 1-minute blocks that likely contain ads
    let rawDecisions: [Int: Bool] // Full map for debug
}

final class Stage1CoarseService: Sendable {
    nonisolated static let shared = Stage1CoarseService()
    
    private let logger = Logger(subsystem: "com.jonasgunklach.CleanCast", category: "Stage1Coarse")
    private let groqChatService = GroqChatService.shared
    
    // Config
    private let model = "llama-3.1-8b-instant" // Fast, efficient 8B model
    // previously gemma2-9b-it
    
    private let minuteChunkDuration: TimeInterval = 60
    
    private init() {}
    
    /// Analyze a 5-minute transcript window in 1-minute chunks to find potential ad regions
    func analyze(transcriptSegments: [GroqWhisperService.SegmentTimestamp],
                 blockStart: TimeInterval,
                 blockDuration: TimeInterval,
                 apiKey: String) async throws -> Stage1Result {
        
        // 1. Split into 1-minute blocks
        let minuteChunks = splitIntoMinutes(segments: transcriptSegments, blockDuration: blockDuration)
        
        if minuteChunks.isEmpty {
            return Stage1Result(positiveBlocks: [], rawDecisions: [:])
        }
        
        logger.info("⚡️ [Stage 1] Analyzing \(minuteChunks.count) chunks with \(self.model)")
        
        // 2. Process in parallel
        var positiveBlocks: [Int] = []
        var rawDecisions: [Int: Bool] = [:]
        
        // Use throwing task group for parallelism
        try await withThrowingTaskGroup(of: (Int, Bool).self) { group in
            for chunk in minuteChunks {
                group.addTask {
                    let hasAd = try await self.detectAdsInChunk(text: chunk.text, apiKey: apiKey)
                    return (chunk.minute, hasAd)
                }
            }
            
            for try await (minute, hasAd) in group {
                rawDecisions[minute] = hasAd
                if hasAd {
                    positiveBlocks.append(minute)
                }
            }
        }
        
        let sortedPositives = positiveBlocks.sorted()
        logger.info("⚡️ [Stage 1] Found suspicious blocks: \(sortedPositives)")
        
        return Stage1Result(positiveBlocks: sortedPositives, rawDecisions: rawDecisions)
    }
    
    private func splitIntoMinutes(segments: [GroqWhisperService.SegmentTimestamp], blockDuration: TimeInterval) -> [(minute: Int, text: String)] {
        var result: [(minute: Int, text: String)] = []
        let maxMinute = Int((blockDuration / minuteChunkDuration).rounded(.up))
        
        for minute in 0..<maxMinute {
            // Whisper timestamps are in relative seconds (0 based).
            // NOTE: Earlier code mentioned "Whisper times are in 2x speed".
            // We need to assume the `transcriptSegments` passed here are already adjusted to REAL TIME or handle the conversion before passing here.
            // **assumption**: Input segments are in REAL TIME seconds relative to blockStart.
            
            let start = Double(minute) * minuteChunkDuration
            let end = start + minuteChunkDuration
            
            let chunkText = segments
                .filter { $0.start >= start && $0.end <= end } // Rough containment
                // Overlap handling: maybe include if midpoint is in range?
                // Better: if intersection > 0.
                // Simple: strict center point check or start time check.
                // Let's use strict containment for simplicity or at least significant overlap.
                // Actually, just checking if 'start' is in range is usually enough for sequential sentences.
                .map { $0.text }
                .joined(separator: " ")
            
            if !chunkText.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append((minute, chunkText))
            }
        }
        return result
    }
    
    private func detectAdsInChunk(text: String, apiKey: String) async throws -> Bool {
        let prompt = """
        Analyze this podcast transcript segment for CLEAR advertisements or sponsorships.
        
        Look for:
        - "This episode is brought to you by..."
        - "Use code X at checkout"
        - "Go to [URL] for 10% off"
        - "Support us on Patreon"
        - "Check out our other show..."
        
        Ignore:
        - Casual mentions of products without call-to-action
        - Guest introductions
        
        Return JSON: {"has_ad": true/false, "likelihood": 0.0-1.0, "tags": ["tag1", "tag2"]}
        
        Transcript:
        \(text)
        """
        
        let response = try await groqChatService.chat(prompt: prompt, apiKey: apiKey, model: model)
        
        // Simple parsing
        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let hasAd = json["has_ad"] as? Bool {
            return hasAd
        }
        
        return response.lowercased().contains("true")
    }
}

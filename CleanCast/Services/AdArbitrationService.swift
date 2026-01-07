//
//  AdArbitrationService.swift
//  CleanCast
//
//  Created by Jonas Gunklach on 29.12.25.
//

import Foundation
import OSLog

final class AdArbitrationService: Sendable {
    nonisolated static let shared = AdArbitrationService()
    private let logger = Logger(subsystem: "com.jonasgunklach.CleanCast", category: "AdArbitration")
    
    private init() {}
    
    /// Arbitrate between two sets of segments (70B vs 120B)
    /// Returns AdSegmentData which can be safely passed across isolation boundaries
    func arbitrate(segmentsA: [AdSegmentData], segmentsB: [AdSegmentData]) -> [AdSegmentData] {
        var finalSegments: [AdSegmentData] = []
        
        // Normalize: Merge segments within 15s in each set first
        let normA = normalize(segmentsA)
        let normB = normalize(segmentsB)
        
        logger.info("⚖️ [Arbitration] A: \(normA.count) vs B: \(normB.count)")
        
        var usedBIndices = Set<Int>()
        
        // 1. Check A against B
        for segA in normA {
            var bestMatchIndex: Int? = nil
            var bestMatchScore: Double = 0
            
            // Find best matching B segment
            for (idxB, segB) in normB.enumerated() {
                if usedBIndices.contains(idxB) { continue }
                
                // Calculate simple overlap duration
                let overlap = calculateOverlap(segA, segB)
                
                // If there is any significant overlap (> 5s), consider it a candidate
                // We pick the one with most overlap
                if overlap > 5 && overlap > bestMatchScore {
                    bestMatchScore = overlap
                    bestMatchIndex = idxB
                }
            }
            
            if let idxB = bestMatchIndex {
                // Merge A and B (Union) -> "Prefer longer ones" logic satisfied by Union
                let segB = normB[idxB]
                let merged = mergeSegments(segA, segB, source: "merged")
                
                finalSegments.append(merged)
                usedBIndices.insert(idxB)
                logger.debug("   Merged A&B (Overlap: \(Int(bestMatchScore))s)")
            } else {
                // Keep A -> "Prefer more ones"
                let segAWithSource = segA.withSource("model-A-only")
                finalSegments.append(segAWithSource)
            }
        }
        
        // 2. Add remaining B -> "Prefer more ones"
        for (idxB, segB) in normB.enumerated() {
            if !usedBIndices.contains(idxB) {
                let segBWithSource = segB.withSource("model-B-only")
                finalSegments.append(segBWithSource)
            }
        }
        
        return normalize(finalSegments) // Final cleanup
    }
    
    private func calculateOverlap(_ s1: AdSegmentData, _ s2: AdSegmentData) -> Double {
        let intersectionStart = max(s1.startTime, s2.startTime)
        let intersectionEnd = min(s1.endTime, s2.endTime)
        
        return max(0, intersectionEnd - intersectionStart)
    }
    
    private func normalize(_ segments: [AdSegmentData]) -> [AdSegmentData] {
        if segments.isEmpty { return [] }
        let sorted = segments.sorted { $0.startTime < $1.startTime }
        var result: [AdSegmentData] = [sorted[0]]
        
        for i in 1..<sorted.count {
            let current = sorted[i]
            let last = result[result.count - 1]
            
            // Merge if gap < 15s or overlapping
            if current.startTime <= last.endTime + 15 {
                // Create merged segment (immutable)
                let mergedEndTime = max(last.endTime, current.endTime)
                var mergedEvidence = last.evidenceExcerpt ?? ""
                if let newEv = current.evidenceExcerpt {
                    if !mergedEvidence.contains(newEv.prefix(15)) {
                        mergedEvidence = mergedEvidence.isEmpty ? newEv : mergedEvidence + " | " + newEv
                    }
                }
                
                let merged = AdSegmentData(
                    startTime: last.startTime,
                    endTime: mergedEndTime,
                    confidence: max(last.confidence, current.confidence),
                    label: last.label,
                    adType: last.adType,
                    source: last.source,
                    firstSentenceId: last.firstSentenceId,
                    lastSentenceId: current.lastSentenceId ?? last.lastSentenceId,
                    firstSentenceText: last.firstSentenceText,
                    lastSentenceText: current.lastSentenceText ?? last.lastSentenceText,
                    evidenceExcerpt: mergedEvidence.isEmpty ? nil : mergedEvidence
                )
                result[result.count - 1] = merged
            } else {
                result.append(current)
            }
        }
        return result
    }
    
    private func mergeSegments(_ s1: AdSegmentData, _ s2: AdSegmentData, source: String) -> AdSegmentData {
        // Union strategy for safety (cover the whole ad)
        let start = min(s1.startTime, s2.startTime)
        let end = max(s1.endTime, s2.endTime)
        
        return AdSegmentData(
            startTime: start,
            endTime: end,
            confidence: max(s1.confidence, s2.confidence),
            label: s1.label,
            adType: s1.adType,
            source: source,
            firstSentenceId: s1.firstSentenceId,
            lastSentenceId: s2.lastSentenceId ?? s1.lastSentenceId,
            firstSentenceText: s1.firstSentenceText,
            lastSentenceText: s2.lastSentenceText ?? s1.lastSentenceText,
            evidenceExcerpt: "A: \(s1.evidenceExcerpt ?? "") | B: \(s2.evidenceExcerpt ?? "")"
        )
    }
}

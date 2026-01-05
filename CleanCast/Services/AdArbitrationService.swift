//
//  AdArbitrationService.swift
//  CleanCast
//
//  Created by Jonas Gunklach on 29.12.25.
//

import Foundation
import OSLog

final class AdArbitrationService {
    static let shared = AdArbitrationService()
    private let logger = Logger(subsystem: "com.jonasgunklach.CleanCast", category: "AdArbitration")
    
    private init() {}
    
    /// Arbitrate between two sets of segments (70B vs 120B)
    func arbitrate(segmentsA: [AdSegment], segmentsB: [AdSegment]) -> [AdSegment] {
        var finalSegments: [AdSegment] = []
        
        // Normalize: Merge segments within 15s in each set first
        let normA = normalize(segmentsA)
        let normB = normalize(segmentsB)
        
        logger.info("⚖️ [Arbitration] A: \(normA.count) vs B: \(normB.count)")
        
        var usedBIndices = Set<Int>()
        
        // 1. Check A against B
        for segA in normA {
            var matchFound = false
            
            for (idxB, segB) in normB.enumerated() {
                if usedBIndices.contains(idxB) { continue }
                
                let iou = calculateIoU(segA, segB)
                
                if iou >= 0.6 {
                    // Strong Agreement
                    let merged = mergeSegments(segA, segB, source: "agree")
                    merged.confidence = max(segA.confidence, segB.confidence) + 0.1 // Boost
                    finalSegments.append(merged)
                    usedBIndices.insert(idxB)
                    matchFound = true
                    logger.debug("   Match (Strong): \(iou)")
                    break
                } else if iou >= 0.3 {
                    // Partial Agreement
                    let merged = mergeSegments(segA, segB, source: "union")
                    merged.confidence = (segA.confidence + segB.confidence) / 2
                    finalSegments.append(merged)
                    usedBIndices.insert(idxB)
                    matchFound = true
                     logger.debug("   Match (Partial): \(iou)")
                    break
                }
            }
            
            if !matchFound {
                // Single Model A
                segA.source = "single-model-A"
                // Default: keep, but maybe flag as lower confidence
                finalSegments.append(segA)
            }
        }
        
        // 2. Add remaining B
        for (idxB, segB) in normB.enumerated() {
            if !usedBIndices.contains(idxB) {
                segB.source = "single-model-B"
                finalSegments.append(segB)
            }
        }
        
        return normalize(finalSegments) // Final cleanup
    }
    
    private func calculateIoU(_ s1: AdSegment, _ s2: AdSegment) -> Double {
        let intersectionStart = max(s1.startTime, s2.startTime)
        let intersectionEnd = min(s1.endTime, s2.endTime)
        
        if intersectionEnd <= intersectionStart { return 0 }
        
        let intersection = intersectionEnd - intersectionStart
        let union = (s1.endTime - s1.startTime) + (s2.endTime - s2.startTime) - intersection
        
        return union > 0 ? intersection / union : 0
    }
    
    private func normalize(_ segments: [AdSegment]) -> [AdSegment] {
        if segments.isEmpty { return [] }
        let sorted = segments.sorted { $0.startTime < $1.startTime }
        var result: [AdSegment] = [sorted[0]]
        
        for i in 1..<sorted.count {
            let current = sorted[i]
            let last = result[result.count - 1]
            
            // Merge if gap < 15s or overlapping
            if current.startTime <= last.endTime + 15 {
                last.endTime = max(last.endTime, current.endTime)
                // Append evidence
                if let newEv = current.evidenceExcerpt {
                    last.evidenceExcerpt = (last.evidenceExcerpt ?? "") + " | " + newEv
                }
            } else {
                result.append(current)
            }
        }
        return result
    }
    
    private func mergeSegments(_ s1: AdSegment, _ s2: AdSegment, source: String) -> AdSegment {
        // Union strategy for safety (cover the whole ad)
        let start = min(s1.startTime, s2.startTime)
        let end = max(s1.endTime, s2.endTime)
        
        return AdSegment(
            startTime: start,
            endTime: end,
            confidence: max(s1.confidence, s2.confidence),
            label: s1.label,
            adType: s1.adType,
            source: source,
            evidenceExcerpt: "A: \(s1.evidenceExcerpt ?? "") | B: \(s2.evidenceExcerpt ?? "")"
        )
    }
}

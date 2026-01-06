//
//  AdSegment.swift
//  CleanCast
//
//  Created by Jonas Gunklach on 11.12.25.
//

import Foundation
import SwiftData

@Model
final class AdSegment {
    var startTime: TimeInterval
    var endTime: TimeInterval
    
    // Rich metadata from Llama detection
    var confidence: Double
    var label: String
    var adType: String?
    var brandOrOffer: String?
    
    // Evidence & Arbitration
    var source: String? // "70b", "120b", "union", "agree", "single-model", "vote"
    
    // Sentence-level evidence for precise validation
    var firstSentenceId: Int?
    var lastSentenceId: Int?
    var firstSentenceText: String?
    var lastSentenceText: String?
    
    var evidenceExcerpt: String?
    var reasoning: String?
    
    // User Verification
    var verificationStatus: VerificationStatus? // nil = unknown, 1 = correct, 0 = incorrect (or use enum)
    
    enum VerificationStatus: Int, Codable {
        case unverified = 0
        case correct = 1
        case incorrect = 2
    }

    
    var episode: Episode?
    
    init(startTime: TimeInterval, 
         endTime: TimeInterval, 
         confidence: Double = 1.0, 
         label: String = "Ad",
         adType: String? = nil,
         brandOrOffer: String? = nil,
         source: String? = nil,
         firstSentenceId: Int? = nil,
         lastSentenceId: Int? = nil,
         firstSentenceText: String? = nil,
         lastSentenceText: String? = nil,
         evidenceExcerpt: String? = nil,
         reasoning: String? = nil) {
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.label = label
        self.adType = adType
        self.brandOrOffer = brandOrOffer
        self.source = source
        self.firstSentenceId = firstSentenceId
        self.lastSentenceId = lastSentenceId
        self.firstSentenceText = firstSentenceText
        self.lastSentenceText = lastSentenceText
        self.evidenceExcerpt = evidenceExcerpt
        self.reasoning = reasoning
    }
}

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
    var evidenceExcerpt: String?
    var reasoning: String?
    
    var episode: Episode?
    
    init(startTime: TimeInterval, 
         endTime: TimeInterval, 
         confidence: Double = 1.0, 
         label: String = "Ad",
         adType: String? = nil,
         brandOrOffer: String? = nil,
         evidenceExcerpt: String? = nil,
         reasoning: String? = nil) {
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.label = label
        self.adType = adType
        self.brandOrOffer = brandOrOffer
        self.evidenceExcerpt = evidenceExcerpt
        self.reasoning = reasoning
    }
}

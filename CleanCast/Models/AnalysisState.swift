//
//  AnalysisState.swift
//  CleanCast
//
//  Created by Jonas Gunklach on 29.12.25.
//

import Foundation
import SwiftData

@Model
final class WindowRecord {
    var id: UUID
    var windowIndex: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
    var isIntro: Bool
    
    // Status: "pending", "processing", "analyzing", "done", "failed"
    var status: String
    var error: String?
    var retryCount: Int
    
    @Relationship(deleteRule: .cascade)
    var transcriptChunk: TranscriptChunk?
    
    var episode: Episode?
    
    init(windowIndex: Int, startTime: TimeInterval, endTime: TimeInterval, isIntro: Bool = false) {
        self.id = UUID()
        self.windowIndex = windowIndex
        self.startTime = startTime
        self.endTime = endTime
        self.isIntro = isIntro
        self.status = "pending"
        self.retryCount = 0
    }
}

@Model
final class TranscriptChunk {
    var text: String
    var segmentsJSON: String // Stores [SegmentTimestamp] as JSON
    var timestamp: Date
    
    @Relationship(inverse: \WindowRecord.transcriptChunk)
    var window: WindowRecord?
    
    init(text: String, segmentsJSON: String) {
        self.text = text
        self.segmentsJSON = segmentsJSON
        self.timestamp = Date()
    }
}

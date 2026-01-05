//
//  Episode.swift
//  CleanCast
//
//  Created by Jonas Gunklach on 11.12.25.
//

import Foundation
import SwiftData

@Model
final class Episode: Identifiable {
    var id: UUID
    var title: String
    var desc: String
    var url: String
    var duration: TimeInterval
    var releaseDate: Date
    
    var playStateRaw: Int // 0: unplayed, 1: inProgress, 2: played
    var progress: TimeInterval
    var isDownloaded: Bool = false
    var localFilePath: String? // Absolute or relative path to downloaded file
    
    // New Features
    var transcript: String?
    var isSaved: Bool = false
    
    // Ad Segments as a Relationship to a separate Model
    @Relationship(deleteRule: .cascade)
    var adSegments: [AdSegment]? = []
    
    // Window-based analysis tracking
    @Relationship(deleteRule: .cascade)
    var windowRecords: [WindowRecord]? = []
    
    var adDetectionStatus: String? // "processing", "completed", "failed"
    var adDetectionError: String?
    
    var podcast: Podcast?
    
    init(title: String, desc: String, url: String, duration: TimeInterval, releaseDate: Date) {
        self.id = UUID()
        self.title = title
        self.desc = desc
        self.url = url
        self.duration = duration
        self.releaseDate = releaseDate
        self.playStateRaw = PlayState.unplayed.rawValue
        self.progress = 0
        self.isDownloaded = false
        self.localFilePath = nil
        self.adSegments = []
        self.windowRecords = []
    }
    
    var playState: PlayState {
        get { PlayState(rawValue: playStateRaw) ?? .unplayed }
        set { playStateRaw = newValue.rawValue }
    }
}

enum PlayState: Int, Codable {
    case unplayed = 0
    case inProgress = 1
    case played = 2
}

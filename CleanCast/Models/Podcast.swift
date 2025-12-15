//
//  Podcast.swift
//  CleanCast
//
//  Created by Jonas Gunklach on 11.12.25.
//

import Foundation
import SwiftUI
import SwiftData

@Model
final class Podcast {
    var id: UUID
    var title: String
    var author: String
    var feedUrl: String
    var imageURL: URL?
    var subscribedDate: Date
    var lastUpdate: Date?
    
    // Hex colors for theming
    var accentColorHex: String?
    var backgroundColorHex: String?
    
    var desc: String?
    var isSubscribed: Bool = true // Added for soft unsubscribe
    
    // New Features
    var totalListenedDuration: TimeInterval = 0 // Track popularity
    var autoDownloadLimit: Int? // Optional per-podcast override
    
    @Relationship(deleteRule: .cascade, inverse: \Episode.podcast)
    var episodes: [Episode]?
    
    init(title: String, author: String, feedUrl: String, imageURL: URL? = nil, desc: String? = nil) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.feedUrl = feedUrl
        self.imageURL = imageURL
        self.desc = desc
        self.subscribedDate = Date()
        self.episodes = []
        self.isSubscribed = true
    }
}

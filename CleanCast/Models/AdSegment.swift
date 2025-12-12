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
    
    var episode: Episode?
    
    init(startTime: TimeInterval, endTime: TimeInterval) {
        self.startTime = startTime
        self.endTime = endTime
    }
}

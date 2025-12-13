import Foundation

/// A thread-safe, Sendable struct for ad segments during detection
struct DetectedAdSegment: Sendable, Codable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
    let label: String
    let adType: String?
    let brandOrOffer: String?
    let evidenceExcerpt: String?
    let reasoning: String?
}

//
//  Stage2RefineService.swift
//  CleanCast
//
//  Created by Jonas Gunklach on 29.12.25.
//

import Foundation
import OSLog

/// Sendable data transfer object for ad segment data (used for cross-isolation boundary transfer)
struct AdSegmentData: Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
    let label: String
    let adType: String?
    let source: String?
    let firstSentenceId: Int?
    let lastSentenceId: Int?
    let firstSentenceText: String?
    let lastSentenceText: String?
    let evidenceExcerpt: String?
    
    /// Convert to AdSegment model (must be called on MainActor if inserting into SwiftData context)
    func toAdSegment() -> AdSegment {
        AdSegment(
            startTime: startTime,
            endTime: endTime,
            confidence: confidence,
            label: label,
            adType: adType,
            source: source,
            firstSentenceId: firstSentenceId,
            lastSentenceId: lastSentenceId,
            firstSentenceText: firstSentenceText,
            lastSentenceText: lastSentenceText,
            evidenceExcerpt: evidenceExcerpt
        )
    }
    
    /// Create a copy with an updated source
    func withSource(_ newSource: String) -> AdSegmentData {
        AdSegmentData(
            startTime: startTime,
            endTime: endTime,
            confidence: confidence,
            label: label,
            adType: adType,
            source: newSource,
            firstSentenceId: firstSentenceId,
            lastSentenceId: lastSentenceId,
            firstSentenceText: firstSentenceText,
            lastSentenceText: lastSentenceText,
            evidenceExcerpt: evidenceExcerpt
        )
    }
}

struct Stage2Result: Sendable {
    let segmentsA: [AdSegmentData] // From model A (70B)
    let segmentsB: [AdSegmentData] // From model B (120B)
}

final class Stage2RefineService: Sendable {
    nonisolated static let shared = Stage2RefineService()
    private let logger = Logger(subsystem: "com.jonasgunklach.CleanCast", category: "Stage2Refine")
    private let groqChatService = GroqChatService.shared
    
    // Models
    private let modelA = "llama-3.3-70b-versatile"
    private let modelB = "openai/gpt-oss-120b" // Based on user provided URL
    
    // For internal reference
    private let model70B = "llama-3.3-70b-versatile"
    private let model120B = "openai/gpt-oss-120b"
    
    private init() {}
    
    /// Refine candidate runs using two large models in parallel
    func refine(
        candidateText: String,
        sentences: [IndexedSentence],
        apiKey: String
    ) async throws -> Stage2Result {
        
        logger.info("🔬 [Stage 2] Refining context (\(candidateText.count) chars) with LLama 70B & OpenAI OSS 120B")
        
        async let resultA = extractSegments(text: candidateText, sentences: sentences, model: model70B, apiKey: apiKey, source: "70b")
        async let resultB = extractSegments(text: candidateText, sentences: sentences, model: model120B, apiKey: apiKey, source: "120b")
        
        // Wait for both
        let (segmentsA, segmentsB) = try await (resultA, resultB)
        
        return Stage2Result(segmentsA: segmentsA, segmentsB: segmentsB)
    }
    
    private func extractSegments(text: String, sentences: [IndexedSentence], model: String, apiKey: String, source: String) async throws -> [AdSegmentData] {
        // Build text with IDs
        var labeledText = ""
        for sentence in sentences {
            labeledText += "[\(sentence.id)] \(sentence.text)\n"
        }
        
        let prompt = """
        You are a precise ad detection engine.
        Analyze the following transcript where each sentence is prefixed with an ID [x].
        Identify start/end sentence IDs of advertisements.
        
        Categories:
        - "paid_ad" (Sponsors, external companies)
        - "self_promo" (Merch, Patreon, live shows)
        - "cross_promo" (Other podcasts)
        
        Strictly output JSON. Return a list of segments defined by their start_id and end_id (inclusive).
        
        Format:
        {
          "segments": [
            {
              "type": "paid_ad",
              "start_id": 12,
              "end_id": 15,
              "confidence": 0.9
            }
          ]
        }
        
        Transcript:
        \(labeledText)
        """
        
        do {
            let jsonString = try await groqChatService.chat(prompt: prompt, apiKey: apiKey, model: model)
            return parseAndValidate(jsonString: jsonString, sentences: sentences, source: source)
        } catch {
            logger.error("❌ [Stage 2] Model \(model) failed: \(error.localizedDescription)")
            return []
        }
    }
    
    private func parseAndValidate(jsonString: String, sentences: [IndexedSentence], source: String) -> [AdSegmentData] {
        guard let data = jsonString.data(using: .utf8),
              let response = try? JSONDecoder().decode(Stage2Response.self, from: data),
              let rawSegments = response.segments else {
            return []
        }
        
        var validated: [AdSegmentData] = []
        
        // create ID lookup map for O(1) access
        let sentenceMap = Dictionary(uniqueKeysWithValues: sentences.map { ($0.id, $0) })
        
        for raw in rawSegments {
            // Validate IDs exist in our window
            if let startNode = sentenceMap[raw.start_id],
               let endNode = sentenceMap[raw.end_id] {
                
                let startTime = startNode.start
                let endTime = endNode.end
                
                if endTime > startTime {
                    validated.append(AdSegmentData(
                        startTime: startTime,
                        endTime: endTime,
                        confidence: raw.confidence,
                        label: raw.type,
                        adType: raw.type,
                        source: source,
                        firstSentenceId: startNode.id,
                        lastSentenceId: endNode.id,
                        firstSentenceText: startNode.text,
                        lastSentenceText: endNode.text,
                        evidenceExcerpt: "\(startNode.text)... \(endNode.text)"
                    ))
                }
            }
        }
        
        return validated
    }
    
    // findBestSentenceMatch is no longer needed but we can keep it private or remove it
    // removing unused function
}

// Helper structures
struct IndexedSentence: Sendable {
    let id: Int
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

private struct Stage2Response: Codable {
    struct RawSegment: Codable {
        let type: String
        let start_id: Int
        let end_id: Int
        let confidence: Double
    }
    let segments: [RawSegment]?
}

//
//  Stage2RefineService.swift
//  CleanCast
//
//  Created by Jonas Gunklach on 29.12.25.
//

import Foundation
import OSLog

struct Stage2Result: Sendable {
    let segmentsA: [AdSegment] // From model A (70B)
    let segmentsB: [AdSegment] // From model B (120B)
}

final class Stage2RefineService {
    static let shared = Stage2RefineService()
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
        
        logger.info("🔬 [Stage 2] Refining context (\(candidateText.count) chars) with 70B & 120B (Mixtral)")
        
        async let resultA = extractSegments(text: candidateText, sentences: sentences, model: model70B, apiKey: apiKey, source: "70b")
        async let resultB = extractSegments(text: candidateText, sentences: sentences, model: model120B, apiKey: apiKey, source: "120b")
        
        // Wait for both
        let (segmentsA, segmentsB) = try await (resultA, resultB)
        
        return Stage2Result(segmentsA: segmentsA, segmentsB: segmentsB)
    }
    
    private func extractSegments(text: String, sentences: [IndexedSentence], model: String, apiKey: String, source: String) async throws -> [AdSegment] {
        let prompt = """
        You are a precise ad detection engine.
        Analyze the following text. Identify start/end sentences of advertisements.
        
        Categories:
        - "paid_ad" (Sponsors, external companies)
        - "self_promo" (Merch, Patreon, live shows)
        - "cross_promo" (Other podcasts)
        - "product_mention" (Organic discussion - use caution)
        
        Strictly output JSON:
        {
          "segments": [
            {
              "type": "paid_ad",
              "first_sentence": "exact text...",
              "last_sentence": "exact text...",
              "confidence": 0.9
            }
          ]
        }
        
        Text:
        \(text.prefix(12000))
        """
        
        do {
            let jsonString = try await groqChatService.chat(prompt: prompt, apiKey: apiKey, model: model)
            return parseAndValidate(jsonString: jsonString, sentences: sentences, source: source)
        } catch {
            logger.error("❌ [Stage 2] Model \(model) failed: \(error.localizedDescription)")
            return []
        }
    }
    
    private func parseAndValidate(jsonString: String, sentences: [IndexedSentence], source: String) -> [AdSegment] {
        guard let data = jsonString.data(using: .utf8),
              let response = try? JSONDecoder().decode(Stage2Response.self, from: data),
              let rawSegments = response.segments else {
            return []
        }
        
        var validated: [AdSegment] = []
        
        for raw in rawSegments {
            // Find best matching sentences in the provided list
            // We use fuzzy matching or exact matching against the `sentences` list
            
            if let startNode = findBestSentenceMatch(query: raw.first_sentence, sentences: sentences),
               let endNode = findBestSentenceMatch(query: raw.last_sentence, sentences: sentences) {
                
                let startTime = startNode.start
                let endTime = endNode.end
                
                if endTime > startTime {
                    validated.append(AdSegment(
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
    
    private func findBestSentenceMatch(query: String, sentences: [IndexedSentence]) -> IndexedSentence? {
        // Simple containment or equality check
        // In product, use Levenshtein or specialized fuzzy matcher
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // 1. Exact match
        if let exact = sentences.first(where: { $0.text.lowercased().contains(cleanedQuery) || cleanedQuery.contains($0.text.lowercased()) }) {
            return exact
        }
        
        // 2. Fallback: first match with significant overlap
        // (Simplified for now)
        return nil
    }
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
        let first_sentence: String
        let last_sentence: String
        let confidence: Double
    }
    let segments: [RawSegment]?
}

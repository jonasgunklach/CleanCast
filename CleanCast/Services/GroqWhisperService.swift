//
//  GroqWhisperService.swift
//  CleanCast
//
//  Created by Jonas Gunklach on 21.11.25.
//

import Foundation
import OSLog

final class GroqWhisperService: Sendable {
    static let shared = GroqWhisperService()
    
    private let logger = Logger(subsystem: "com.jonasgunklach.CleanCast", category: "GroqWhisper")
    private let baseURL = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    
    private let session: URLSession
    
    // MARK: - Timestamp Structures
    
    /// Segment timestamp from Whisper API (sentence-level)
    struct SegmentTimestamp: Codable, Sendable {
        let start: Double  // Start time in seconds (relative to audio start)
        let end: Double    // End time in seconds
        let text: String   // Sentence text
    }
    
    /// Complete transcription result with timestamps
    struct TranscriptionResult: Sendable {
        let text: String
        let segments: [SegmentTimestamp]
    }
    
    private init() {
        // Use ephemeral session to prevent stale connection/local endpoint errors
        // This is crucial for the Simulator's flaky network stack
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        self.session = URLSession(configuration: config)
    }
    
    /// Transcribe audio using Groq's Whisper Large V3 Turbo with segment timestamps
    /// - Parameters:
    ///   - audioData: Audio file data (FLAC, MP3, M4A, MPEG, MPGA, OGG, WAV, or WEBM)
    ///   - apiKey: Groq API key
    ///   - language: Optional language code (auto-detect if nil)
    ///   - prompt: Optional text to guide the model's style or continue a previous audio segment
    /// - Returns: TranscriptionResult with text and segment timestamps
    func transcribe(audioData: Data, apiKey: String, language: String? = nil, prompt: String? = nil) async throws -> TranscriptionResult {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-large-v3-turbo\r\n".data(using: .utf8)!)
        
        // Add response format - use verbose_json to get segment timestamps
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json\r\n".data(using: .utf8)!)
        
        // Request segment-level timestamps (sentence boundaries)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"timestamp_granularities[]\"\r\n\r\n".data(using: .utf8)!)
        body.append("segment\r\n".data(using: .utf8)!)
        
        // Add language parameter if specified (auto-detect if not provided)
        if let language = language {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language)\r\n".data(using: .utf8)!)
        }
        
        // Add prompt if specified
        if let prompt = prompt {
             body.append("--\(boundary)\r\n".data(using: .utf8)!)
             body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
             body.append("\(prompt)\r\n".data(using: .utf8)!)
        }
        
        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let fileSizeMB = Double(audioData.count) / (1024 * 1024)

        // Log silenced per user request (too spammy with chunking)
        // logger.debug("📤 [Whisper] Sending \(String(format: "%.1f", fileSizeMB))MB audio to Groq API")
        
        // Check file size limit (Groq API typically has ~25MB limit)
        if fileSizeMB > 25 {
            logger.error("Audio file too large (\(String(format: "%.1f", fileSizeMB))MB), exceeds API limit")
            throw GroqWhisperAPIError.apiError(413, "File too large: \(String(format: "%.1f", fileSizeMB))MB exceeds 25MB limit")
        }

        // Retry logic for network failures
        var lastError: Error?
        let maxRetries = 3
        let apiCallStart = Date()
        
        for attempt in 1...maxRetries {
            do {
                if attempt > 1 {
                    logger.info("⏱️ [Whisper] Retry attempt \(attempt)/\(maxRetries)")
                }
                let (data, response) = try await session.data(for: request)
                lastError = nil
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw GroqWhisperAPIError.invalidResponse
                }
                
                guard (200..<300).contains(httpResponse.statusCode) else {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    logger.error("Groq Whisper API error: \(httpResponse.statusCode) - \(errorMessage, privacy: .public)")
                    
                    if httpResponse.statusCode == 401 {
                        throw GroqWhisperAPIError.invalidAPIKey
                    } else if httpResponse.statusCode == 429 {
                        throw GroqWhisperAPIError.rateLimitExceeded
                    } else if httpResponse.statusCode == 413 || httpResponse.statusCode == -1017 {
                        throw GroqWhisperAPIError.apiError(httpResponse.statusCode, "File too large for API. Try reducing chunk size.")
                    } else {
                        throw GroqWhisperAPIError.apiError(httpResponse.statusCode, errorMessage)
                    }
                }
                
                // Parse verbose_json response with segment timestamps
                struct WhisperResponse: Codable {
                    let text: String
                    let segments: [WhisperSegment]?
                }
                
                struct WhisperSegment: Codable {
                    let start: Double
                    let end: Double
                    let text: String
                }
                
                let decoder = JSONDecoder()
                let whisperResponse = try decoder.decode(WhisperResponse.self, from: data)
                
                // Convert to our SegmentTimestamp format
                let segments = (whisperResponse.segments ?? []).map { seg in
                    SegmentTimestamp(start: seg.start, end: seg.end, text: seg.text)
                }
                
                let _ = Date().timeIntervalSince(apiCallStart)
                // Log silenced per user request (too spammy with chunking)
                // logger.info("[Whisper] \(segments.count) segments in \(String(format: "%.1f", totalApiTime))s")
                
                return TranscriptionResult(text: whisperResponse.text, segments: segments)
                
            } catch let error as URLError where error.code == .networkConnectionLost || error.code == .notConnectedToInternet || error.code == .timedOut {
                lastError = error
                if attempt < maxRetries {
                    let delay = Double(attempt) * 2.0 // Exponential backoff: 2s, 4s, 6s
                    logger.warning("Network error (attempt \(attempt)/\(maxRetries)), retrying in \(delay)s...")
                    try? await Task.sleep(for: .seconds(delay))
                    continue
                } else {
                    logger.error("Network error after \(maxRetries) attempts: \(error.localizedDescription, privacy: .public)")
                    throw GroqWhisperAPIError.networkError(error)
                }
            } catch {
                // Non-network errors, throw immediately
                throw error
            }
        }
        
        // Should never reach here, but just in case
        if let error = lastError {
            throw GroqWhisperAPIError.networkError(error)
        }
        throw GroqWhisperAPIError.invalidResponse
    }
}

enum GroqWhisperAPIError: LocalizedError {
    case invalidAPIKey
    case rateLimitExceeded
    case invalidResponse
    case apiError(Int, String)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid Groq API key. Please check your API key configuration."
        case .rateLimitExceeded:
            return "Groq API rate limit exceeded. Please try again later."
        case .invalidResponse:
            return "Invalid response from Groq API."
        case .apiError(let code, let message):
            return "Groq API error (\(code)): \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

//
//  GroqChatService.swift
//  CleanCast
//
//  Created by Jonas Gunklach on 21.11.25.
//

import Foundation
import OSLog

final class GroqChatService {
    static let shared = GroqChatService()
    
    private let logger = Logger(subsystem: "com.jonasgunklach.CleanCast", category: "GroqChat")
    private let baseURL = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    
    private init() {}
    
    /// Call Groq chat API for ad detection
    /// - Parameters:
    ///   - prompt: The prompt to send
    ///   - apiKey: Groq API key
    ///   - model: Model to use (default: llama-3.3-70b-versatile - fast and accurate)
    /// - Returns: JSON response content as string
    func chat(prompt: String, apiKey: String, model: String = "llama-3.3-70b-versatile") async throws -> String {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct RequestBody: Codable {
            let model: String
            let messages: [Message]
            let response_format: ResponseFormat?
            let temperature: Double?
        }
        
        struct Message: Codable {
            let role: String
            let content: String
        }
        
        struct ResponseFormat: Codable {
            let type: String
        }
        
        let body = RequestBody(
            model: model,
            messages: [
                Message(role: "user", content: prompt)
            ],
            response_format: ResponseFormat(type: "json_object"),
            temperature: 0.1 // Lower temperature for more consistent JSON output
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        // Configure URLSession with timeout
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        let session = URLSession(configuration: config)
        
        let apiCallStart = Date()
        
        logger.debug("[Groq Chat] Sending request to \(model, privacy: .public)")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GroqChatAPIError.invalidResponse
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("⏱️ [Groq Chat] API error: \(httpResponse.statusCode) - \(errorMessage, privacy: .public)")
            
            if httpResponse.statusCode == 401 {
                throw GroqChatAPIError.invalidAPIKey
            } else if httpResponse.statusCode == 429 {
                throw GroqChatAPIError.rateLimitExceeded
            } else {
                throw GroqChatAPIError.apiError(httpResponse.statusCode, errorMessage)
            }
        }
        
        // Log slow requests removed - networkTime was unused
        
        // Parse response
        struct APIResponse: Codable {
            let choices: [Choice]
        }
        
        struct Choice: Codable {
            let message: Message
        }
        
        let parseStart = Date()
        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
        guard let content = apiResponse.choices.first?.message.content else {
            logger.warning("No content in Groq response")
            throw GroqChatAPIError.invalidResponse
        }
        
        let _ = Date().timeIntervalSince(parseStart)
        let totalTime = Date().timeIntervalSince(apiCallStart)
        logger.debug("[Groq Chat] \(model, privacy: .public) complete: \(String(format: "%.2f", totalTime))s")
        
        return content
    }
}

enum GroqChatAPIError: LocalizedError {
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

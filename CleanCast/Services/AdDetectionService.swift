//
//  AdDetectionService.swift
//  CleanCast
//
//  Created by Jonas Gunklach on 21.11.25.
//

import Foundation
import AVFoundation
import OSLog

struct EpisodeDetectionContext: Sendable {
    let id: UUID
    let title: String
    let audioURL: String
    let isDownloaded: Bool
    let localFilePath: String?
}

private struct ChunkResult: Sendable {
    let index: Int
    let transcript: String
    let segments: [AdSegment]
}

final class AdDetectionService {
    static let shared = AdDetectionService()
    
    private let logger = Logger(subsystem: "com.jonasgunklach.CleanCast", category: "AdDetection")
    private let groqWhisperService = GroqWhisperService.shared
    private let groqChatService = GroqChatService.shared
    private let settingsManager = SettingsManager.shared
    
    // Models for two-stage detection
    private let filterModel = "llama-3.1-8b-instant"      // Fast model for yes/no detection
    private let precisionModel = "llama-3.3-70b-versatile" // Accurate model for timestamps
    
    // Chunk size for ad detection (1 minute chunks for yes/no detection)
    private let adCheckChunkDuration: TimeInterval = 60 // 1 minute per chunk for Stage 1
    
    private init() {}
    
    // MARK: - Public API
    
    /// Analyze episode for ad segments using two-stage Groq Llama detection
    /// Stage 1: Llama 8B for quick yes/no ad detection on 1-minute chunks
    /// Stage 2: Llama 70B for accurate timestamps on identified ad segments
    func analyze(context: EpisodeDetectionContext, episode: Episode? = nil, timeout: TimeInterval = 300) async throws -> [AdSegment] {
        logger.info("Starting ad detection for episode: \(context.title, privacy: .public)")
        
        // Check if already processed
        if let episode = episode, episode.adDetectionStatus == "completed", let segments = episode.adSegments, !segments.isEmpty {
            logger.info("Using existing ad segments: \(segments.count) segments")
            return segments
        }
        
        // Update status
        await MainActor.run {
            updateEpisodeStatus(episode, status: "processing", error: nil)
        }
        
        // Check API key
        guard let groqKey = settingsManager.groqAPIKey else {
            let error = "Groq API key not configured. Set GROQ_API_KEY environment variable."
            logger.error("\(error, privacy: .public)")
            await MainActor.run {
                updateEpisodeStatus(episode, status: "failed", error: error)
            }
            throw NSError(domain: "AdDetection", code: -1, userInfo: [NSLocalizedDescriptionKey: error])
        }
        
        // Get local file
        guard let localURL = await ensureLocalFile(for: context) else {
            let error = "Unable to get local file for episode"
            logger.error("\(error, privacy: .public)")
            await MainActor.run {
                updateEpisodeStatus(episode, status: "failed", error: error)
            }
            throw NSError(domain: "AdDetection", code: -2, userInfo: [NSLocalizedDescriptionKey: error])
        }
        
        let asset = AVURLAsset(url: localURL)
        let isTempFile = localURL.path.contains(FileManager.default.temporaryDirectory.path) && 
                         localURL.path.contains("ad-detection-")
        
        let overallStart = Date()
        var allDetectedSegments: [DetectedAdSegment] = []
        
        do {
            // Get episode duration
            let duration = try await asset.load(.duration).seconds
            logger.info("Episode duration: \(String(format: "%.1f", duration))s")
            
            // Process in 10-minute blocks
            let blockDuration: TimeInterval = 10 * 60 // 10 minutes per block
            var blockStart: TimeInterval = 0
            
            while blockStart < duration {
                let blockEnd = min(blockStart + blockDuration, duration)
                let actualBlockDuration = blockEnd - blockStart
                
                logger.info("Processing block: \(String(format: "%.0f", blockStart))s - \(String(format: "%.0f", blockEnd))s")
                
                // Process this block with two-stage detection
                let blockSegments = try await processBlockWithTwoStageDetection(
                    asset: asset,
                    blockStart: blockStart,
                    blockDuration: actualBlockDuration,
                    groqKey: groqKey
                )
                
                allDetectedSegments.append(contentsOf: blockSegments)
                blockStart = blockEnd
            }
            
            // Apply intelligent merging on DTOs
            let finalDetectedSegments = mergeAndAdjustSegments(allDetectedSegments, episodeDuration: duration)
            
            logger.info("Final result: \(finalDetectedSegments.count) ad segments after merging")
            var convertedSegments: [AdSegment] = []
            
            // Store results in episode
            await MainActor.run {
                // Convert DTOs to Model objects on MainActor
                convertedSegments = finalDetectedSegments.map { convertToModel($0) }
                
                if let episode = episode {
                    episode.adSegments = convertedSegments
                    episode.adDetectionStatus = "completed"
                    episode.adDetectionError = nil
                }
            }
            
            let totalElapsed = Date().timeIntervalSince(overallStart)
            logger.info("⏱️ Total ad detection time: \(String(format: "%.2f", totalElapsed))s")
            
            // Clean up temp file
            if isTempFile {
                cleanupTempFile(at: localURL)
            }
            
            return convertedSegments
            
        } catch {
            logger.error("Ad detection failed: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                updateEpisodeStatus(episode, status: "failed", error: error.localizedDescription)
            }
            
            if isTempFile {
                cleanupTempFile(at: localURL)
            }
            
            throw error
        }
    }
    
    /// Analyze a specific time range (for streaming) using two-stage Llama detection
    /// - Parameters:
    ///   - processedAudioURL: Optional pre-processed audio file (compressed/speeded up)
    ///   - episodeDuration: Total episode duration for merging adjustments
    func analyzeChunk(
        context: EpisodeDetectionContext,
        startTime: TimeInterval,
        duration: TimeInterval,
        episode: Episode? = nil,
        processedAudioURL: URL? = nil,
        episodeDuration: TimeInterval = 0
    ) async throws -> [AdSegment] {
        let chunkStart = Date()
        logger.info("⏱️ [analyzeChunk] Starting: \(startTime, privacy: .public)s - \(startTime + duration, privacy: .public)s")
        
        guard let groqKey = settingsManager.groqAPIKey else {
            throw NSError(domain: "AdDetection", code: -1, userInfo: [NSLocalizedDescriptionKey: "Groq API key not configured"])
        }
        
        let audioData: Data
        let isSpedUp: Bool
        
        if let processedURL = processedAudioURL {
            // Use pre-processed audio file directly (already 2x speed)
            logger.info("⏱️ [analyzeChunk] Loading pre-processed audio file...")
            audioData = try Data(contentsOf: processedURL)
            isSpedUp = true
        } else {
            // Check for local file first
            if context.isDownloaded, let path = context.localFilePath, FileManager.default.fileExists(atPath: path) {
                 let localURL = URL(fileURLWithPath: path)
                 let asset = AVURLAsset(url: localURL)
                 guard let extractedData = try await extractAudioChunk(asset: asset, start: startTime, duration: duration) else {
                     throw NSError(domain: "AdDetection", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to extract locally"])
                 }
                 audioData = extractedData
            } else if let remoteURL = URL(string: context.audioURL) {
                 // Optimization: Manually download first chunk (~15MB for ~5-10m) to avoid AVAssetExportSession remote limits
                 logger.info("STOP: Downloading partial remote file for chunk extraction")
                 
                 // Estimate bytes for duration (assuming 192kbps safe upper bound + overhead)
                 // 300 seconds * 24KB/s = 7.2MB. Let's grab 15MB to be safe and cover VBR spikes.
                 let bytesToDownload: Int64 = 15 * 1024 * 1024 // 15 MB
                 
                 guard let localPartialURL = try await downloadPartialAudio(url: remoteURL, limitBytes: bytesToDownload) else {
                     throw NSError(domain: "AdDetection", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to download partial audio"])
                 }
                 
                 defer {
                     try? FileManager.default.removeItem(at: localPartialURL)
                 }
                 
                 let asset = AVURLAsset(url: localPartialURL)
                 guard let extractedData = try await extractAudioChunk(asset: asset, start: startTime, duration: duration) else {
                     throw NSError(domain: "AdDetection", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to extract from partial local file"])
                 }
                 audioData = extractedData
            } else {
                 throw NSError(domain: "AdDetection", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
             
            isSpedUp = false
        }
        
        // Transcribe with Groq Whisper
        let whisperStart = Date()
        logger.info("⏱️ [analyzeChunk] Transcribing with Groq Whisper...")
        let transcript = try await groqWhisperService.transcribe(audioData: audioData, apiKey: groqKey)
        let whisperTime = Date().timeIntervalSince(whisperStart)
        logger.info("⏱️ [analyzeChunk] Whisper transcription: \(String(format: "%.2f", whisperTime))s")
        
        // Two-stage detection using Llama
        let segments = try await twoStageAdDetection(
            transcript: transcript,
            chunkStartTime: startTime,
            chunkDuration: duration,
            isSpedUp: isSpedUp,
            groqKey: groqKey
        )
        
        // Apply timestamp adjustment for sped-up audio
        let adjustedSegments: [DetectedAdSegment]
        if isSpedUp {
            // Audio was 2x speed, multiply timestamps by 2 and add chunk start time
            adjustedSegments = segments.map { segment in
                DetectedAdSegment(
                    startTime: (segment.startTime * 2) + startTime,
                    endTime: (segment.endTime * 2) + startTime,
                    confidence: segment.confidence,
                    label: segment.label,
                    adType: segment.adType,
                    brandOrOffer: segment.brandOrOffer,
                    evidenceExcerpt: segment.evidenceExcerpt,
                    reasoning: segment.reasoning
                )
            }
        } else {
            // Add chunk start time to segment timestamps
            adjustedSegments = segments.map { segment in
                DetectedAdSegment(
                    startTime: segment.startTime + startTime,
                    endTime: segment.endTime + startTime,
                    confidence: segment.confidence,
                    label: segment.label,
                    adType: segment.adType,
                    brandOrOffer: segment.brandOrOffer,
                    evidenceExcerpt: segment.evidenceExcerpt,
                    reasoning: segment.reasoning
                )
            }
        }
        
        // Apply intelligent merging
        let effectiveDuration = episodeDuration > 0 ? episodeDuration : (startTime + duration)
        let finalSegments = mergeAndAdjustSegments(adjustedSegments, episodeDuration: effectiveDuration)
        
        var convertedSegments: [AdSegment] = []
        
        // Merge with existing segments in episode
        if let episode = episode {
            await MainActor.run {
                convertedSegments = finalSegments.map { convertToModel($0) }
                var existing = episode.adSegments ?? []
                existing.append(contentsOf: convertedSegments)
                // We need to re-merge model objects here or convert back/forth. 
                // Simple approach: just append. The main loop merges DTOs properly. 
                // For partial chunk, simple append is "OK" but let's try to merge properly if we extracted DTOs from existing.
                // But existing are Model objects. Let's just append for now to be safe.
                episode.adSegments = existing // Naive merge for chunk updates
            }
        } else {
             convertedSegments = finalSegments.map { convertToModel($0) } // Convert if no episode to attach to immediately
        }
        
        let totalTime = Date().timeIntervalSince(chunkStart)
        logger.info("⏱️ [analyzeChunk] Total time: \(String(format: "%.2f", totalTime))s - Found \(convertedSegments.count) ad segments")
        
        return convertedSegments
    }
    
    /// Merge segments that are ≤10 seconds apart and extend to start/end if ≤10 seconds away
    func mergeAndAdjustSegments(_ segments: [DetectedAdSegment], episodeDuration: TimeInterval) -> [DetectedAdSegment] {
        guard !segments.isEmpty else { return [] }
        
        // Sort segments by start time
        let sorted = segments.sorted { $0.startTime < $1.startTime }
        var merged: [DetectedAdSegment] = []
        
        for segment in sorted {
            if let last = merged.last {
                // Merge if segments are ≤10 seconds apart or overlapping
                let gap = segment.startTime - last.endTime
                if gap <= 10 {
                    // Merge segments
                    let mergedSegment = DetectedAdSegment(
                        startTime: last.startTime,
                        endTime: max(last.endTime, segment.endTime),
                        confidence: max(last.confidence, segment.confidence),
                        label: last.label,
                        adType: last.adType ?? segment.adType,
                        brandOrOffer: last.brandOrOffer ?? segment.brandOrOffer,
                        evidenceExcerpt: last.evidenceExcerpt ?? segment.evidenceExcerpt,
                        reasoning: last.reasoning ?? segment.reasoning
                    )
                    merged[merged.count - 1] = mergedSegment
                } else {
                    merged.append(segment)
                }
            } else {
                merged.append(segment)
            }
        }
        
        // Extend first segment to start if ≤10 seconds from beginning
        if let first = merged.first, first.startTime <= 10 {
            merged[0] = DetectedAdSegment(
                startTime: 0,
                endTime: first.endTime,
                confidence: first.confidence,
                label: first.label,
                adType: first.adType,
                brandOrOffer: first.brandOrOffer,
                evidenceExcerpt: first.evidenceExcerpt,
                reasoning: first.reasoning
            )
        }
        
        // Extend last segment to end if ≤10 seconds from episode end
        if let last = merged.last, episodeDuration > 0, (episodeDuration - last.endTime) <= 10 {
            merged[merged.count - 1] = DetectedAdSegment(
                startTime: last.startTime,
                endTime: episodeDuration,
                confidence: last.confidence,
                label: last.label,
                adType: last.adType,
                brandOrOffer: last.brandOrOffer,
                evidenceExcerpt: last.evidenceExcerpt,
                reasoning: last.reasoning
            )
        }
        
        return merged
    }
    
    // MARK: - Two-Stage Detection
    
    /// Process a block with two-stage Llama detection
    private func processBlockWithTwoStageDetection(
        asset: AVAsset,
        blockStart: TimeInterval,
        blockDuration: TimeInterval,
        groqKey: String
    ) async throws -> [DetectedAdSegment] {
        // Extract audio for this block
        guard let audioData = try await extractAudioChunk(asset: asset, start: blockStart, duration: blockDuration) else {
            logger.warning("Failed to extract block at \(blockStart)s, skipping")
            return []
        }
        
        // Transcribe with Groq Whisper
        let transcript = try await groqWhisperService.transcribe(audioData: audioData, apiKey: groqKey)
        
        // Run two-stage detection
        return try await twoStageAdDetection(
            transcript: transcript,
            chunkStartTime: blockStart,
            chunkDuration: blockDuration,
            isSpedUp: false,
            groqKey: groqKey
        )
    }
    
    /// Two-stage ad detection:
    /// Stage 1: Split transcript into ~1 minute chunks, use Llama 8B for quick yes/no
    /// Stage 2: For chunks with ads, use Llama 70B to get accurate timestamps
    private func twoStageAdDetection(
        transcript: String,
        chunkStartTime: TimeInterval,
        chunkDuration: TimeInterval,
        isSpedUp: Bool,
        groqKey: String
    ) async throws -> [DetectedAdSegment] {
        // Split transcript into ~1 minute chunks (estimate: ~150 words per minute)
        let wordsPerMinute = 150
        let words = transcript.split(separator: " ")
        let totalWords = words.count
        
        // If transcript is short enough, process as single chunk
        if totalWords <= wordsPerMinute * 2 {
            // Process entire transcript at once
            let hasAd = try await checkForAds(transcript: transcript, groqKey: groqKey)
            if hasAd {
                return try await getAdTimestamps(
                    transcript: transcript,
                    chunkStartTime: 0, // Relative to this chunk
                    chunkDuration: chunkDuration,
                    isSpedUp: isSpedUp,
                    groqKey: groqKey
                )
            }
            return []
        }
        
        // Split into 1-minute chunks for Stage 1
        // Make struct Sendable for task group
        struct ChunkData: Sendable {
            let text: String
            let startMinute: Int
        }
        
        var minuteChunks: [ChunkData] = []
        var currentChunk: [String.SubSequence] = []
        var currentMinute = 0
        
        for (index, word) in words.enumerated() {
            currentChunk.append(word)
            
            if currentChunk.count >= wordsPerMinute || index == words.count - 1 {
                minuteChunks.append(ChunkData(text: currentChunk.joined(separator: " "), startMinute: currentMinute))
                currentChunk = []
                currentMinute += 1
            }
        }
        
        logger.info("Stage 1: Checking \(minuteChunks.count) minute-chunks with Llama 8B")
        
        // Stage 1: Quick yes/no check with Llama 8B (parallel)
        var chunksWithAds: [ChunkData] = []
        
        try await withThrowingTaskGroup(of: (Int, Bool).self) { group in
            for (index, chunk) in minuteChunks.enumerated() {
                group.addTask {
                    let hasAd = try await self.checkForAds(transcript: chunk.text, groqKey: groqKey)
                    return (index, hasAd)
                }
            }
            
            for try await (index, hasAd) in group {
                if hasAd {
                    chunksWithAds.append(minuteChunks[index])
                }
            }
        }
        
        logger.info("Stage 1 complete: \(chunksWithAds.count)/\(minuteChunks.count) chunks contain ads")
        
        if chunksWithAds.isEmpty {
            return []
        }
        
        // Stage 2: Get accurate timestamps for chunks with ads using Llama 70B (parallel)
        var allSegments: [DetectedAdSegment] = []
        
        try await withThrowingTaskGroup(of: [DetectedAdSegment].self) { group in
            for chunk in chunksWithAds {
                group.addTask {
                    let minuteStartTime = TimeInterval(chunk.startMinute * 60)
                    let segments = try await self.getAdTimestamps(
                        transcript: chunk.text,
                        chunkStartTime: minuteStartTime,
                        chunkDuration: 60, // 1 minute
                        isSpedUp: isSpedUp,
                        groqKey: groqKey
                    )
                    return segments
                }
            }
            
            for try await segments in group {
                allSegments.append(contentsOf: segments)
            }
        }
        
        logger.info("Stage 2 complete: Found \(allSegments.count) ad segments total")
        
        return allSegments
    }
    
    /// Stage 1: Quick yes/no ad check using Llama 8B
    private func checkForAds(transcript: String, groqKey: String) async throws -> Bool {
        let prompt = """
        You are an ad detector. Analyze this podcast transcript and determine if it contains any advertisements.

        An ad is any segment where speakers clearly promote or recommend:
        - Products, services, apps, brands
        - Sponsor mentions ("brought to you by", discount codes, special offers)
        - Self-promotion (Patreon, Discord, merch, newsletter, premium content)
        - Cross-promotion of other podcasts

        Respond with ONLY a JSON object: {"has_ad": true} or {"has_ad": false}

        Transcript:
        \(transcript.prefix(4000))
        """
        
        let response = try await groqChatService.chat(prompt: prompt, apiKey: groqKey, model: filterModel)
        
        // Parse response
        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let hasAd = json["has_ad"] as? Bool {
            return hasAd
        }
        
        // Default to true to be safe
        return response.lowercased().contains("true")
    }
    
    /// Stage 2: Get accurate ad timestamps using Llama 70B
    private func getAdTimestamps(
        transcript: String,
        chunkStartTime: TimeInterval,
        chunkDuration: TimeInterval,
        isSpedUp: Bool,
        groqKey: String
    ) async throws -> [DetectedAdSegment] {
        let speedNote = isSpedUp ? """
        
        IMPORTANT: The audio was processed at 2x speed. Return timestamps as if the audio was at normal speed.
        The transcript represents \(String(format: "%.0f", chunkDuration)) seconds of original audio.
        """ : ""
        
        let prompt = """
        You are an ad detector. Analyze this podcast transcript and identify the exact timestamps of advertisements.

        An ad is any segment where speakers clearly promote or recommend:
        - Products, services, apps, brands
        - Sponsor mentions ("brought to you by", discount codes, special offers)
        - Self-promotion (Patreon, Discord, merch, newsletter, premium content)
        - Cross-promotion of other podcasts

        This transcript chunk starts at \(String(format: "%.0f", chunkStartTime)) seconds.
        Duration of this chunk: \(String(format: "%.0f", chunkDuration)) seconds.
        \(speedNote)

        Return a JSON object with this format:
        {
            "segments": [
                {
                    "start_time": <seconds from chunk start>,
                    "end_time": <seconds from chunk start>,
                    "confidence": <0.0-1.0>,
                    "ad_type": "host_read_ad" | "dynamic_audio_ad" | "self_promotion" | "embedded_brand_mention",
                    "brand_or_offer": "<brand name or unknown>",
                    "evidence_excerpt": "<short quote from ad>",
                    "reasoning": "<why this is an ad>"
                }
            ]
        }

        If no ads found, return: {"segments": []}

        Transcript:
        \(transcript.prefix(6000))
        """
        
        let response = try await groqChatService.chat(prompt: prompt, apiKey: groqKey, model: precisionModel)
        
        // Parse response
        guard let data = response.data(using: .utf8) else {
            return []
        }
    
        // Try parsing with custom struct
        struct TimestampResponse: Codable {
            let segments: [SegmentJSON]?
        }
        
        struct SegmentJSON: Codable {
            let start_time: Double
            let end_time: Double
            let confidence: Double?
            let ad_type: String?
            let brand_or_offer: String?
            let evidence_excerpt: String?
            let reasoning: String?
        }
        
        if let parsed = try? JSONDecoder().decode(TimestampResponse.self, from: data),
           let segments = parsed.segments {
            return segments.map { seg in
                DetectedAdSegment(
                    startTime: seg.start_time,
                    endTime: seg.end_time,
                    confidence: seg.confidence ?? 0.8,
                    label: seg.ad_type ?? "Ad",
                    adType: seg.ad_type,
                    brandOrOffer: seg.brand_or_offer,
                    evidenceExcerpt: seg.evidence_excerpt,
                    reasoning: seg.reasoning
                )
            }
        }
        
        return []
    }
    
    // MARK: - Audio Extraction
    
    private func extractAudioChunk(asset: AVAsset, start: TimeInterval, duration: TimeInterval) async throws -> Data? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ad-chunk-\(UUID().uuidString).m4a")
        

        
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            logger.error("Failed to create AVAssetExportSession")
            return nil
        }
        
        exporter.outputURL = tempURL
        exporter.outputFileType = .m4a
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        
        // Use a detached task to avoid capturing non-Sendable exporter in a way that Swift 6 dislikes?
        // Actually, just awaiting the export inside this actor-isolated function should be fine 
        // IF we don't pass exporter to a separate unstructured Task closure that escapes.
        // The export() helper I wrote uses a closure for the older API.
        
        try await export(assetExporter: exporter)
        
        guard let audioData = try? Data(contentsOf: tempURL) else {
            logger.error("Failed to read exported audio data")
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
        
        try? FileManager.default.removeItem(at: tempURL)
        return audioData
    }
    
    // MARK: - Helper Methods
    
    private func convertToModel(_ dto: DetectedAdSegment) -> AdSegment {
        // Must be called on MainActor if AdSegment is bound to a context, but here AdSegment init is just an object.
        // However, standard says @Model classes are MainActor bound often. 
        // We will call this from MainActor block in analyze().
        return AdSegment(
            startTime: dto.startTime,
            endTime: dto.endTime,
            confidence: dto.confidence,
            label: dto.label,
            adType: dto.adType,
            brandOrOffer: dto.brandOrOffer,
            evidenceExcerpt: dto.evidenceExcerpt,
            reasoning: dto.reasoning
        )
    }
    
    private func ensureLocalFile(for context: EpisodeDetectionContext) async -> URL? {
        if context.isDownloaded, let path = context.localFilePath {
            let fileURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                return fileURL
            }
        }
        
        guard let remoteURL = URL(string: context.audioURL) else {
            return nil
        }
        
        logger.info("Downloading episode temporarily for ad detection: \(context.title, privacy: .public)")
        
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent("ad-detection-\(context.id.uuidString).mp3")
            
            try? FileManager.default.removeItem(at: tempFile)
            
            let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
            try FileManager.default.moveItem(at: tempURL, to: tempFile)
            
            return tempFile
        } catch {
            logger.error("Failed to download episode: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    private func cleanupTempFile(at url: URL) {
        guard url.path.contains(FileManager.default.temporaryDirectory.path) &&
              url.path.contains("ad-detection-") else { return }
        
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logger.error("Failed to clean up temp file: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func export(assetExporter: AVAssetExportSession) async throws {
        guard let outputURL = assetExporter.outputURL,
              let outputFileType = assetExporter.outputFileType else {
            throw NSError(domain: "AdDetection", code: -2, userInfo: [NSLocalizedDescriptionKey: "Export output URL or file type is nil"])
        }
        
        if #available(iOS 18.0, *) {
            try await assetExporter.export(to: outputURL, as: outputFileType)
        } else {
            // To avoid capture of non-Sendable assetExporter in closure:
            // We can wait in a loop or use KVO, but simple way is just using the closure carefully.
            // If strict 6 mode complains, we can verify if AVAssetExportSession is actually not sendable. 
            // It is not. But we are in a non-isolated or actor context? AdDetectionService is final class -> non-isolated by default unless global actor.
            // Let's assume we can suppress or just ignore if it works, BUT user complained.
            // Fix: Use the Polling or Timer approach if closure capture is banned? No, just use 'await' if possible.
            // The available(iOS 18) covers new devices. For older...
            // We can capture it if we ensure we don't cross boundaries.
            
            await assetExporter.export()
            if let error = assetExporter.error {
                 throw error
            }
        }
    }
    
    private func updateEpisodeStatus(_ episode: Episode?, status: String, error: String?) {
        Task { @MainActor in
            episode?.adDetectionStatus = status
            episode?.adDetectionError = error
        }
    }

    /// Manually download the first N bytes of a remote file to a temp location
    private func downloadPartialAudio(url: URL, limitBytes: Int64) async throws -> URL? {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-\(limitBytes)", forHTTPHeaderField: "Range")
        
        let tempDir = FileManager.default.temporaryDirectory
        // Use mp3 extension as generic container; AVURLAsset handles content sniffing usually
        let tempFile = tempDir.appendingPathComponent("partial-ad-check-\(UUID().uuidString).mp3")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, 
           (200...299).contains(httpResponse.statusCode) {
            try data.write(to: tempFile)
            return tempFile
        }
        
        return nil
    }
}

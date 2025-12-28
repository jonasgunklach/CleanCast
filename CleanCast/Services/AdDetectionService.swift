//
//  AdDetectionService.swift
//  CleanCast
//
//  Created by Jonas Gunklach on 21.11.25.
//

import Foundation
import AVFoundation
import OSLog
import UIKit

struct EpisodeDetectionContext: Sendable {
    let id: UUID
    let title: String
    let audioURL: String
    let isDownloaded: Bool
    let localFilePath: String?
}

/// Wrapper for unsafe sendable values (for AVAssetWriter callbacks)
private struct UnsafeSendable<T>: @unchecked Sendable {
    let value: T
}

/// Sendable DTO for ad segment data (used internally before converting to SwiftData model)
private struct AdSegmentData: Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
    let label: String
    let adType: String?
    let brandOrOffer: String?
    let evidenceExcerpt: String?
    let reasoning: String?
    
    func toAdSegment() -> AdSegment {
        AdSegment(
            startTime: startTime,
            endTime: endTime,
            confidence: confidence,
            label: label,
            adType: adType,
            brandOrOffer: brandOrOffer,
            evidenceExcerpt: evidenceExcerpt,
            reasoning: reasoning
        )
    }
}

/// Whisper segment with absolute episode timestamps (for cross-block padding)
private struct AbsoluteSegment: Sendable {
    let start: TimeInterval  // Absolute episode time
    let end: TimeInterval    // Absolute episode time
    let text: String
}

final class AdDetectionService {
    static let shared = AdDetectionService()
    
    private let logger = Logger(subsystem: "com.jonasgunklach.CleanCast", category: "AdDetection")
    private let groqWhisperService = GroqWhisperService.shared
    private let groqChatService = GroqChatService.shared
    private let settingsManager = SettingsManager.shared
    
    // Models for two-stage detection
    private let filterModel = "llama-3.1-8b-instant"       // Fast model for yes/no detection
    private let precisionModel = "llama-3.3-70b-versatile" // Accurate model for timestamps
    
    // Configuration
    private let blockDuration: TimeInterval = 5 * 60  // 5-minute blocks for Whisper (optimized for speed)
    private let minuteChunkDuration: TimeInterval = 60 // 1-minute chunks for Stage 1
    private let paddingDuration: TimeInterval = 45     // 45 second padding for Stage 2
    
    private init() {}
    
    // MARK: - Public API
    
    /// Analyze episode for ad segments using two-stage Groq Llama detection
    /// Stage 1: Llama 8B for quick yes/no ad detection on 1-minute chunks
    /// Stage 2: Llama 70B for accurate timestamps on identified ad segments
    func analyze(context: EpisodeDetectionContext, episode: Episode? = nil, timeout: TimeInterval = 300) async throws -> [AdSegment] {
        logger.info("🚀 [AdDetection] Starting detection for: \(context.title, privacy: .public)")
        
        // Check if already processed
        if let episode = episode, episode.adDetectionStatus == "completed", let segments = episode.adSegments, !segments.isEmpty {
            logger.info("♻️ [AdDetection] Using cached \(segments.count) ad segments")
            return segments
        }
        
        await MainActor.run { updateEpisodeStatus(episode, status: "processing", error: nil) }
        
        // Validate API key
        guard let groqKey = settingsManager.groqAPIKey else {
            let error = "Groq API key not configured"
            await MainActor.run { updateEpisodeStatus(episode, status: "failed", error: error) }
            throw NSError(domain: "AdDetection", code: -1, userInfo: [NSLocalizedDescriptionKey: error])
        }
        
        // Get local audio file
        guard let localURL = await ensureLocalFile(for: context) else {
            let error = "Unable to get local file for episode"
            await MainActor.run { updateEpisodeStatus(episode, status: "failed", error: error) }
            throw NSError(domain: "AdDetection", code: -2, userInfo: [NSLocalizedDescriptionKey: error])
        }
        
        let asset = AVURLAsset(url: localURL)
        let isTempFile = localURL.path.contains(FileManager.default.temporaryDirectory.path) &&
                         localURL.path.contains("ad-detection-")
        
        let overallStart = Date()
        var allSegments: [AdSegment] = []
        var accumulatedWhisperSegments: [AbsoluteSegment] = []  // For cross-block padding
        
        do {
            let duration = try await asset.load(.duration).seconds
            logger.info("📊 [AdDetection] Episode duration: \(String(format: "%.1f", duration))s, processing in \(String(format: "%.0f", self.blockDuration/60))min blocks")
            
            var blockStart: TimeInterval = 0
            
            while blockStart < duration {
                let blockEnd = min(blockStart + self.blockDuration, duration)
                let actualBlockDuration = blockEnd - blockStart
                
                logger.info("⏳ [AdDetection] Block \(String(format: "%.0f", blockStart/60))-\(String(format: "%.0f", blockEnd/60))min")
                
                let (blockSegments, blockTranscript, newAbsoluteSegments) = try await processBlock(
                    asset: asset,
                    blockStart: blockStart,
                    blockDuration: actualBlockDuration,
                    groqKey: groqKey,
                    accumulatedSegments: accumulatedWhisperSegments
                )
                
                // Accumulate segments for future blocks' padding
                accumulatedWhisperSegments.append(contentsOf: newAbsoluteSegments)
                
                allSegments.append(contentsOf: blockSegments)
                // Append transcript to episode
                if !blockTranscript.isEmpty {
                    await MainActor.run {
                        if let existing = episode?.transcript, !existing.isEmpty {
                            episode?.transcript = existing + "\n" + blockTranscript
                        } else {
                            episode?.transcript = blockTranscript
                        }
                    }
                }
                blockStart = blockEnd
            }
            
            // Final merge
            let finalSegments = mergeAndAdjustSegments(allSegments, episodeDuration: duration)
            
            let totalTime = Date().timeIntervalSince(overallStart)
            logger.info("✅ [AdDetection] Complete! Found \(finalSegments.count) ads in \(String(format: "%.1f", totalTime))s")
            
            await MainActor.run {
                episode?.adSegments = finalSegments
                episode?.adDetectionStatus = "completed"
                episode?.adDetectionError = nil
            }
            
            if isTempFile { cleanupTempFile(at: localURL) }
            return finalSegments
            
        } catch {
            logger.error("❌ [AdDetection] Failed: \(error.localizedDescription, privacy: .public)")
            await MainActor.run { updateEpisodeStatus(episode, status: "failed", error: error.localizedDescription) }
            if isTempFile { cleanupTempFile(at: localURL) }
            throw error
        }
    }
    
    /// Analyze first 5 minutes (for streaming - blocks playback until complete)
    func analyzeFirstSegment(context: EpisodeDetectionContext, episode: Episode) async throws {
        guard let groqKey = settingsManager.groqAPIKey else {
            throw NSError(domain: "AdDetection", code: -1, userInfo: [NSLocalizedDescriptionKey: "Groq API key not configured"])
        }
        
        guard let localURL = await ensureLocalFile(for: context) else {
            throw NSError(domain: "AdDetection", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to get local file"])
        }
        
        let asset = AVURLAsset(url: localURL)
        let isTempFile = localURL.path.contains(FileManager.default.temporaryDirectory.path)
        
        let start = Date()
        let (segments, transcript, _) = try await processBlock(asset: asset, blockStart: 0, blockDuration: blockDuration, groqKey: groqKey, accumulatedSegments: [])
        let elapsed = Date().timeIntervalSince(start)
        
        // Log in spec format
        if !segments.isEmpty {
            let ranges = segments.map { "\(Int($0.startTime))-\(Int($0.endTime))" }.joined(separator: ", ")
            logger.info("Ad Detection 10% took \(String(format: "%.1f", elapsed))s, ads from \(ranges)")
        } else {
            logger.info("Ad Detection 10% took \(String(format: "%.1f", elapsed))s, no ads")
        }
        
        await MainActor.run {
            episode.adSegments = segments
            episode.adDetectionStatus = "partial_start"
            episode.transcript = transcript
        }
        
        if isTempFile { cleanupTempFile(at: localURL) }
    }
    
    /// Pre-process first 2 blocks (10 min) after episode download
    /// Remaining processing happens during playback (cost-saving)
    func preProcessDownloadedEpisode(episode: Episode) async {
        guard let groqKey = settingsManager.groqAPIKey else { return }
        guard let path = episode.localFilePath, FileManager.default.fileExists(atPath: path) else { return }
        
        // Skip if already processed
        if episode.adDetectionStatus == "completed" || episode.adDetectionStatus == "partial_start" {
            return
        }
        
        let localURL = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: localURL)
        
        let start = Date()
        
        do {
            let duration = try await asset.load(.duration).seconds
            
            // Process first 2 blocks (10 min total)
            var accumulatedWhisperSegments: [AbsoluteSegment] = []
            
            for blockIndex in 0..<2 {
                let blockStart = TimeInterval(blockIndex) * blockDuration
                if blockStart >= duration { break }
                
                let blockEnd = min(blockStart + blockDuration, duration)
                let actualDuration = blockEnd - blockStart
                if actualDuration < 30 { break }
                
                let (segments, transcript, newAbsoluteSegments) = try await processBlock(
                    asset: asset,
                    blockStart: blockStart,
                    blockDuration: actualDuration,
                    groqKey: groqKey,
                    accumulatedSegments: accumulatedWhisperSegments
                )
                
                // Accumulate segments for next block's padding
                accumulatedWhisperSegments.append(contentsOf: newAbsoluteSegments)
                
                await MainActor.run {
                    var existing = episode.adSegments ?? []
                    existing.append(contentsOf: segments)
                    episode.adSegments = mergeAndAdjustSegments(existing, episodeDuration: duration)
                    // Append transcript
                    if let existingTranscript = episode.transcript, !existingTranscript.isEmpty {
                        episode.transcript = existingTranscript + "\n" + transcript
                    } else {
                        episode.transcript = transcript
                    }
                }
            }
            
            let elapsed = Date().timeIntervalSince(start)
            let adsFound = episode.adSegments?.count ?? 0
            
            if adsFound > 0 {
                let ranges = (episode.adSegments ?? []).map { "\(Int($0.startTime))-\(Int($0.endTime))" }.joined(separator: ", ")
                logger.info("📥 Pre-processed first 10min: \(adsFound) ads (\(ranges)) in \(String(format: "%.1f", elapsed))s")
            } else {
                logger.info("📥 Pre-processed first 10min: no ads in \(String(format: "%.1f", elapsed))s")
            }
            
            await MainActor.run {
                episode.adDetectionStatus = "partial_start"
            }
            
        } catch {
            logger.error("Pre-processing failed: \(error.localizedDescription)")
        }
    }
    
    /// Analyze remaining segments in background (after first 5 minutes)
    func analyzeRemainingSegments(context: EpisodeDetectionContext, episode: Episode) async throws {
        logger.info("🔄 [AdDetection] Continuing background analysis...")
        
        guard let groqKey = settingsManager.groqAPIKey else { return }
        guard let localURL = await ensureLocalFile(for: context) else { return }
        
        let asset = AVURLAsset(url: localURL)
        let duration = try await asset.load(.duration).seconds
        let isTempFile = localURL.path.contains(FileManager.default.temporaryDirectory.path)
        
        var blockStart = blockDuration // Start after first 5 minutes
        var accumulatedWhisperSegments: [AbsoluteSegment] = []  // For cross-block padding
        
        while blockStart < duration {
            let blockEnd = min(blockStart + blockDuration, duration)
            let actualDuration = blockEnd - blockStart
            if actualDuration < 30 { break }
            
            do {
                let (segments, transcript, newAbsoluteSegments) = try await processBlock(
                    asset: asset,
                    blockStart: blockStart,
                    blockDuration: actualDuration,
                    groqKey: groqKey,
                    accumulatedSegments: accumulatedWhisperSegments
                )
                
                // Accumulate segments for next block's padding
                accumulatedWhisperSegments.append(contentsOf: newAbsoluteSegments)
                
                await MainActor.run {
                    var existing = episode.adSegments ?? []
                    existing.append(contentsOf: segments)
                    episode.adSegments = mergeAndAdjustSegments(existing, episodeDuration: duration)
                    // Append transcript
                    if let existingTranscript = episode.transcript, !existingTranscript.isEmpty {
                        episode.transcript = existingTranscript + "\n" + transcript
                    } else {
                        episode.transcript = transcript
                    }
                }
            } catch {
                logger.error("Block at \(blockStart)s failed: \(error.localizedDescription)")
            }
            
            blockStart = blockEnd
        }
        
        await MainActor.run { episode.adDetectionStatus = "completed" }
        if isTempFile { cleanupTempFile(at: localURL) }
    }
    // MARK: - Core Processing Pipeline
    
    /// Process a single 5-minute block with 2x speed + compression + two-stage detection
    /// Returns: (ad segments, timestamped transcript, new absolute segments for accumulation)
    private func processBlock(
        asset: AVAsset,
        blockStart: TimeInterval,
        blockDuration: TimeInterval,
        groqKey: String,
        accumulatedSegments: [AbsoluteSegment]
    ) async throws -> (segments: [AdSegment], transcript: String, absoluteSegments: [AbsoluteSegment]) {
        // Step 1: Extract, speed up (2x), and compress audio
        let audioTimer = Date()
        guard let audioData = try await processAudioSegment(asset: asset, start: blockStart, duration: blockDuration) else {
            logger.warning("Audio extraction failed at \(Int(blockStart))s")
            return ([], "", [])
        }
        let audioTime = Date().timeIntervalSince(audioTimer)
        logger.info("Preparing audio: took \(String(format: "%.1f", audioTime))s")
        
        // Step 2: Transcribe with Whisper (returns segments with timestamps)
        let whisperTimer = Date()
        let transcription = try await groqWhisperService.transcribe(audioData: audioData, apiKey: groqKey)
        let whisperTime = Date().timeIntervalSince(whisperTimer)
        logger.info("Transcribing audio: took \(String(format: "%.1f", whisperTime))s")
        
        // Build timestamped transcript string for saving
        // Whisper times are in 2x speed, so multiply by 2 and add blockStart for real times
        let timestampedTranscript = transcription.segments.map { seg in
            let realStart = Int(blockStart + seg.start * 2)
            let realEnd = Int(blockStart + seg.end * 2)
            return "[\(realStart)-\(realEnd)] \(seg.text.trimmingCharacters(in: .whitespaces))"
        }.joined(separator: "\n")
        
        // Convert Whisper segments to absolute timestamps for accumulation
        let newAbsoluteSegments: [AbsoluteSegment] = transcription.segments.map { seg in
            AbsoluteSegment(
                start: blockStart + seg.start * 2,  // Convert 2x to real time
                end: blockStart + seg.end * 2,
                text: seg.text
            )
        }
        
        // Combine accumulated + new segments for Stage 2 (for cross-block padding)
        let allSegmentsForStage2 = accumulatedSegments + newAbsoluteSegments
        
        // Step 3: Two-stage LLM detection with full segment history
        let segments = try await twoStageDetection(
            currentBlockSegments: transcription.segments,
            allAbsoluteSegments: allSegmentsForStage2,
            blockStart: blockStart,
            blockDuration: blockDuration,
            groqKey: groqKey
        )
        
        return (segments, timestampedTranscript, newAbsoluteSegments)
    }
    
    // MARK: - Audio Processing (2x Speed + Compression)
    
    /// Extract audio chunk, speed up 2x, and compress to 24kbps AAC mono
    private func processAudioSegment(asset: AVAsset, start: TimeInterval, duration: TimeInterval) async throws -> Data? {
        let composition = AVMutableComposition()
        
        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
              let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            logger.error("Failed to load audio track")
            return nil
        }
        
        let timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        
        try compositionTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        
        // Scale time by 0.5 (2x speed)
        let scaledDuration = CMTimeMultiplyByFloat64(timeRange.duration, multiplier: 0.5)
        compositionTrack.scaleTimeRange(CMTimeRange(start: .zero, duration: timeRange.duration), toDuration: scaledDuration)
        
        // Export with compression
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ad-chunk-\(UUID().uuidString).m4a")
        
        do {
            let reader = try AVAssetReader(asset: composition)
            let writer = try AVAssetWriter(outputURL: tempURL, fileType: .m4a)
            
            // Output: AAC, 24kHz, Mono, ~24kbps
            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 24000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 24000
            ]
            
            let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
            writerInput.expectsMediaDataInRealTime = false
            writer.add(writerInput)
            
            // Reader output (Linear PCM for re-encoding)
            let readerOutput = AVAssetReaderTrackOutput(track: compositionTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false
            ])
            reader.add(readerOutput)
            
            reader.startReading()
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            
            // Processing loop using continuation
            let queue = DispatchQueue(label: "audio.processing")
            let writerInputWrapper = UnsafeSendable(value: writerInput)
            let readerOutputWrapper = UnsafeSendable(value: readerOutput)
            let writerWrapper = UnsafeSendable(value: writer)
            
            await withCheckedContinuation { continuation in
                writerInput.requestMediaDataWhenReady(on: queue) {
                    let writerInput = writerInputWrapper.value
                    let readerOutput = readerOutputWrapper.value
                    let writer = writerWrapper.value
                    
                    while writerInput.isReadyForMoreMediaData {
                        if let buffer = readerOutput.copyNextSampleBuffer() {
                            writerInput.append(buffer)
                        } else {
                            writerInput.markAsFinished()
                            writer.finishWriting {
                                continuation.resume()
                            }
                            break
                        }
                    }
                }
            }
            
            if writer.status == .completed {
                let data = try Data(contentsOf: tempURL)
                try? FileManager.default.removeItem(at: tempURL)
                return data
            } else {
                try? FileManager.default.removeItem(at: tempURL)
                logger.error("Audio writer failed: \(writer.error?.localizedDescription ?? "unknown")")
                return nil
            }
            
        } catch {
            logger.error("Audio processing failed: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
    }
    
    // MARK: - Two-Stage LLM Detection
    
    /// Two-stage detection using segment timestamps
    /// Stage 1: 1-minute chunks → Llama 8B (parallel yes/no) - uses current block only
    /// Stage 2: Super-chunks with padding → Llama 70B (exact timestamps) - uses all accumulated segments
    private func twoStageDetection(
        currentBlockSegments: [GroqWhisperService.SegmentTimestamp],
        allAbsoluteSegments: [AbsoluteSegment],
        blockStart: TimeInterval,
        blockDuration: TimeInterval,
        groqKey: String
    ) async throws -> [AdSegment] {
        guard !currentBlockSegments.isEmpty else {
            logger.warning("No segments to analyze")
            return []
        }
        
        // Group segments into 1-minute chunks based on their timestamps
        // Note: Whisper times are from 2x speed audio, so multiply by 2 for real time
        var minuteChunks: [(minute: Int, segments: [GroqWhisperService.SegmentTimestamp], text: String)] = []
        
        let maxMinute = Int((blockDuration / minuteChunkDuration).rounded(.up))
        
        for minute in 0..<maxMinute {
            // Real-time boundaries for this minute
            let realStart = Double(minute) * minuteChunkDuration
            let realEnd = realStart + minuteChunkDuration
            
            // Whisper timestamps are in 2x audio time, so divide by 2 to get the range
            let audioStart = realStart / 2.0
            let audioEnd = realEnd / 2.0
            
            let chunkSegments = currentBlockSegments.filter { seg in
                seg.start < audioEnd && seg.end > audioStart
            }
            
            if !chunkSegments.isEmpty {
                let text = chunkSegments.map { $0.text }.joined(separator: " ")
                minuteChunks.append((minute: minute, segments: chunkSegments, text: text))
            }
        }
        
        if minuteChunks.isEmpty {
            return []
        }
        
        // Stage 1: Parallel yes/no detection with Llama 8B
        let stage1Timer = Date()
        var positiveMinutes: [Int] = []
        
        try await withThrowingTaskGroup(of: (Int, Bool).self) { group in
            for chunk in minuteChunks {
                group.addTask {
                    let hasAd = try await self.checkForAds(transcript: chunk.text, groqKey: groqKey)
                    return (chunk.minute, hasAd)
                }
            }
            
            for try await (minute, hasAd) in group {
                if hasAd {
                    positiveMinutes.append(minute)
                }
            }
        }
        
        let stage1Time = Date().timeIntervalSince(stage1Timer)
        if !positiveMinutes.isEmpty {
            let chunks = positiveMinutes.sorted().map { String($0) }.joined(separator: ",")
            logger.info("Stage 1 took \(String(format: "%.1f", stage1Time))s, ads in chunk \(chunks)")
        } else {
            logger.info("Stage 1 took \(String(format: "%.1f", stage1Time))s, no ads detected")
        }
        
        if positiveMinutes.isEmpty {
            return []
        }
        
        // Group adjacent minutes into super-chunks
        let superChunks = groupAdjacentMinutes(positiveMinutes.sorted())
        
        // Stage 2: Get exact timestamps for each super-chunk
        let stage2Timer = Date()
        var allSegmentData: [AdSegmentData] = []
        
        try await withThrowingTaskGroup(of: [AdSegmentData].self) { group in
            for superChunk in superChunks {
                group.addTask {
                    return try await self.getExactTimestampsData(
                        allAbsoluteSegments: allAbsoluteSegments,
                        startMinute: superChunk.startMinute,
                        endMinute: superChunk.endMinute,
                        blockStart: blockStart,
                        groqKey: groqKey
                    )
                }
            }
            
            for try await segmentResults in group {
                allSegmentData.append(contentsOf: segmentResults)
            }
        }
        
        // Convert DTOs to SwiftData models
        let allSegments = allSegmentData.map { $0.toAdSegment() }
        
        let stage2Time = Date().timeIntervalSince(stage2Timer)
        if !allSegments.isEmpty {
            let ranges = allSegments.map { "\(Int($0.startTime))-\(Int($0.endTime))" }.joined(separator: ", ")
            logger.info("Stage 2 took \(String(format: "%.1f", stage2Time))s, ads from \(ranges)")
        } else {
            logger.info("Stage 2 took \(String(format: "%.1f", stage2Time))s, no exact timestamps")
        }
        
        return allSegments
    }
    
    /// Group adjacent minute indices: [1,2,4,5,6] → [(1,2), (4,6)]
    private func groupAdjacentMinutes(_ minutes: [Int]) -> [(startMinute: Int, endMinute: Int)] {
        guard !minutes.isEmpty else { return [] }
        
        var result: [(startMinute: Int, endMinute: Int)] = []
        var currentStart = minutes[0]
        var currentEnd = minutes[0]
        
        for i in 1..<minutes.count {
            if minutes[i] == currentEnd + 1 {
                currentEnd = minutes[i]
            } else {
                result.append((currentStart, currentEnd))
                currentStart = minutes[i]
                currentEnd = minutes[i]
            }
        }
        result.append((currentStart, currentEnd))
        
        return result
    }
    
    /// Stage 1: Quick yes/no ad check using Llama 8B
    private func checkForAds(transcript: String, groqKey: String) async throws -> Bool {
        // Debug: Log transcript being analyzed
        logger.debug("🔎 [Stage 1] Analyzing transcript (\(transcript.count) chars):\n\(transcript.prefix(500), privacy: .public)")
        
        let prompt = """
        You are a podcast ad detector. Determine if this transcript contains CLEAR promotional content.
        Be CONSERVATIVE - only say true for obvious ads, not general discussion.

        CLEAR promotional content includes:
        - Paid sponsors with promo codes or URLs ("use code", "brought to you by")
        - Self-promotion with call-to-action (Patreon, merch, "subscribe to our premium")
        - Cross-promotion of other podcasts ("check out our other show")
        
        Do NOT flag:
        - General discussion about products (organic mentions)
        - Interview content where guests discuss their work
        - Technical discussions mentioning tools/services

        Respond with ONLY this json: {"has_ad": true} or {"has_ad": false}

        Transcript:
        \(transcript.prefix(4000))
        """
        
        let response = try await groqChatService.chat(prompt: prompt, apiKey: groqKey, model: filterModel)
        
        // Debug: Log raw LLM response
        logger.debug("🔎 [Stage 1] Raw LLM response: \(response, privacy: .public)")
        
        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let hasAd = json["has_ad"] as? Bool {
            logger.info("🔎 [Stage 1] Result: hasAd=\(hasAd)")
            return hasAd
        }
        
        // Fallback parsing failed - log warning
        let fallbackResult = response.lowercased().contains("true")
        logger.warning("🔎 [Stage 1] JSON parse failed, using fallback. Response: \(response.prefix(100), privacy: .public) -> \(fallbackResult)")
        return fallbackResult
    }
    
    /// Stage 2: Get exact timestamps by asking 70B for first/last sentences, then matching against Whisper
    /// Returns Sendable DTOs that are later converted to SwiftData models
    /// Now uses AbsoluteSegment with absolute episode timestamps for cross-block padding
    private func getExactTimestampsData(
        allAbsoluteSegments: [AbsoluteSegment],
        startMinute: Int,
        endMinute: Int,
        blockStart: TimeInterval,
        groqKey: String
    ) async throws -> [AdSegmentData] {
        // Calculate padded time range in ABSOLUTE episode time
        // startMinute/endMinute are block-relative, so add blockStart to get absolute times
        let absoluteChunkStart = blockStart + Double(startMinute) * minuteChunkDuration
        let absoluteChunkEnd = blockStart + Double(endMinute + 1) * minuteChunkDuration
        
        // Apply padding to absolute times (allows padding into previous blocks)
        let absolutePaddedStart = max(0, absoluteChunkStart - paddingDuration)
        let absolutePaddedEnd = absoluteChunkEnd + paddingDuration
        
        // Log if we're getting cross-block padding
        if absolutePaddedStart < blockStart {
            logger.info("✅ Stage 2: Using cross-block padding from \(Int(absolutePaddedStart))s (block starts at \(Int(blockStart))s)")
        }
        
        // Filter AbsoluteSegments using absolute timestamps - this now works across blocks!
        let relevantSegments = allAbsoluteSegments.filter { seg in
            seg.end > absolutePaddedStart && seg.start < absolutePaddedEnd
        }
        
        if relevantSegments.isEmpty {
            return []
        }
        
        // Build plain transcript for 70B (no timestamps - it just needs to identify content)
        let plainTranscript = relevantSegments.map { $0.text }.joined(separator: " ")
        
        let prompt = """
        You are a podcast ad detector. Analyze this transcript and identify promotional segments.
        Be CONSERVATIVE - only flag clear promotional content, not general discussion.

        CATEGORIES (use EXACTLY these values):

        1. "paid_ad" - External sponsor ads
           Signals: promo codes, sponsor URLs, "brought to you by", "use code", discount offers
           
        2. "self_promo" - Creator's own products/services  
           Signals: Patreon, merch store, "our Discord", "subscribe to premium", newsletter signup
           
        3. "cross_promo" - Promoting other podcasts/creators
           Signals: Other podcast names, "check out", network promotions, guest's other shows
           
        4. "product_mention" - Organic brand mention (NOT an ad break)
           Signals: Casual mention in conversation, no promo code, no call-to-action
           Use this ONLY if genuinely unclear - prefer skipping low-confidence detections

        For each segment found, identify the EXACT FIRST SENTENCE and EXACT LAST SENTENCE.
        Quote sentences EXACTLY as they appear.

        Return ONLY this JSON:
        {
            "ads": [
                {
                    "first_sentence": "<exact first sentence>",
                    "last_sentence": "<exact last sentence>",
                    "confidence": <0.0-1.0>,
                    "ad_type": "paid_ad" | "self_promo" | "cross_promo" | "product_mention",
                    "brand_or_offer": "<brand name or unknown>"
                }
            ]
        }

        If no promotional content found: {"ads": []}
        If unsure, do NOT include it - err on the side of NOT flagging.

        Transcript:
        \(plainTranscript.prefix(6000))
        """
        
        let response = try await groqChatService.chat(prompt: prompt, apiKey: groqKey, model: precisionModel)
        
        logger.debug("🔍 [Stage 2] Raw LLM response:\n\(response, privacy: .public)")
        
        guard let data = response.data(using: .utf8) else {
            return []
        }
        
        struct SentenceResponse: Codable {
            let ads: [AdJSON]?
        }
        
        struct AdJSON: Codable {
            let first_sentence: String
            let last_sentence: String
            let confidence: Double?
            let ad_type: String?
            let brand_or_offer: String?
        }
        
        guard let parsed = try? JSONDecoder().decode(SentenceResponse.self, from: data),
              let ads = parsed.ads, !ads.isEmpty else {
            return []
        }
        
        // Match sentences against AbsoluteSegments (now with absolute timestamps!)
        var detectedSegments: [AdSegmentData] = []
        
        for ad in ads {
            // Find start time by matching first sentence
            let startMatch = findBestMatchAbsolute(query: ad.first_sentence, in: relevantSegments)
            // Find end time by matching last sentence
            let endMatch = findBestMatchAbsolute(query: ad.last_sentence, in: relevantSegments)
            
            if let start = startMatch, let end = endMatch {
                // Timestamps are already absolute episode times
                let realStartTime = start.start
                let realEndTime = end.end
                
                if realEndTime > realStartTime {
                    let segment = AdSegmentData(
                        startTime: realStartTime,
                        endTime: realEndTime,
                        confidence: ad.confidence ?? 0.8,
                        label: ad.ad_type ?? "Ad",
                        adType: ad.ad_type,
                        brandOrOffer: ad.brand_or_offer,
                        evidenceExcerpt: "\(ad.first_sentence.prefix(50))...",
                        reasoning: "Matched: '\(ad.first_sentence.prefix(30))...' to '\(ad.last_sentence.prefix(30))...'"
                    )
                    detectedSegments.append(segment)
                    logger.info("Stage 2: Matched ad \(Int(realStartTime))s-\(Int(realEndTime))s")
                }
            }
        }
        
        return detectedSegments
    }
    
    /// Fuzzy match a query sentence against AbsoluteSegments
    private func findBestMatchAbsolute(query: String, in segments: [AbsoluteSegment]) -> AbsoluteSegment? {
        // Normalize query: "dot com" -> ".com", " slash " -> "/", lowercase, etc.
        let queryNormalized = normalizeForMatching(query)
        
        // First try exact substring match
        for segment in segments {
            let segmentNormalized = normalizeForMatching(segment.text)
            if segmentNormalized.contains(queryNormalized) || queryNormalized.contains(segmentNormalized) {
                return segment
            }
        }
        
        // Fallback: word overlap matching with better tokenization
        let queryWords = tokenize(queryNormalized)
        var bestMatch: (segment: AbsoluteSegment, score: Double)?
        
        for segment in segments {
            let segmentWords = tokenize(normalizeForMatching(segment.text))
            
            let intersection = queryWords.intersection(segmentWords)
            let union = queryWords.union(segmentWords)
            
            // Jaccard similarity
            let score = union.isEmpty ? 0 : Double(intersection.count) / Double(union.count)
            
            if score > 0.3 {  // Minimum 30% word overlap
                if bestMatch == nil || score > bestMatch!.score {
                    bestMatch = (segment, score)
                }
            }
        }
        
        return bestMatch?.segment
    }
    
    private func normalizeForMatching(_ text: String) -> String {
        return text.lowercased()
            .replacingOccurrences(of: " dot ", with: ".")
            .replacingOccurrences(of: " slash ", with: "/")
            .replacingOccurrences(of: " at ", with: "@")
            .replacingOccurrences(of: "dash", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func tokenize(_ text: String) -> Set<String> {
        // Split by whitespace and punctuation
        let components = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(components.filter { !$0.isEmpty })
    }
    
    // MARK: - Segment Merging
    
    /// Merge segments ≤15s apart (without adjusting to episode boundaries)
    private func mergeAdjacentSegments(_ segments: [AdSegment]) -> [AdSegment] {
        guard !segments.isEmpty else { return [] }
        
        let sorted = segments.sorted { $0.startTime < $1.startTime }
        var merged: [AdSegment] = []
        
        for segment in sorted {
            if let last = merged.last, segment.startTime - last.endTime <= 15 {
                merged[merged.count - 1] = AdSegment(
                    startTime: last.startTime,
                    endTime: max(last.endTime, segment.endTime),
                    confidence: max(last.confidence, segment.confidence),
                    label: last.label,
                    adType: last.adType ?? segment.adType,
                    brandOrOffer: last.brandOrOffer ?? segment.brandOrOffer,
                    evidenceExcerpt: last.evidenceExcerpt ?? segment.evidenceExcerpt,
                    reasoning: last.reasoning ?? segment.reasoning
                )
            } else {
                merged.append(segment)
            }
        }
        
        return merged
    }
    
    /// Merge segments ≤10s apart and extend to episode boundaries if ≤10s away
    func mergeAndAdjustSegments(_ segments: [AdSegment], episodeDuration: TimeInterval) -> [AdSegment] {
        guard !segments.isEmpty else { return [] }
        
        let sorted = segments.sorted { $0.startTime < $1.startTime }
        var merged: [AdSegment] = []
        
        for segment in sorted {
            if let last = merged.last, segment.startTime - last.endTime <= 15 {
                merged[merged.count - 1] = AdSegment(
                    startTime: last.startTime,
                    endTime: max(last.endTime, segment.endTime),
                    confidence: max(last.confidence, segment.confidence),
                    label: last.label,
                    adType: last.adType ?? segment.adType,
                    brandOrOffer: last.brandOrOffer ?? segment.brandOrOffer,
                    evidenceExcerpt: last.evidenceExcerpt ?? segment.evidenceExcerpt,
                    reasoning: last.reasoning ?? segment.reasoning
                )
            } else {
                merged.append(segment)
            }
        }
        
        // Extend first segment to start if ≤15s from beginning
        if let first = merged.first, first.startTime <= 15 {
            merged[0] = AdSegment(
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
        
        // Extend last segment to end if ≤15s from episode end
        if let last = merged.last, episodeDuration > 0, episodeDuration - last.endTime <= 15 {
            merged[merged.count - 1] = AdSegment(
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
    
    // MARK: - Chunked Download (HTTP Range)
    
    /// Get remote file size via HEAD request
    private func getRemoteFileSize(url: URL) async -> Int64? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        
        logger.debug("[Range] Checking file size for: \(url.absoluteString.prefix(60), privacy: .public)")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                logger.debug("[Range] HEAD response status: \(httpResponse.statusCode)")
                
                // Log all headers for debugging
                let headers = httpResponse.allHeaderFields
                if let contentLength = headers["Content-Length"] as? String {
                    logger.info("[Range] Content-Length: \(contentLength)")
                    if let size = Int64(contentLength) {
                        return size
                    }
                }
                if let acceptRanges = headers["Accept-Ranges"] as? String {
                    logger.info("[Range] Accept-Ranges: \(acceptRanges)")
                }
            }
            // Fallback to expectedContentLength
            let expectedLength = response.expectedContentLength
            logger.debug("[Range] expectedContentLength: \(expectedLength)")
            return expectedLength > 0 ? expectedLength : nil
        } catch {
            logger.warning("HEAD request failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Check if server supports Range requests
    private func supportsRangeRequests(url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let acceptRanges = httpResponse.value(forHTTPHeaderField: "Accept-Ranges")
                let supports = acceptRanges?.lowercased() == "bytes"
                logger.info("[Range] Server supports Range: \(supports) (Accept-Ranges: \(acceptRanges ?? "nil", privacy: .public))")
                // Most CDNs support Range even without Accept-Ranges header, so try anyway
                // Return true and let the actual Range request fail if not supported
                return true  // Optimistic: try Range request anyway
            }
        } catch {
            logger.warning("Range support check failed: \(error.localizedDescription)")
        }
        return true  // Try anyway, will fallback if it fails
    }
    
    /// Download a chunk of the file using HTTP Range request
    private func downloadChunk(url: URL, startByte: Int64, endByte: Int64, chunkIndex: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(startByte)-\(endByte)", forHTTPHeaderField: "Range")
        
        let downloadStart = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let downloadTime = Date().timeIntervalSince(downloadStart)
        
        if let httpResponse = response as? HTTPURLResponse {
            // 206 = Partial Content (Range request successful)
            // 200 = Full content (server ignoring Range, or file smaller than requested)
            if httpResponse.statusCode == 206 || httpResponse.statusCode == 200 {
                if chunkIndex == 0 {
                    logger.info("10% downloaded: took \(String(format: "%.1f", downloadTime))s")
                }
                return data
            } else {
                throw NSError(domain: "AdDetection", code: httpResponse.statusCode, 
                              userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
            }
        }
        
        return data
    }
    
    /// Download first chunk (10%) for immediate analysis - used for streaming
    func downloadFirstChunk(for context: EpisodeDetectionContext, chunkPercent: Int = 10) async -> URL? {
        guard let remoteURL = URL(string: context.audioURL) else { return nil }
        
        // Check if already downloaded
        if context.isDownloaded, let path = context.localFilePath {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        
        // Get file size
        guard let totalSize = await getRemoteFileSize(url: remoteURL) else {
            logger.warning("Could not get file size, falling back to full download")
            return await ensureLocalFileFull(for: context)
        }
        
        // Check Range support
        let supportsRange = await supportsRangeRequests(url: remoteURL)
        if !supportsRange {
            logger.warning("Server doesn't support Range requests, falling back to full download")
            return await ensureLocalFileFull(for: context)
        }
        
        // Calculate first chunk size
        let chunkSize = totalSize * Int64(chunkPercent) / 100
        let endByte = min(chunkSize, totalSize) - 1
        
        do {
            let chunkData = try await downloadChunk(url: remoteURL, startByte: 0, endByte: endByte, chunkIndex: 0)
            
            // Save to temp file
            let tempFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("ad-chunk-\(context.id.uuidString)-0.mp3")
            try? FileManager.default.removeItem(at: tempFile)
            try chunkData.write(to: tempFile)
            
            return tempFile
        } catch {
            logger.error("Chunk download failed: \(error.localizedDescription), falling back to full download")
            return await ensureLocalFileFull(for: context)
        }
    }
    
    /// Background ad detection with playback-based pacing
    /// Stays 2 blocks (10 min) ahead of current playback position
    /// Continues running in background while audio plays
    func processRemainingWithPlaybackPacing(
        context: EpisodeDetectionContext,
        episode: Episode
    ) async {
        guard let groqKey = settingsManager.groqAPIKey else { return }
        
        // Request background execution time - this ensures iOS doesn't suspend us
        // while we're processing (important when user backgrounds the app)
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: "AdDetection") {
                // Expiration handler - called if iOS needs to reclaim resources
                // With audio playing, this shouldn't be called, but it's a safety net
                self.logger.info("⚠️ Background task expiring, will resume when foregrounded")
            }
        }
        
        defer {
            if backgroundTaskID != .invalid {
                Task { @MainActor in
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
            }
        }
        
        let downloadStart = Date()
        
        // Download the complete file
        guard let localURL = await ensureLocalFileFull(for: context) else {
            logger.error("Failed to download full file")
            return
        }
        
        let downloadTime = Date().timeIntervalSince(downloadStart)
        logger.info("📥 Downloaded episode: took \(String(format: "%.1f", downloadTime))s")
        
        // Save the file and mark as downloaded
        await MainActor.run {
            episode.localFilePath = localURL.path
            episode.isDownloaded = true
        }
        
        let asset = AVURLAsset(url: localURL)
        
        do {
            let duration = try await asset.load(.duration).seconds
            var processedUpTo: TimeInterval = blockDuration // Already processed first 5 min
            var accumulatedWhisperSegments: [AbsoluteSegment] = []  // For cross-block padding
            
            // Process loop - stays 2 blocks ahead of playback
            while processedUpTo < duration {
                // Get current playback position
                let currentPlayback = await MainActor.run { episode.progress }
                
                // Calculate how far ahead we are
                let aheadBy = processedUpTo - currentPlayback
                let twoBlocksAhead = blockDuration * 2  // 10 minutes
                
                // If we're already 2+ blocks ahead, wait before processing more
                if aheadBy >= twoBlocksAhead {
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 second pause
                    continue
                }
                
                // Process next block
                let blockStart = processedUpTo
                let blockEnd = min(blockStart + blockDuration, duration)
                let actualDuration = blockEnd - blockStart
                
                if actualDuration < 30 { break }
                
                do {
                    let (segments, transcript, newAbsoluteSegments) = try await processBlock(
                        asset: asset,
                        blockStart: blockStart,
                        blockDuration: actualDuration,
                        groqKey: groqKey,
                        accumulatedSegments: accumulatedWhisperSegments
                    )
                    
                    // Accumulate segments for next block's padding
                    accumulatedWhisperSegments.append(contentsOf: newAbsoluteSegments)
                    
                    await MainActor.run {
                        if !segments.isEmpty {
                            var existing = episode.adSegments ?? []
                            existing.append(contentsOf: segments)
                            episode.adSegments = mergeAndAdjustSegments(existing, episodeDuration: duration)
                        }
                        // Append transcript
                        if !transcript.isEmpty {
                            if let existingTranscript = episode.transcript, !existingTranscript.isEmpty {
                                episode.transcript = existingTranscript + "\n" + transcript
                            } else {
                                episode.transcript = transcript
                            }
                        }
                    }
                    
                    // Log progress
                    let adsCount = segments.count
                    if adsCount > 0 {
                        let ranges = segments.map { "\(Int($0.startTime))-\(Int($0.endTime))" }.joined(separator: ", ")
                        logger.info("✅ Processed \(Int(blockStart))s-\(Int(blockEnd))s: \(adsCount) ads (\(ranges))")
                    } else {
                        logger.info("✅ Processed \(Int(blockStart))s-\(Int(blockEnd))s: no ads")
                    }
                    
                } catch {
                    logger.error("Block at \(Int(blockStart))s failed: \(error.localizedDescription)")
                }
                
                processedUpTo = blockEnd
            }
            
        } catch {
            logger.error("Failed to load duration: \(error.localizedDescription)")
            return
        }
        
        await MainActor.run { episode.adDetectionStatus = "completed" }
        logger.info("✅ Processed complete episode")
    }
    /// Original full-file download (fallback)
    private func ensureLocalFileFull(for context: EpisodeDetectionContext) async -> URL? {
        if context.isDownloaded, let path = context.localFilePath {
            let fileURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                return fileURL
            }
        }
        
        guard let remoteURL = URL(string: context.audioURL) else { return nil }
        
        logger.info("📥 [AdDetection] Downloading full episode...")
        
        do {
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("ad-detection-\(context.id.uuidString).mp3")
            try? FileManager.default.removeItem(at: tempFile)
            
            let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
            try FileManager.default.moveItem(at: tempURL, to: tempFile)
            
            return tempFile
        } catch {
            logger.error("Download failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    /// Legacy method - now uses chunked download for streaming
    private func ensureLocalFile(for context: EpisodeDetectionContext) async -> URL? {
        // For downloaded episodes, use local file directly
        if context.isDownloaded, let path = context.localFilePath {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        
        // For streaming, use chunked download (first 10%)
        return await downloadFirstChunk(for: context)
    }
    
    private func cleanupTempFile(at url: URL) {
        guard url.path.contains(FileManager.default.temporaryDirectory.path) &&
              url.path.contains("ad-detection-") else { return }
        
        try? FileManager.default.removeItem(at: url)
    }
    
    private func updateEpisodeStatus(_ episode: Episode?, status: String, error: String?) {
        episode?.adDetectionStatus = status
        episode?.adDetectionError = error
    }
}

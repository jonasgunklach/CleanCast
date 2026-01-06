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
import SwiftData

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

final class AdDetectionService {
    static let shared = AdDetectionService()
    
    private let logger = Logger(subsystem: "com.jonasgunklach.CleanCast", category: "AdDetection")
    private let groqWhisperService = GroqWhisperService.shared
    private let stage1Service = Stage1CoarseService.shared
    private let stage2Service = Stage2RefineService.shared
    private let arbitrationService = AdArbitrationService.shared
    private let settingsManager = SettingsManager.shared
    
    // Configuration
    private let progressiveWindowDuration: TimeInterval = 5 * 60  // 5 minutes
    
    private init() {}
    
    // MARK: - Public API
    
    /// Reset any windows stuck in "processing" state to "pending"
    /// Call this on app launch/restore to ensure interrupted analysis resumes
    func resetStuckWindows(for episode: Episode) async {
        logger.info("♻️ [AdDetection] Checking for stuck windows in \(episode.title)")
        
        // Use MainActor to safeguard SwiftData access
        await MainActor.run {
            guard let windows = episode.windowRecords else { return }
            var resetCount = 0
            
            for window in windows {
                if window.status == "processing" {
                    window.status = "pending"
                    window.error = nil
                    resetCount += 1
                }
            }
            
            if resetCount > 0 {
                logger.info("   Reset \(resetCount) stuck windows to pending")
                
                // If the overall episode status was stuck, reset it too
                if episode.adDetectionStatus == "processing" {
                    episode.adDetectionStatus = "partial_start" // or whatever indicates "in progress"
                }
            }
            
            // Rebuild transcript from any existing chunks (repair/restore)
            let fullTranscript = windows
                .sorted { $0.windowIndex < $1.windowIndex }
                .compactMap { $0.transcriptChunk?.text }
                .joined(separator: "\n\n")
            
            if !fullTranscript.isEmpty {
                // Only update if different to avoid unnecessary writes?
                // actually, just overwriting is fine for correctness
                if episode.transcript != fullTranscript {
                    logger.info("   Restored transcript from \(windows.count) windows")
                    episode.transcript = fullTranscript
                }
            }
        }
    }

    /// Main entry point: Analyze episode segments based on current Tier and Playback state
    func analyzeEpisode(
        context: EpisodeDetectionContext,
        episode: Episode,
        currentPlayhead: TimeInterval? = nil
    ) async {
        guard let groqKey = settingsManager.groqAPIKey else {
            await updateEpisodeStatus(episode, status: "failed", error: "Groq API key not configured")
            return
        }
        
        // 1. Initialize Windows if needed
        await initializeWindowsIfNeeded(episode: episode, context: context)
        
        // 2. Determine Strategy & Windows to Process
        let tier = settingsManager.adDetectionTier
        let strategy = WindowingStrategy(tier: tier)
        
        let windows = await MainActor.run { return episode.windowRecords ?? [] }
        let duration = await MainActor.run { return episode.duration }
        
        let windowsToProcess = windows.filter { (window: WindowRecord) -> Bool in
            // Check if window needs processing
            let needsWork = (window.status == "pending" || window.status == "failed")
            if !needsWork { return false }
            
            // Check if window is selected by strategy
            return strategy.shouldProcess(
                windowIndex: window.windowIndex,
                totalDuration: duration,
                currentPlayhead: currentPlayhead
            )
        }.sorted { $0.windowIndex < $1.windowIndex }
        
        if windowsToProcess.isEmpty {
            logger.info("✅ [AdDetection] No windows satisfy processing criteria for \(tier.rawValue)")
            await checkOverallCompletion(episode: episode)
            return
        }
        
        // 3. Process Windows Sequentially (for simple concurrency control)
        // 3. Process Windows Sequentially
        // We ensure the file is available per-window to allow for partial downloads (optimization)
        
        await updateEpisodeStatus(episode, status: "processing", error: nil)
        
        for window in windowsToProcess {
            // Check if we should stop (e.g. user paused, app backgrounded, lookahead limits)
            if Task.isCancelled { break }
            
            // Optimization: For Window 0 (Intro), we only need the first chunk
            // For later windows, we might need the full file
            guard let localURL = await ensureLocalFile(for: context, tier: tier, windowIndex: window.windowIndex) else {
                logger.error("❌ Failed to get audio file for window \(window.windowIndex)")
                // If a window fails to download, we might want to fail the episode or just this window
                await updateWindowStatus(window, status: "failed", error: "Download failed")
                continue
            }
            
            let asset = AVURLAsset(url: localURL)
            await processWindow(window: window, asset: asset, apiKey: groqKey, episode: episode)
        }
        
        // Check overall completion
        await checkOverallCompletion(episode: episode)
    }
    
    // MARK: - Core Pipeline (Per Window)
    
    private func processWindow(window: WindowRecord, asset: AVAsset, apiKey: String, episode: Episode) async {
        logger.info("🚀 [Window \(window.windowIndex)] Starting processing (\(Int(window.startTime))-\(Int(window.endTime))s)")
        
        await updateWindowStatus(window, status: "processing")
        
        do {
            // STEP A: Audio Prep (Extract & Resample)
            guard let audioData = try await processAudioSegment(asset: asset, start: window.startTime, duration: window.endTime - window.startTime) else {
                throw NSError(domain: "AdDetection", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio extraction failed"])
            }
            logger.info("   [Window \(window.windowIndex)] Audio extracted")
            
            // STEP B: Whisper Transcription
            // Use a generic prompt to encourage handling of multilingual content/code-switching
            let prompt = "This audio may contain distinct advertisement segments in various languages."
            let transcription = try await groqWhisperService.transcribe(
                audioData: audioData, 
                apiKey: apiKey,
                prompt: prompt
            )
            
            // Convert timestamps to real time (Whisper runs on 2x speed audio, so x2)
            // AND offset by window.startTime (since we transcribed a chunk)
            let realSegments = transcription.segments.map { seg in
                GroqWhisperService.SegmentTimestamp(
                    start: window.startTime + (seg.start * 2),
                    end: window.startTime + (seg.end * 2),
                    text: seg.text
                )
            }
            
            // Persist Transcript Chunk
            let segmentsJSON = (try? JSONEncoder().encode(realSegments)) ?? Data()
            let jsonString = String(data: segmentsJSON, encoding: .utf8) ?? "[]"
            
            // Format text for TranscriptView: "[start-end] text"
            let formattedText = realSegments.map { seg in
                "[\(Int(seg.start))-\(Int(seg.end))] \(seg.text)"
            }.joined(separator: "\n")
            
            await MainActor.run {
                if let existing = window.transcriptChunk {
                    existing.text = formattedText
                    existing.segmentsJSON = jsonString
                } else {
                    let chunk = TranscriptChunk(text: formattedText, segmentsJSON: jsonString)
                    // Explicitly insert into the context
                    if let context = window.modelContext {
                        context.insert(chunk)
                    }
                    window.transcriptChunk = chunk
                    chunk.window = window
                }
                
                // Force save to disk to avoid data loss on crash/exit
                try? window.modelContext?.save()
            }
            logger.info("   [Window \(window.windowIndex)] Transcription persisted")
            
            // STEP C: Stage 1 (Coarse)
            // Use realSegments (absolute episode time) for next steps
            // Need to pass blockStart/Duration to help Stage 1 split correctly relative to the window
            let stage1Result = try await stage1Service.analyze(
                transcriptSegments: realSegments,
                blockStart: window.startTime,
                blockDuration: window.endTime - window.startTime,
                apiKey: apiKey
            )
            
            if stage1Result.positiveBlocks.isEmpty {
                logger.info("   [Window \(window.windowIndex)] No ads found in Stage 1")
                await finalizeWindow(window: window, segments: [])
                return 
            }
            
            // STEP D: Build Candidate Runs
            let candidateRuns = buildCandidateRuns(
                stage1Result: stage1Result,
                allSegments: realSegments,
                windowStart: window.startTime,
                windowEnd: window.endTime
            )
            
            // STEP E: Stage 2 (Refine) & STEP F: Arbitrate
            var finalWindowSegments: [AdSegment] = []
            
            for run in candidateRuns {
                let stage2Result = try await stage2Service.refine(
                    candidateText: run.text,
                    sentences: run.sentences,
                    apiKey: apiKey
                )
                
                let arbitrated = arbitrationService.arbitrate(
                    segmentsA: stage2Result.segmentsA,
                    segmentsB: stage2Result.segmentsB
                )
                
                finalWindowSegments.append(contentsOf: arbitrated)
            }
            
            // STEP G: Finalize & Persist
            await finalizeWindow(window: window, segments: finalWindowSegments, episode: episode)
            
        } catch {
            logger.error("❌ [Window \(window.windowIndex)] Failed: \(error.localizedDescription)")
            await updateWindowStatus(window, status: "failed", error: error.localizedDescription)
        }
    }
    
    // MARK: - Pipeline Helpers
    
    struct CandidateRun {
        let text: String
        let sentences: [IndexedSentence]
        let startTime: TimeInterval
        let endTime: TimeInterval
    }
    
    private func buildCandidateRuns(
        stage1Result: Stage1Result,
        allSegments: [GroqWhisperService.SegmentTimestamp],
        windowStart: TimeInterval,
        windowEnd: TimeInterval
    ) -> [CandidateRun] {
        // 1. Group adjacent positive blocks
        let blocks = stage1Result.positiveBlocks.sorted()
        if blocks.isEmpty { return [] }
        
        var runs: [(startBlock: Int, endBlock: Int)] = []
        var currentRunStart = blocks[0]
        var currentRunEnd = blocks[0]
        
        for i in 1..<blocks.count {
            if blocks[i] == currentRunEnd + 1 {
                currentRunEnd = blocks[i]
            } else {
                runs.append((currentRunStart, currentRunEnd))
                currentRunStart = blocks[i]
                currentRunEnd = blocks[i]
            }
        }
        runs.append((currentRunStart, currentRunEnd))
        
        // 2. Expand runs by ~45s and build context
        var candidates: [CandidateRun] = []
        let padding: TimeInterval = 45
        
        for run in runs {
            // Block indices correspond to minutes (0, 1, 2, 3, 4) within the window
            // Convert to absolute time
            let runStartTime = windowStart + Double(run.startBlock) * 60
            let runEndTime = windowStart + Double(run.endBlock + 1) * 60
            
            // Apply padding, clamped to window
            let paddedStart = max(windowStart, runStartTime - padding)
            let paddedEnd = min(windowEnd, runEndTime + padding)
            
            // Filter transcript segments for this time range
            let relevantSegments = allSegments.filter { $0.end > paddedStart && $0.start < paddedEnd }
            
            if relevantSegments.isEmpty { continue }
            
            // Build IndexedSentences for Stage 2 mapping
            var sentences: [IndexedSentence] = []
            var fullText = ""
            
            for (idx, seg) in relevantSegments.enumerated() {
                sentences.append(IndexedSentence(
                    id: idx,
                    start: seg.start,
                    end: seg.end,
                    text: seg.text
                ))
                fullText += seg.text + " "
            }
            
            candidates.append(CandidateRun(
                text: fullText,
                sentences: sentences,
                startTime: paddedStart,
                endTime: paddedEnd
            ))
        }
        
        return candidates
    }
    
    private func finalizeWindow(window: WindowRecord, segments: [AdSegment], episode: Episode? = nil) async {
        logger.info("✅ [Window \(window.windowIndex)] Finalizing with \(segments.count) segments")
        
        await MainActor.run {
            // Persist segments
            if let episode = window.episode ?? episode {
                var existing = episode.adSegments ?? []
                existing.append(contentsOf: segments)
                
                // Merge new segments into global pool
                // We use a simple merge here, but in production might want global arbitration
                // For now, assume window arbitration is sufficient, just sort
                episode.adSegments = existing.sortedWithMerging()
                
                // Rebuild transcript from all available chunks
                // This ensures we have the full text even after a restore
                if let windows = episode.windowRecords {
                    let fullTranscript = windows
                        .sorted { $0.windowIndex < $1.windowIndex }
                        .compactMap { $0.transcriptChunk?.text }
                        .joined(separator: "\n\n")
                    
                    if !fullTranscript.isEmpty {
                        episode.transcript = fullTranscript
                    }
                }
            }
            
            window.status = "done"
            window.error = nil
        }
    }
    
    // MARK: - State Management
    
    private func initializeWindowsIfNeeded(episode: Episode, context: EpisodeDetectionContext) async {
        let windows = await MainActor.run { return episode.windowRecords ?? [] }
        if !windows.isEmpty { return }
        
        logger.info("Preparing window records for \(context.title)")
        
        // Optimisation: Use metadata duration if available to avoid blocking on download
        var duration = await MainActor.run { episode.duration }
        
        // If duration unknown, fallback to checking file (downloads 10% chunk if needed)
        if duration == 0 {
             if let local = await ensureLocalFile(for: context, tier: .free, windowIndex: 0) {
                 duration = (try? await AVURLAsset(url: local).load(.duration).seconds) ?? 0
             }
        }
        
        if duration == 0 { 
            logger.warning("Duration 0, cannot init windows")
            return 
        }
        
        var newWindows: [WindowRecord] = []
        
        // 1. Intro Window (First 5%)
        let introDuration = duration * WindowingStrategy.introWindowPercentage
        let introWindow = WindowRecord(windowIndex: 0, startTime: 0, endTime: introDuration, isIntro: true)
        newWindows.append(introWindow)
        
        // 2. Progressive Windows (Rest in 5 min chunks)
        // Only created if duration > intro
        if duration > introDuration {
            var currentTime = introDuration
            var idx = 1
            while currentTime < duration {
                let end = min(currentTime + progressiveWindowDuration, duration)
                let win = WindowRecord(windowIndex: idx, startTime: currentTime, endTime: end, isIntro: false)
                newWindows.append(win)
                currentTime += progressiveWindowDuration
                idx += 1
            }
        }
        
        await MainActor.run {
            episode.windowRecords = newWindows
        }
    }
    
    private func updateWindowStatus(_ window: WindowRecord, status: String, error: String? = nil) async {
        await MainActor.run {
            window.status = status
            window.error = error
        }
    }
    
    private func updateEpisodeStatus(_ episode: Episode?, status: String, error: String?) async {
        await MainActor.run {
            episode?.adDetectionStatus = status
            episode?.adDetectionError = error
        }
    }
    
    private func checkOverallCompletion(episode: Episode) async {
        await MainActor.run {
            let windows = episode.windowRecords ?? []
            let allDone = windows.allSatisfy { $0.status == "done" || ($0.status == "failed" && $0.retryCount > 2) } // naive
            
            // Logic differs by tier.
            // If Download tier, completion means ALL windows done.
            // If Streaming tier, completion is "caught up".
            // Let's just track if "all windows created are done".
            
            if allDone && !windows.isEmpty {
                episode.adDetectionStatus = "completed"
            } else {
                // If not all done, but we finished the current batch of processing:
                // Set to "idle" so the UI spinner stops.
                // It will go back to "processing" when the next batch starts.
                episode.adDetectionStatus = "idle"
            }
        }
    }

    // MARK: - Audio Processing (2x Speed + Compression)
    
    /// Extract audio chunk, speed up 2x, and compress to 24kbps AAC mono
    private func processAudioSegment(asset: AVAsset, start: TimeInterval, duration: TimeInterval) async throws -> Data? {
        let composition = AVMutableComposition()
        
        // Retry loading track just in case
        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
              let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            logger.error("Failed to load audio track")
            return nil
        }
        
        let timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        
        // Validate range
        let assetDuration = try? await asset.load(.duration)
        if let assetDur = assetDuration, timeRange.end > assetDur {
             // Clamp? Or fail?
             logger.warning("Requested range out of bounds")
             return nil
        }
        
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
    
    // MARK: - File Management
    
    private func ensureLocalFile(for context: EpisodeDetectionContext, tier: AdDetectionTier, windowIndex: Int) async -> URL? {
        // If downloaded, use it
        if context.isDownloaded, let path = context.localFilePath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        
        // Optimization: For Window 0 (Intro), try partial download first
        if windowIndex == 0 {
             // 12% to safely cover the 10% intro window (handling VBR variance)
             return await downloadFirstChunk(for: context, chunkPercent: 12)
        }
        
        // For other windows, we currently mandate full file
        // (Improving this to download specific ranges would be better but complex for AVURLAsset)
        return await ensureLocalFileFull(for: context)
    }
    
    /// Download valid 10% chunk for Intro window
    private func downloadFirstChunk(for context: EpisodeDetectionContext, chunkPercent: Int = 10) async -> URL? {
        guard let remoteURL = URL(string: context.audioURL) else { return nil }
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("ad-chunk-\(context.id.uuidString)-intro.mp3")
        
        if FileManager.default.fileExists(atPath: tempFile.path) { return tempFile }
        
        // ... (Reuse logic from old service: check size, range support, download bytes)
        // Simplified Logic for brevity in rewrite, assume standard range request:
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "HEAD"
        let size = (try? await URLSession.shared.data(for: request))?.1.expectedContentLength ?? 0
        if size > 0 {
            let limit = size * Int64(chunkPercent) / 100
             var dataReq = URLRequest(url: remoteURL)
            dataReq.setValue("bytes=0-\(limit)", forHTTPHeaderField: "Range")
            if let (data, resp) = try? await URLSession.shared.data(for: dataReq), (resp as? HTTPURLResponse)?.statusCode == 206 {
                try? data.write(to: tempFile)
                return tempFile
            }
        }
        
        // Fallback full download
        return await ensureLocalFileFull(for: context)
    }
    
    private func ensureLocalFileFull(for context: EpisodeDetectionContext) async -> URL? {
        guard let remoteURL = URL(string: context.audioURL) else { return nil }
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("ad-full-\(context.id.uuidString).mp3")
        
        if FileManager.default.fileExists(atPath: tempFile.path) { return tempFile }
        
        do {
            let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
            try FileManager.default.moveItem(at: tempURL, to: tempFile)
            return tempFile
        } catch {
            return nil
        }
    }
    
    private func cleanupTempFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// Extension for sorting
extension Array where Element == AdSegment {
    func sortedWithMerging() -> [AdSegment] {
        guard !self.isEmpty else { return [] }
        let sorted = self.sorted { $0.startTime < $1.startTime }
        
        var merged: [AdSegment] = [sorted[0]]
        
        for i in 1..<sorted.count {
            let current = sorted[i]
            let last = merged[merged.count - 1]
            
            // Merge if gap <= 15s or overlapping
            if current.startTime <= last.endTime + 15 {
                last.endTime = Swift.max(last.endTime, current.endTime)
                // Combine confidence (boost if both high?)
                last.confidence = Swift.max(last.confidence, current.confidence)
                
                // Append evidence if unique
                if let newEv = current.evidenceExcerpt, 
                   let lastEv = last.evidenceExcerpt, 
                   !lastEv.contains(newEv.prefix(10)) {
                    last.evidenceExcerpt = lastEv + " | " + newEv
                }
            } else {
                merged.append(current)
            }
        }
        return merged
    }
}

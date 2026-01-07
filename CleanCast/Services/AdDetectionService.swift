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

/// Sendable context for Window processing to allow passing to non-isolated background tasks
struct WindowProcessingContext: Sendable {
    let windowIndex: Int
    let startTime: TimeInterval
    let endTime: TimeInterval
}

/// Sendable result from background processing
struct WindowProcessingResult: Sendable {
    let segments: [AdSegmentData]
    let transcriptSegments: [GroqWhisperService.SegmentTimestamp]
    let error: String?
}

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

/// Singleton service (MainActor-isolated to safely interact with SwiftData/UI)
@MainActor
final class AdDetectionService {
    static let shared = AdDetectionService()
    
    // Dependencies
    private let logger = Logger(subsystem: "com.jonasgunklach.CleanCast", category: "AdDetection")
    private let settingsManager = SettingsManager.shared
    
    // Configuration
    private let progressiveWindowDuration: TimeInterval = 5 * 60  // 5 minutes
    
    // State (MainActor safe)
    private var activeWindows: Set<Int> = []
    
    private init() {}
    
    // MARK: - Public API
    
    /// Reset any windows stuck in "processing" state to "pending"
    func resetStuckWindows(for episode: Episode) {
        logger.info("♻️ [AdDetection] Checking for stuck windows in \(episode.title)")
        
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
            if episode.adDetectionStatus == "processing" {
                episode.adDetectionStatus = "partial_start"
            }
        }
        
        // Restore transcript
        let fullTranscript = windows
            .sorted { $0.windowIndex < $1.windowIndex }
            .compactMap { $0.transcriptChunk?.text }
            .joined(separator: "\n\n")
        
        if !fullTranscript.isEmpty && episode.transcript != fullTranscript {
            episode.transcript = fullTranscript
        }
    }

    /// Main entry point: Analyze episode segments
    func analyzeEpisode(
        context: EpisodeDetectionContext,
        episode: Episode,
        currentPlayhead: TimeInterval? = nil,
        targetWindowIndex: Int? = nil
    ) async {
        
        guard let apiKey = settingsManager.groqAPIKey, !apiKey.isEmpty else {
            episode.adDetectionStatus = "failed"
            episode.adDetectionError = "Groq API key not configured"
            return
        }
        
        // 1. Initialize logic
        await initializeWindowsIfNeeded(episode: episode, context: context)
        
        // 2. Filter logic
        let wins = episode.windowRecords ?? []
        let strategy = WindowingStrategy(tier: settingsManager.adDetectionTier)
        let tier = settingsManager.adDetectionTier
        
        let windowsToProcess = wins.filter { window in
            guard window.status == "pending" || window.status == "failed" else { return false }
            
            let allowed = strategy.shouldProcess(
                windowIndex: window.windowIndex,
                totalDuration: episode.duration,
                currentPlayhead: currentPlayhead
            )
            
            if let target = targetWindowIndex {
                return allowed && window.windowIndex == target
            }
            return allowed
        }.sorted { $0.windowIndex < $1.windowIndex }
        
        if windowsToProcess.isEmpty {
            checkOverallCompletion(episode: episode)
            return
        }
        
        // 3. Process Windows
        episode.adDetectionStatus = "processing"
        episode.adDetectionError = nil
        
        for window in windowsToProcess {
            // Check cancellation (though we are on Main, yielding allows checking)
            if Task.isCancelled { break }
            
            if activeWindows.contains(window.windowIndex) {
                 logger.warning("⚠️ [Window \(window.windowIndex)] Skipped - already active")
                 continue
            }
            activeWindows.insert(window.windowIndex)
            
            // Start Processing
            window.status = "processing"
            
            // Prepare Contexts for detached task
            let winContext = WindowProcessingContext(
                windowIndex: window.windowIndex,
                startTime: window.startTime,
                endTime: window.endTime
            )
            
            // Get File URL (Async but usually fast)
            // Note: `ensureLocalFile` accesses disk/network, so we should be careful.
            // But since this service is MainActor, we should ideally offload download too?
            // For now, let's keep it simple: call it here, valid URL passed to bg.
            guard let localURL = await ensureLocalFile(for: context, tier: tier, windowIndex: window.windowIndex) else {
                window.status = "failed"
                window.error = "Download failed"
                activeWindows.remove(window.windowIndex)
                try? episode.modelContext?.save()
                continue
            }
            
            // Offload Heavy Work to Background (Non-Isolated)
            // We await it here without blocking the UI because the await suspends.
            let result = await performHeavyProcessing(
                context: winContext,
                fileURL: localURL,
                apiKey: apiKey
            )
            
            // Handle Result (Back on MainActor)
            if let error = result.error {
                logger.error("❌ [Window \(window.windowIndex)] Failed: \(error)")
                window.status = "failed"
                window.error = error
            } else {
                finalizeWindowResult(episode: episode, window: window, result: result)
            }
            
            activeWindows.remove(window.windowIndex)
            try? episode.modelContext?.save()
        }
        
        checkOverallCompletion(episode: episode)
    }
    
    // MARK: - Post-Processing (Main Thread)
    
    private func finalizeWindowResult(episode: Episode, window: WindowRecord, result: WindowProcessingResult) {
        logger.info("✅ [Window \(window.windowIndex)] Success: \(result.segments.count) ads")
        
        // 1. Save Transcript Chunk
        let segmentsJSON = (try? JSONEncoder().encode(result.transcriptSegments)) ?? Data()
        let jsonString = String(data: segmentsJSON, encoding: .utf8) ?? "[]"
        let formattedText = result.transcriptSegments.map { "[\(Int($0.start))-\(Int($0.end))] \($0.text)" }.joined(separator: "\n")
        
        if let existing = window.transcriptChunk {
            existing.text = formattedText
            existing.segmentsJSON = jsonString
        } else {
            let chunk = TranscriptChunk(text: formattedText, segmentsJSON: jsonString)
            window.modelContext?.insert(chunk)
            window.transcriptChunk = chunk
            chunk.window = window
        }
        
        // 2. Save Ad Segments (convert from AdSegmentData to AdSegment model)
        var currentAds = episode.adSegments ?? []
        let newAdSegments = result.segments.map { $0.toAdSegment() }
        currentAds.append(contentsOf: newAdSegments)
        episode.adSegments = currentAds.sortedWithMerging()
        
        // 3. Update Full Transcript
        if let wins = episode.windowRecords {
            let fullText = wins.sorted { $0.windowIndex < $1.windowIndex }
                .compactMap { $0.transcriptChunk?.text }
                .joined(separator: "\n\n")
            if !fullText.isEmpty {
                 episode.transcript = fullText
            }
        }
        
        window.status = "done"
        window.error = nil
    }
    
    private func checkOverallCompletion(episode: Episode) {
        let wins = episode.windowRecords ?? []
        let allDone = wins.allSatisfy { $0.status == "done" || ($0.status == "failed" && $0.retryCount > 2) }
        episode.adDetectionStatus = (allDone && !wins.isEmpty) ? "completed" : "idle"
        try? episode.modelContext?.save()
    }
    
    private func initializeWindowsIfNeeded(episode: Episode, context: EpisodeDetectionContext) async {
        if let w = episode.windowRecords, !w.isEmpty { return }
        logger.info("Preparing windows for \(context.title)")
        
        let duration = episode.duration
        // Assuming metadata handled or duration > 0
        guard duration > 0 else { return }
        
        var newWindows: [WindowRecord] = []
        let introDuration = duration * WindowingStrategy.introWindowPercentage
        newWindows.append(WindowRecord(windowIndex: 0, startTime: 0, endTime: introDuration, isIntro: true))
        
        if duration > introDuration {
            var curr = introDuration
            var idx = 1
            while curr < duration {
                let end = min(curr + progressiveWindowDuration, duration)
                newWindows.append(WindowRecord(windowIndex: idx, startTime: curr, endTime: end, isIntro: false))
                curr += progressiveWindowDuration
                idx += 1
            }
        }
        episode.windowRecords = newWindows
        try? episode.modelContext?.save()
    }
    
    // MARK: - File Management (MainActor-side mainly, or detached)
    
    private func ensureLocalFile(for context: EpisodeDetectionContext, tier: AdDetectionTier, windowIndex: Int) async -> URL? {
        if context.isDownloaded, let path = context.localFilePath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if windowIndex == 0 {
             return await downloadFirstChunk(for: context, chunkPercent: 12)
        }
        return await ensureLocalFileFull(for: context)
    }
    
    // Simplistic downloads suitable for calling from Main (async)
    // In production, move to a separate DownloadManager actor
    private func downloadFirstChunk(for context: EpisodeDetectionContext, chunkPercent: Int) async -> URL? {
        // ... (Same logic as before, just async)
         guard let url = URL(string: context.audioURL) else { return nil }
         let temp = FileManager.default.temporaryDirectory.appendingPathComponent("chunk-\(context.id).mp3")
         if FileManager.default.fileExists(atPath: temp.path) { return temp }
         
         var req = URLRequest(url: url); req.httpMethod = "HEAD"
         let size = (try? await URLSession.shared.data(for: req))?.1.expectedContentLength ?? 0
         if size > 0 {
             let limit = size * Int64(chunkPercent) / 100
             var r = URLRequest(url: url)
             r.setValue("bytes=0-\(limit)", forHTTPHeaderField: "Range")
             if let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 206 {
                 try? d.write(to: temp); return temp
             }
         }
         return await ensureLocalFileFull(for: context)
    }
    
    private func ensureLocalFileFull(for context: EpisodeDetectionContext) async -> URL? {
        guard let url = URL(string: context.audioURL) else { return nil }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("full-\(context.id).mp3")
        if FileManager.default.fileExists(atPath: temp.path) { return temp }
        if let (loc, _) = try? await URLSession.shared.download(from: url) {
            try? FileManager.default.moveItem(at: loc, to: temp); return temp
        }
        return nil
    }
}

// MARK: - Non-Isolated Heavy Processing
// This runs on the generic thread pool, keeping the UI responsive.
nonisolated func performHeavyProcessing(
    context: WindowProcessingContext,
    fileURL: URL,
    apiKey: String
) async -> WindowProcessingResult {
    let asset = AVURLAsset(url: fileURL)
    
    do {
        // STEP A & B: Process Chunks (Parallel)
        let chunkDuration: TimeInterval = 60
        var ranges: [(start: TimeInterval, duration: TimeInterval)] = []
        for s in stride(from: context.startTime, to: context.endTime, by: chunkDuration) {
            ranges.append((s, min(chunkDuration, context.endTime - s)))
        }
        
        let allSegments = await withTaskGroup(of: [GroqWhisperService.SegmentTimestamp]?.self) { group in
            var results: [[GroqWhisperService.SegmentTimestamp]] = []
            var iterator = ranges.makeIterator()
            let maxConcurrency = 3
            var active = 0
            
            func submitNext() {
                guard let range = iterator.next() else { return }
                group.addTask {
                    guard let data = try? await processAudioSegmentNonIsolated(asset: asset, start: range.start, duration: range.duration) else { return nil }
                    // Groq Service is thread-safe (singleton is often safe or immutable)
                    // Assuming GroqWhisperService.shared is sendable/actor-like or thread-safe
                    guard let res = try? await GroqWhisperService.shared.transcribe(audioData: data, apiKey: apiKey) else { return nil }
                    return res.segments.map {
                        GroqWhisperService.SegmentTimestamp(start: $0.start + range.start, end: $0.end + range.start, text: $0.text)
                    }
                }
                active += 1
            }
            
            for _ in 0..<maxConcurrency { submitNext() }
            for await res in group {
                active -= 1; if let r = res { results.append(r) }; submitNext()
            }
            // Sort
            return results.flatMap { $0 }.sorted { $0.start < $1.start }
        }
        
        let realSegments = allSegments
        
        // Step C: Stage 1
        let stage1 = Stage1CoarseService.shared
        let stage1Result = try await stage1.analyze(
            transcriptSegments: realSegments,
            blockStart: context.startTime,
            blockDuration: context.endTime - context.startTime,
            apiKey: apiKey
        )
        
        if stage1Result.positiveBlocks.isEmpty {
            return WindowProcessingResult(segments: [], transcriptSegments: realSegments, error: nil)
        }
        
        // Step D: Candidates
        // (Duplicate buildCandidateRuns logic here or make it static helper)
        let candidates = buildCandidateRunsNonIsolated(stage1Result: stage1Result, allSegments: realSegments, windowStart: context.startTime, windowEnd: context.endTime)
        
        // Step E/F: Stage 2
        var finalSegments: [AdSegmentData] = []
        let stage2 = Stage2RefineService.shared
        let arb = AdArbitrationService.shared
        
        for run in candidates {
            let res = try await stage2.refine(candidateText: run.text, sentences: run.sentences, apiKey: apiKey)
            let merged = await arb.arbitrate(segmentsA: res.segmentsA, segmentsB: res.segmentsB)
            finalSegments.append(contentsOf: merged)
        }
        
        return WindowProcessingResult(segments: finalSegments, transcriptSegments: realSegments, error: nil)
        
    } catch {
        return WindowProcessingResult(segments: [], transcriptSegments: [], error: error.localizedDescription)
    }
}

// Helper: Extract audio (Non-Isolated)
nonisolated func processAudioSegmentNonIsolated(asset: AVAsset, start: TimeInterval, duration: TimeInterval) async throws -> Data? {
    let composition = AVMutableComposition()
    guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
          let compTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
    
    let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: duration, preferredTimescale: 600))
    try compTrack.insertTimeRange(range, of: track, at: .zero)
    
    let scaled = CMTimeMultiplyByFloat64(range.duration, multiplier: 0.5)
    compTrack.scaleTimeRange(CMTimeRange(start: .zero, duration: range.duration), toDuration: scaled)
    
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
    defer { try? FileManager.default.removeItem(at: tempURL) }
    
    let writer = try AVAssetWriter(outputURL: tempURL, fileType: .m4a)
    let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32000
    ]
    let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
    input.expectsMediaDataInRealTime = false
    writer.add(input)
    
    let reader = try AVAssetReader(asset: composition)
    let output = AVAssetReaderTrackOutput(track: compTrack, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsNonInterleaved: false, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsFloatKey: false
    ])
    reader.add(output)
    
    reader.startReading(); writer.startWriting(); writer.startSession(atSourceTime: .zero)
    
    let queue = DispatchQueue(label: "audio.bg")
    let wIn = UnsafeSendable(value: input); let rOut = UnsafeSendable(value: output); let w = UnsafeSendable(value: writer)
    
    await withCheckedContinuation { continuation in
        input.requestMediaDataWhenReady(on: queue) {
            let wi = wIn.value; let ro = rOut.value; let wr = w.value
            while wi.isReadyForMoreMediaData {
                if let buff = ro.copyNextSampleBuffer() { wi.append(buff) }
                else { wi.markAsFinished(); wr.finishWriting { continuation.resume() }; break }
            }
        }
    }
    
    if writer.status == .completed { return try Data(contentsOf: tempURL) }
    return nil
}

// Helper: Build Candidates (Non-Isolated)
nonisolated func buildCandidateRunsNonIsolated(stage1Result: Stage1Result, allSegments: [GroqWhisperService.SegmentTimestamp], windowStart: TimeInterval, windowEnd: TimeInterval) -> [AdDetectionService.CandidateRun] {
    // Replicate logic or move duplicate struct to top level
    // Assuming CandidateRun is made visible or duplicated
    // For now, let's use the struct defined in AdDetectionService extensions if possible
    // Note: Nested structs are hard to access from nonisolated.
    // Better to define CandidateRun at file scope.
    
    let blocks = stage1Result.positiveBlocks.sorted()
    if blocks.isEmpty { return [] }
    
    var runs: [(start: Int, end: Int)] = []
    var start = blocks[0]; var end = blocks[0]
    
    for i in 1..<blocks.count {
        if blocks[i] == end + 1 { end = blocks[i] }
        else { runs.append((start, end)); start = blocks[i]; end = blocks[i] }
    }
    runs.append((start, end))
    
    var candidates: [AdDetectionService.CandidateRun] = []
    let padding: TimeInterval = 45
    
    for run in runs {
        let rs = windowStart + Double(run.start) * 60
        let re = windowStart + Double(run.end + 1) * 60
        let ps = max(windowStart, rs - padding)
        let pe = min(windowEnd, re + padding)
        
        let segs = allSegments.filter { $0.end > ps && $0.start < pe }
        if segs.isEmpty { continue }
        
        var sentences: [IndexedSentence] = []
        var txt = ""
        for (i, s) in segs.enumerated() {
            sentences.append(IndexedSentence(id: i, start: s.start, end: s.end, text: s.text))
            txt += s.text + " "
        }
        candidates.append(AdDetectionService.CandidateRun(text: txt, sentences: sentences, startTime: ps, endTime: pe))
    }
    return candidates
}

// Make CandidateRun visible
extension AdDetectionService {
    struct CandidateRun {
        let text: String
        let sentences: [IndexedSentence]
        let startTime: TimeInterval
        let endTime: TimeInterval
    }
}

// Helpers
extension Array where Element == AdSegment {
    func sortedWithMerging() -> [AdSegment] {
        guard !isEmpty else { return [] }
        let sorted = self.sorted { $0.startTime < $1.startTime }
        var merged: [AdSegment] = [sorted[0]]
        for i in 1..<sorted.count {
            let curr = sorted[i]; let last = merged[merged.count - 1]
            if curr.startTime <= last.endTime + 15 {
                last.endTime = Swift.max(last.endTime, curr.endTime)
                last.confidence = Swift.max(last.confidence, curr.confidence)
                if let nE = curr.evidenceExcerpt, let lE = last.evidenceExcerpt, !lE.contains(nE.prefix(10)) {
                    last.evidenceExcerpt = lE + " | " + nE
                }
            } else { merged.append(curr) }
        }
        return merged
    }
}

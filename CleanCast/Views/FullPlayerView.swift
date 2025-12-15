import SwiftUI

struct FullPlayerView: View {
    @Binding var showFullPlayer: Bool
    @Environment(AudioManager.self) private var audioManager
    @Environment(\.colorScheme) var colorScheme
    @State private var isDragging = false
    @State private var sliderValue: Double = 0.0
    @State private var selectedTab = 0
    
    // Drag to dismiss state
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. Solid Base Background (prevents transparency)
                Color.black.ignoresSafeArea()
                
                // 2. Dynamic Blurred Background
                if let url = audioManager.currentEpisode?.podcast?.imageURL {
                    AsyncImage(url: url) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .blur(radius: 50)
                            .overlay(Color.black.opacity(0.4))
                            .ignoresSafeArea()
                    } placeholder: {
                        Color.black.ignoresSafeArea()
                    }
                } else {
                    Color.black.ignoresSafeArea()
                }
                
                TabView(selection: $selectedTab) {
                    // Page 0: Player Controls
                    VStack(spacing: 30) {
                        // Drag Handle
                        Capsule()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 60, height: 5)
                            .padding(.top, 10)
                        
                        Spacer()
                        
                        // Artwork
                        if let url = audioManager.currentEpisode?.podcast?.imageURL {
                             let size = max(0, geometry.size.width - 60)
                             AsyncImage(url: url) { image in
                                 image.resizable().aspectRatio(contentMode: .fill)
                             } placeholder: {
                                 Color.gray.opacity(0.3)
                             }
                             .frame(width: size, height: size)
                             .cornerRadius(12)
                             .shadow(radius: 20)
                             .scaleEffect(audioManager.isPlaying ? 1.0 : 0.75)
                             .animation(.spring(response: 0.5, dampingFraction: 0.7), value: audioManager.isPlaying)
                        } else {
                             let size = max(0, geometry.size.width - 60)
                             RoundedRectangle(cornerRadius: 12)
                                 .fill(Color.gray.opacity(0.3))
                                 .frame(width: size, height: size)
                                 .scaleEffect(audioManager.isPlaying ? 1.0 : 0.75)
                                 .animation(.spring(response: 0.5, dampingFraction: 0.7), value: audioManager.isPlaying)
                        }
                        
                        // Info
                        VStack(spacing: 8) {
                            Text(audioManager.currentEpisode?.title ?? "Not Playing")
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .foregroundStyle(.white) // Ensure white text on dark blurred background
                            
                            Text(audioManager.currentEpisode?.podcast?.title ?? "")
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        .padding(.horizontal)
                        
                        // Progress
                        VStack(spacing: 8) {
                            Slider(value: $sliderValue, in: 0...(audioManager.duration > 0 ? audioManager.duration : 1)) { editing in
                                isDragging = editing
                                if !editing {
                                    audioManager.seek(to: sliderValue)
                                }
                            }
                            .tint(.white) 
                            .background(
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        if let segments = audioManager.currentEpisode?.adSegments, audioManager.duration > 0 {
                                            ForEach(segments) { segment in
                                                let startPercent = segment.startTime / audioManager.duration
                                                let endPercent = segment.endTime / audioManager.duration
                                                let width = (endPercent - startPercent) * geometry.size.width
                                                let startOffset = startPercent * geometry.size.width
                                                
                                                Rectangle()
                                                    .fill(Color.yellow.opacity(0.8))
                                                    .frame(width: max(2, width), height: 4)
                                                    .offset(x: startOffset)
                                            }
                                        }
                                    }
                                    .frame(height: 4)
                                    .offset(y: 14)
                                }
                            )
                            .overlay(alignment: .top) {
                                 if isDragging {
                                     Text(format(sliderValue))
                                         .font(.system(size: 14, weight: .bold))
                                         .foregroundStyle(.black)
                                         .padding(8)
                                         .background(Capsule().fill(Color.white))
                                         .offset(y: -40)
                                         .transition(.opacity)
                                 }
                            }
                            
                            HStack {
                                Text(format(audioManager.currentTime))
                                Spacer()
                                Text(format(audioManager.duration))
                            }
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 30)
                        
                        // Controls
                        HStack(spacing: 50) {
                            Button {
                                audioManager.seek(to: audioManager.currentTime - 15)
                            } label: {
                                Image(systemName: "gobackward.15")
                                    .font(.largeTitle)
                            }
                            
                            Button {
                                audioManager.togglePlayPause()
                            } label: {
                                Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 70))
                            }
                            
                            Button {
                                audioManager.seek(to: audioManager.currentTime + 30)
                            } label: {
                                Image(systemName: "goforward.30")
                                    .font(.largeTitle)
                            }
                        }
                        .foregroundStyle(.white)
                        
                        // Bottom Actions (Speed, Sleep) - RESTORED
                        HStack(spacing: 40) {
                            // Speed
                            Menu {
                                Picker("Speed", selection: Bindable(audioManager).playbackRate) {
                                    ForEach([0.7, 0.8, 0.9, 1.0, 1.2, 1.5, 1.7, 2.0], id: \.self) { rate in
                                        Text("\(String(format: "%.1fx", rate))").tag(Float(rate))
                                    }
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Text("\(String(format: "%.1fx", audioManager.playbackRate))")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("Speed")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                            }
                            
                            // Sleep Timer
                            Menu {
                                Button("Off") { audioManager.invalidateSleepTimer() }
                                Button("5 min") { audioManager.startSleepTimer(minutes: 5) }
                                Button("10 min") { audioManager.startSleepTimer(minutes: 10) }
                                Button("15 min") { audioManager.startSleepTimer(minutes: 15) }
                                Button("30 min") { audioManager.startSleepTimer(minutes: 30) }
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: audioManager.sleepTimer != nil ? "moon.fill" : "moon")
                                        .font(.system(size: 18))
                                    Text(audioManager.sleepTimer != nil ? "On" : "Sleep")
                                        .font(.caption2)
                                }
                                .foregroundStyle(audioManager.sleepTimer != nil ? .yellow : .white.opacity(0.8))
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.bottom, 60) // Increased padding to clear tab dots
                    }
                    .tag(0)
                    
                    // Page 1: Up Next Queue
                    UpNextView()
                        .tag(1)
                    
                    // Page 2: Transcript - RESTORED
                    //if let episode = audioManager.currentEpisode {
                    //    TranscriptView(episode: episode)
                    //        .tag(2)
                    //}
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
            .offset(y: dragOffset.height) // Apply drag offset
            .highPriorityGesture( // changed to highPriorityGesture for better responsiveness
                DragGesture()
                    .onChanged { gesture in
                        if gesture.translation.height > 0 {
                            dragOffset = gesture.translation
                        }
                    }
                    .onEnded { gesture in
                        if gesture.translation.height > 100 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showFullPlayer = false
                            }
                            dragOffset = .zero
                        } else {
                            withAnimation(.spring()) {
                                dragOffset = .zero
                            }
                        }
                    }
            )
        }
        .preferredColorScheme(.dark) // Force dark mode for readability against blurred background
        .onAppear {
            sliderValue = audioManager.currentTime
        }
        .onChange(of: audioManager.currentTime) { _, newValue in
             if !isDragging {
                 sliderValue = newValue
             }
        }
    }
    
    func format(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        if duration >= 3600 { formatter.allowedUnits.insert(.hour) }
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "0:00"
    }
}



import SwiftUI

struct CustomSliderView: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let accentColor: Color
    let onDragChanged: ((Double) -> Void)?
    let onDragEnded: ((Double) -> Void)?
    
    @State private var isDragging: Bool = false
    @State private var dragValue: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 4)
                    .cornerRadius(2)
                
                // Progress
                Rectangle()
                    .fill(accentColor)
                    .frame(width: progressWidth(in: geometry), height: 4)
                    .cornerRadius(2)
                
                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .offset(x: thumbOffset(in: geometry))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                if !isDragging {
                                    isDragging = true
                                }
                                let newValue = valueFromLocation(gesture.location.x, in: geometry)
                                dragValue = newValue
                                // Only update visual state during drag, don't seek yet
                                onDragChanged?(newValue)
                            }
                            .onEnded { gesture in
                                let newValue = valueFromLocation(gesture.location.x, in: geometry)
                                dragValue = newValue
                                value = newValue
                                isDragging = false
                                // Seek only when drag ends
                                onDragEnded?(newValue)
                            }
                    )
            }
            .overlay(alignment: .topLeading) {
                // Drag indicator - appears above the slider, centered on thumb
                if isDragging {
                    let thumbCenterX = thumbOffset(in: geometry) + 8 // Center of thumb
                    VStack(spacing: 4) {
                        Text(formatTime(dragValue))
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.black.opacity(0.8))
                            )
                        
                        // Arrow pointing down
                        Triangle()
                            .fill(Color.black.opacity(0.8))
                            .frame(width: 8, height: 4)
                    }
                    .offset(x: thumbCenterX - 30, y: -35) // Approx center of indicator (60px wide)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: thumbCenterX)
                }
            }
        }
        .frame(height: 16)
        .onChange(of: value) { _, newValue in
            if !isDragging {
                dragValue = newValue
            }
        }
        .onAppear {
            dragValue = value
        }
    }
    
    private func progressWidth(in geometry: GeometryProxy) -> CGFloat {
        let currentValue = isDragging ? dragValue : value
        let progress = (currentValue - range.lowerBound) / (range.upperBound - range.lowerBound)
        return max(0, min(geometry.size.width, geometry.size.width * CGFloat(progress)))
    }
    
    private func thumbOffset(in geometry: GeometryProxy) -> CGFloat {
        let currentValue = isDragging ? dragValue : value
        let progress = (currentValue - range.lowerBound) / (range.upperBound - range.lowerBound)
        let maxOffset = geometry.size.width - 16
        return max(0, min(maxOffset, maxOffset * CGFloat(progress)))
    }
    
    private func valueFromLocation(_ x: CGFloat, in geometry: GeometryProxy) -> Double {
        let clampedX = max(0, min(geometry.size.width, x))
        let progress = Double(clampedX / geometry.size.width)
        return range.lowerBound + progress * (range.upperBound - range.lowerBound)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        if time >= 3600 { formatter.allowedUnits.insert(.hour) }
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: time) ?? "0:00"
    }
}

// Triangle shape for the indicator arrow
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}


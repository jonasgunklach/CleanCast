import SwiftUI
import UIKit

struct ArtworkColors {
    let primary: Color
    let secondary: Color
    let accent: Color
    
    static let `default` = ArtworkColors(
        primary: .blue,
        secondary: .purple,
        accent: .pink
    )
}

final class ArtworkColorExtractor {
    static let shared = ArtworkColorExtractor()
    
    private init() {}
    
    func extractColors(from image: UIImage) -> ArtworkColors {
        // Resize image for faster processing
        let size = CGSize(width: 100, height: 100)
        guard let resized = image.resized(to: size) else {
            return .default
        }
        
        // Extract dominant colors using k-means-like approach
        guard let cgImage = resized.cgImage else {
            return .default
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return .default
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Sample pixels (every 5th pixel for performance)
        var colors: [(r: Double, g: Double, b: Double)] = []
        for y in stride(from: 0, to: height, by: 5) {
            for x in stride(from: 0, to: width, by: 5) {
                let index = (y * width + x) * bytesPerPixel
                guard index + 2 < pixelData.count else { continue }
                let r = Double(pixelData[index]) / 255.0
                let g = Double(pixelData[index + 1]) / 255.0
                let b = Double(pixelData[index + 2]) / 255.0
                
                // Skip very dark or very light colors (likely borders/background)
                let brightness = (r + g + b) / 3.0
                if brightness > 0.15 && brightness < 0.95 {
                    colors.append((r: r, g: g, b: b))
                }
            }
        }
        
        guard !colors.isEmpty else {
            return .default
        }
        
        // Find dominant colors by averaging similar colors
        let primary = findDominantColor(in: colors)
        let secondary = findSecondaryColor(in: colors, excluding: primary)
        let accent = findAccentColor(in: colors, excluding: [primary, secondary])
        
        return ArtworkColors(
            primary: Color(red: primary.r, green: primary.g, blue: primary.b),
            secondary: Color(red: secondary.r, green: secondary.g, blue: secondary.b),
            accent: Color(red: accent.r, green: accent.g, blue: accent.b)
        )
    }
    
    private func findDominantColor(in colors: [(r: Double, g: Double, b: Double)]) -> (r: Double, g: Double, b: Double) {
        // Find the most saturated color
        let sorted = colors.sorted { color1, color2 in
            let sat1 = saturation(color1)
            let sat2 = saturation(color2)
            return sat1 > sat2
        }
        
        // Take top 20% and average them
        let count = max(1, sorted.count / 5)
        let top = Array(sorted.prefix(count))
        
        return averageColor(top)
    }
    
    private func findSecondaryColor(in colors: [(r: Double, g: Double, b: Double)], excluding: (r: Double, g: Double, b: Double)) -> (r: Double, g: Double, b: Double) {
        // Find colors that are different from excluded
        let filtered = colors.filter { color in
            colorDistance(color, excluding) > 0.2
        }
        
        guard !filtered.isEmpty else {
            return hueShift(excluding, by: 0.3)
        }
        
        let sorted = filtered.sorted { color1, color2 in
            let sat1 = saturation(color1)
            let sat2 = saturation(color2)
            return sat1 > sat2
        }
        
        let count = max(1, sorted.count / 5)
        let top = Array(sorted.prefix(count))
        
        return averageColor(top)
    }
    
    private func findAccentColor(in colors: [(r: Double, g: Double, b: Double)], excluding: [(r: Double, g: Double, b: Double)]) -> (r: Double, g: Double, b: Double) {
        let filtered = colors.filter { color in
            !excluding.contains { excluded in
                colorDistance(color, excluded) < 0.15
            }
        }
        
        guard !filtered.isEmpty else {
            // Create a complementary color
            let base = excluding.first ?? (r: 0.5, g: 0.5, b: 0.5)
            return hueShift(base, by: 0.5)
        }
        
        // Find a bright, vibrant color
        let sorted = filtered.sorted { color1, color2 in
            let brightness1 = (color1.r + color1.g + color1.b) / 3.0
            let brightness2 = (color2.r + color2.g + color2.b) / 3.0
            let sat1 = saturation(color1)
            let sat2 = saturation(color2)
            return (brightness1 + sat1) > (brightness2 + sat2)
        }
        
        let count = max(1, sorted.count / 3)
        let top = Array(sorted.prefix(count))
        
        return averageColor(top)
    }
    
    private func saturation(_ color: (r: Double, g: Double, b: Double)) -> Double {
        let max = Swift.max(color.r, color.g, color.b)
        let min = Swift.min(color.r, color.g, color.b)
        guard max > 0 else { return 0 }
        return (max - min) / max
    }
    
    private func averageColor(_ colors: [(r: Double, g: Double, b: Double)]) -> (r: Double, g: Double, b: Double) {
        guard !colors.isEmpty else { return (0.5, 0.5, 0.5) }
        let sum = colors.reduce((r: 0.0, g: 0.0, b: 0.0)) { acc, color in
            (acc.r + color.r, acc.g + color.g, acc.b + color.b)
        }
        let count = Double(colors.count)
        return (sum.r / count, sum.g / count, sum.b / count)
    }
    
    private func colorDistance(_ c1: (r: Double, g: Double, b: Double), _ c2: (r: Double, g: Double, b: Double)) -> Double {
        let dr = c1.r - c2.r
        let dg = c1.g - c2.g
        let db = c1.b - c2.b
        return sqrt(dr * dr + dg * dg + db * db)
    }
    
    private func hueShift(_ color: (r: Double, g: Double, b: Double), by shift: Double) -> (r: Double, g: Double, b: Double) {
        // Simple hue shift approximation
        let hue = atan2(sqrt(3) * (color.g - color.b), 2 * color.r - color.g - color.b) / (2 * .pi)
        let newHue = hue + shift
        
        // Convert back to RGB (simplified)
        let s = saturation(color)
        let v = Swift.max(color.r, color.g, color.b)
        
        let i = floor(newHue * 6)
        let f = newHue * 6 - i
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
        
        switch Int(i) % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}

private extension UIImage {
    func resized(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

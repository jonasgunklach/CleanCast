import SwiftUI
import UIKit

struct ColorManager {
    static let shared = ColorManager()
    
    // Returns (Background, Accent)
    func extractColors(from image: UIImage) -> (background: Color, accent: Color) {
        guard let avg = image.averageColor else {
             return (Color.black, Color.blue)
        }
        
        let bg = Color(uiColor: avg)
        
        // Simple heuristic for accent: 
        // If background is dark, accent is white or light vibrant version.
        // If background is light, accent is dark.
        // For now, let's just shift hue or use a complementary strategy if we want, 
        // but to keep it safe and legible, let's derive a secondary color or use white/primary.
        // Let's try to simulate a 'vibrant' color by boosting saturation.
        
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        avg.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        // Make accent high saturation and brightness
        let accentUI = UIColor(hue: hue, saturation: min(saturation + 0.5, 1.0), brightness: min(brightness + 0.5, 1.0), alpha: 1.0)
        let accent = Color(uiColor: accentUI)
        
        return (bg, accent)
    }
    
    func hexString(from color: Color) -> String {
        guard let components = color.cgColor?.components else { return "#000000" }
        let r = components[0]
        let g = components.count >= 2 ? components[1] : r
        let b = components.count >= 3 ? components[2] : r
        
        return String(format: "#%02lX%02lX%02lX", lroundf(Float(r * 255)), lroundf(Float(g * 255)), lroundf(Float(b * 255)))
    }
    
    func color(from hex: String) -> Color {
        var cString: String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if (cString.hasPrefix("#")) {
            cString.remove(at: cString.startIndex)
        }

        if ((cString.count) != 6) {
            return Color.gray
        }

        var rgbValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)

        return Color(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0
        )
    }
}

extension UIImage {
    // Simple average color implementation to make it slightly better than static placeholder
    var averageColor: UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extentVector = CIVector(x: inputImage.extent.origin.x, y: inputImage.extent.origin.y, z: inputImage.extent.size.width, w: inputImage.extent.size.height)

        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]) else { return nil }
        guard let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

        return UIColor(red: CGFloat(bitmap[0]) / 255, green: CGFloat(bitmap[1]) / 255, blue: CGFloat(bitmap[2]) / 255, alpha: CGFloat(bitmap[3]) / 255)
    }
}

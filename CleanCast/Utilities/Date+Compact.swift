import Foundation

extension Date {
    func compactTimeAgo() -> String {
        let diff = Date().timeIntervalSince(self)
        
        if diff < 60 {
            return "Just now"
        } else if diff < 3600 {
            return String(format: "%.0fm", diff / 60)
        } else if diff < 86400 {
            return String(format: "%.0fh", diff / 3600)
        } else if diff < 604800 {
            return String(format: "%.0fd", diff / 86400)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yy"
            return formatter.string(from: self)
        }
    }
}

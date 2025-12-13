import Foundation

class SettingsManager {
    static let shared = SettingsManager()
    
    private let kGroqAPIKey = "groq_api_key"
    
    // Default key from previous context
    private let defaultKey = "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"
    
    var groqAPIKey: String? {
        get {
            // Check UserDefaults first, then fallback to default
            if let saved = UserDefaults.standard.string(forKey: kGroqAPIKey), !saved.isEmpty {
                return saved
            }
            return defaultKey
        }
        set {
            UserDefaults.standard.set(newValue, forKey: kGroqAPIKey)
        }
    }
    
    private init() {}
}

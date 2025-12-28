import Foundation

class SettingsManager {
    static let shared = SettingsManager()
    
    private let kGroqAPIKey = "groq_api_key"
    
    // Ad type skip preference keys
    private let kSkipPaidAds = "skip_paid_ads"
    private let kSkipSelfPromo = "skip_self_promo"
    private let kSkipCrossPromo = "skip_cross_promo"
    private let kSkipProductMention = "skip_product_mention"
    
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
    
    // MARK: - Ad Type Skip Preferences
    
    /// Skip paid sponsor ads (default: true)
    var skipPaidAds: Bool {
        get {
            // Default to true if not set
            if UserDefaults.standard.object(forKey: kSkipPaidAds) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: kSkipPaidAds)
        }
        set { UserDefaults.standard.set(newValue, forKey: kSkipPaidAds) }
    }
    
    /// Skip self-promotion (Patreon, merch, etc.) (default: false)
    var skipSelfPromo: Bool {
        get { UserDefaults.standard.bool(forKey: kSkipSelfPromo) }
        set { UserDefaults.standard.set(newValue, forKey: kSkipSelfPromo) }
    }
    
    /// Skip cross-promotion (other podcasts) (default: false)
    var skipCrossPromo: Bool {
        get { UserDefaults.standard.bool(forKey: kSkipCrossPromo) }
        set { UserDefaults.standard.set(newValue, forKey: kSkipCrossPromo) }
    }
    
    /// Skip product mentions (organic) (default: false)
    var skipProductMention: Bool {
        get { UserDefaults.standard.bool(forKey: kSkipProductMention) }
        set { UserDefaults.standard.set(newValue, forKey: kSkipProductMention) }
    }
    
    /// Check if a specific ad type should be skipped
    func shouldSkip(adType: String?) -> Bool {
        guard let type = adType?.lowercased() else { return skipPaidAds } // Default to paid_ad behavior
        
        switch type {
        case "paid_ad":
            return skipPaidAds
        case "self_promo":
            return skipSelfPromo
        case "cross_promo":
            return skipCrossPromo
        case "product_mention":
            return skipProductMention
        default:
            // For legacy types or unknown, treat as paid_ad
            return skipPaidAds
        }
    }
    
    private init() {}
}

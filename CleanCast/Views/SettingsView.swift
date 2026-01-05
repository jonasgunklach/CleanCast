import SwiftUI

struct SettingsView: View {
    @AppStorage("autoSkipAds") private var autoSkipAds = true
    @AppStorage("autoDownloadNewest") private var autoDownloadNewest = false
    @AppStorage("downloadCount") private var downloadCount = 3
    
    // Ad type skip preferences
    @AppStorage("skip_paid_ads") private var skipPaidAds = true
    @AppStorage("skip_self_promo") private var skipSelfPromo = false
    @AppStorage("skip_cross_promo") private var skipCrossPromo = false
    @AppStorage("skip_product_mention") private var skipProductMention = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Playback") {
                    Toggle("Auto-Skip Ads", isOn: $autoSkipAds)
                    Text("Identify and skip ads using Groq AI Pipeline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Picker("Detection Tier", selection: Binding(
                        get: { SettingsManager.shared.adDetectionTier },
                        set: { SettingsManager.shared.adDetectionTier = $0 }
                    )) {
                        ForEach(AdDetectionTier.allCases) { tier in
                            Text(tier.rawValue).tag(tier)
                        }
                    }
                    Text(SettingsManager.shared.adDetectionTier.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if autoSkipAds {
                    Section {
                        Toggle(isOn: $skipPaidAds) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Paid Ads")
                                Text("Sponsors, promo codes, \"brought to you by\"")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Toggle(isOn: $skipSelfPromo) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Self-Promotion")
                                Text("Patreon, merch, newsletter, premium")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Toggle(isOn: $skipCrossPromo) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cross-Promotion")
                                Text("Other podcasts, network shows")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Toggle(isOn: $skipProductMention) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Product Mentions")
                                Text("Organic brand mentions (not ads)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Skip These Types")
                    } footer: {
                        Text("Choose which promotional content to skip. Paid ads are skipped by default.")
                    }
                }
                
                Section("Downloads") {
                    Toggle("Auto-Download New Episodes", isOn: $autoDownloadNewest)
                    if autoDownloadNewest {
                        Picker("Keep Downloads", selection: $downloadCount) {
                            Text("1 Episode").tag(1)
                            Text("2 Episodes").tag(2)
                            Text("3 Episodes").tag(3)
                        }
                    }
                    Button("Clear All Downloads", role: .destructive) {
                        // Action
                    }
                }
                
                Section("Appearance") {
                    // Accent Color settings or others
                    Text("App Version 1.0 (iOS 26)")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

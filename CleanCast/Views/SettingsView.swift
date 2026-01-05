import SwiftUI

struct SettingsView: View {
    @AppStorage("autoSkipAds") private var autoSkipAds = true
    @AppStorage("autoDownloadNewest") private var autoDownloadNewest = false
    @AppStorage("downloadCount") private var downloadCount = 3
    @State private var debugModeEnabled = SettingsManager.shared.debugModeEnabled
    @State private var downloadOnSave = SettingsManager.shared.downloadOnSave
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Ads") {
                    NavigationLink(destination: AdSkippingSettingsView()) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Ad Skipping")
                                    .font(.headline)
                                Text("Configure auto-skip and ad types")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
                    
                    Toggle("Download When Saving", isOn: $downloadOnSave)
                        .onChange(of: downloadOnSave) { _, newValue in
                            SettingsManager.shared.downloadOnSave = newValue
                            // Logic to download skipped episodes if needed
                        }
                    
                    Button("Clear All Downloads", role: .destructive) {
                        // Action
                    }
                }
                
                Section("General") {
                    Button("Sync Library") {
                        // Action
                    }
                    .disabled(true)
                    
                    Button("Add Account") {
                        // Action
                    }
                    .disabled(true)
                }
                
                Section("Advanced") {
                    Toggle("Debug Mode", isOn: $debugModeEnabled)
                        .onChange(of: debugModeEnabled) { _, newValue in
                            SettingsManager.shared.debugModeEnabled = newValue
                        }
                    Text("Enables advanced features like Transcript view details and logging.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

struct AdSkippingSettingsView: View {
    @AppStorage("autoSkipAds") private var autoSkipAds = true
    
    // Ad type skip preferences
    @AppStorage("skip_paid_ads") private var skipPaidAds = true
    @AppStorage("skip_self_promo") private var skipSelfPromo = false
    @AppStorage("skip_cross_promo") private var skipCrossPromo = false
    @AppStorage("skip_product_mention") private var skipProductMention = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Auto-Skip Ads", isOn: $autoSkipAds)
                Text("Identify and skips")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Ad Detection") {
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
        }
        .navigationTitle("Skip Ads")
    }
}

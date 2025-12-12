import SwiftUI

struct SettingsView: View {
    @AppStorage("autoSkipAds") private var autoSkipAds = true
    @AppStorage("autoDownloadNewest") private var autoDownloadNewest = false
    @AppStorage("downloadCount") private var downloadCount = 3
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Playback") {
                    Toggle("Auto-Skip Ads", isOn: $autoSkipAds)
                    Text("Identify and skip ads using Groq AI Pipeline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section("Downloads") {
                    Toggle("Auto-Download New Episodes", isOn: $autoDownloadNewest)
                    if autoDownloadNewest {
                        Stepper("Keep latest \(downloadCount) episodes", value: $downloadCount, in: 1...10)
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

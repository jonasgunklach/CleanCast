//
//  OnboardingAdSettingsPage.swift
//  CleanCast
//
//  Created by Agency on 06/01.
//

import SwiftUI

struct OnboardingAdSettingsPage: View {
    let nextAction: () -> Void
    var isLastPage: Bool = true
    
    @State private var selectedTier: AdDetectionTier = SettingsManager.shared.adDetectionTier
    @State private var autoDetect: Bool = SettingsManager.shared.autoAdDetectionEnabled
    @State private var showPricingInfo = false
    
    // Ad Type Skip States
    @State private var skipPaid: Bool = SettingsManager.shared.skipPaidAds
    @State private var skipSelf: Bool = SettingsManager.shared.skipSelfPromo
    @State private var skipCross: Bool = SettingsManager.shared.skipCrossPromo
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                
                // Hero
                VStack(spacing: 16) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .padding(.top, 40)
                    
                    Text("Ad Detection")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    
                    Text("CleanCast analyzes episodes to skip ads accurately. You can choose from 3 tiers of ad detection. Ad detection involves complex analysis and may occasionally miss or misidentify segments.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                
                // Why is this expensive?
                Button(action: { withAnimation { showPricingInfo.toggle() } }) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Why are there Paid Tiers?")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(showPricingInfo ? 90 : 0))
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                
                if showPricingInfo {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Real-time AI Ad Detection is computationally expensive.")
                            .font(.headline)
                        
                        Text("• **High Precision**: Unlike simple regex, our AI 'listens' to context to distinguish between genuine content and native ads.")
                        Text("• **Server Costs**: Each hour of audio analysis costs significant compute credits.")
                        
                        Text("We offer a Free Tier (Intro only) so everyone can try it, but full analysis requires a subscription to cover the AI and server costs.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // Tier Selection
                VStack(alignment: .leading, spacing: 20) {
                    Text("Select Your Tier")
                        .font(.title3.bold())
                        .padding(.horizontal)
                    
                    VStack(spacing: 16) {
                        TierOption(
                            tier: .free,
                            isSelected: selectedTier == .free,
                            price: "Free",
                            action: { selectedTier = .free }
                        )
                        
                        TierOption(
                            tier: .streaming,
                            isSelected: selectedTier == .streaming,
                            price: "$3.99/mo",
                            action: { selectedTier = .streaming }
                        )
                        
                        TierOption(
                            tier: .downloads,
                            isSelected: selectedTier == .downloads,
                            price: "$5.99/mo",
                            action: { selectedTier = .downloads }
                        )
                    }
                    .padding(.horizontal)
                }
                
                // Fine Tuning
                VStack(alignment: .leading, spacing: 16) {
                    Text("Fine Tuning")
                        .font(.title3.bold())
                        .padding(.horizontal)
                    
                    VStack(spacing: 0) {
                        ToggleRow(title: "Enable Ad Skipping", isOn: $autoDetect, icon: "bolt.fill", color: .yellow)
                        
                        /*if autoDetect {
                            Divider().padding(.leading, 50)
                            
                            ToggleRow(title: "Skip Paid Sponsors", isOn: $skipPaid, icon: "dollarsign.circle.fill", color: .green)
                            Divider().padding(.leading, 50)
                            
                            ToggleRow(title: "Skip Self-Promo", isOn: $skipSelf, icon: "person.wave.2.fill", color: .purple)
                            Divider().padding(.leading, 50)
                            
                            ToggleRow(title: "Skip Cross-Promo", isOn: $skipCross, icon: "arrow.triangle.2.circlepath", color: .blue)
                        }*/
                    }
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)
                }
                
                Spacer(minLength: 120) // Space for bottom button
            }
        }
        .onChange(of: selectedTier) { _, newValue in SettingsManager.shared.adDetectionTier = newValue }
        .onChange(of: autoDetect) { _, newValue in SettingsManager.shared.autoAdDetectionEnabled = newValue }
        .onChange(of: skipPaid) { _, newValue in SettingsManager.shared.skipPaidAds = newValue }
        .onChange(of: skipSelf) { _, newValue in SettingsManager.shared.skipSelfPromo = newValue }
        .onChange(of: skipCross) { _, newValue in SettingsManager.shared.skipCrossPromo = newValue }
    }
}

struct TierOption: View {
    let tier: AdDetectionTier
    let isSelected: Bool
    let price: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                // Radio Circle
                Circle()
                    .strokeBorder(isSelected ? Color.blue : Color.secondary.opacity(0.5), lineWidth: 2)
                    .background(Circle().fill(isSelected ? Color.blue : Color.clear).padding(4))
                    .frame(width: 24, height: 24)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(tier.rawValue)
                            .font(.headline)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                        Spacer()
                        Text(price)
                            .font(.subheadline.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isSelected ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                            .foregroundStyle(isSelected ? .blue : .secondary)
                    }
                    
                    Text(tier.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    
                    if tier != .free {
                        Text("Try 1 week free, then auto-renews.")
                            .font(.caption2.bold())
                            .foregroundStyle(.blue)
                            .padding(.top, 2)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color(uiColor: .secondarySystemBackground) : Color(uiColor: .tertiarySystemGroupedBackground))
                    .shadow(color: isSelected ? .black.opacity(0.05) : .clear, radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 30)
            
            Text(title)
                .font(.body)
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(color)
        }
        .padding()
    }
}

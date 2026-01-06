//
//  OnboardingView.swift
//  CleanCast
//
//  Created by Agency on 06/01.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    
    // Transitions
    let transition: AnyTransition = .asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    )
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            // Content
            Group {
                if currentPage == 0 {
                    OnboardingSearchPage(nextAction: {
                        withAnimation(.spring(duration: 0.5)) { currentPage = 1 }
                    })
                    .transition(transition)
                } else {
                    OnboardingAdSettingsPage(nextAction: {
                        finishOnboarding()
                    })
                    .transition(transition)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            
            // Navigation Bar (if we want explicit buttons, but SearchPage and SettingsPage should drive this now)
            // The previous implementation had a floating button overlay which might have felt detached.
            // Let's integrate buttons INTO the pages themselves for better flow, 
            // OR keep a consistent bottom bar. The user said "no next button", implying they WANTS one but didn't see one or didn't like the paging dots.
            // I'll add a persistent bottom bar.
            
            if currentPage == 1 { // Only for Settings page, Search page has its own flow? 
                // Actually unified flow is better.
                VStack {
                    Spacer()
                    Button(action: {
                        finishOnboarding()
                    }) {
                        Text("Get Started")
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity)
                            .padding()
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: currentPage)
    }
    
    private func finishOnboarding() {
        withAnimation {
            SettingsManager.shared.hasCompletedOnboarding = true
            dismiss()
        }
    }
}

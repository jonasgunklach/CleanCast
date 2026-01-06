//
//  CleanCastApp.swift
//  CleanCast
//
//  Created by Jonas Gunklach on 11.12.25.
//

import SwiftUI
import SwiftData

@main
struct CleanCastApp: App {
    let persistenceController = PersistenceController.shared
    @State private var audioManager = AudioManager.shared
    @AppStorage("has_completed_onboarding") private var hasCompletedOnboarding: Bool = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(audioManager)
                .environment(DownloadManager.shared)
                .fullScreenCover(isPresented: Binding(
                    get: { !hasCompletedOnboarding },
                    set: { _ in }
                )) {
                    OnboardingView()
                }
        }
        .modelContainer(persistenceController.container)
    }
}

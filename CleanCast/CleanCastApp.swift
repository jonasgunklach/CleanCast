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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(audioManager)
                .environment(DownloadManager.shared)
        }
        .modelContainer(persistenceController.container)
    }
}

//
//  ContentView.swift
//  CleanCast
//
//
//  Created by Jonas Gunklach on 11.12.25.
//

import SwiftUI

struct ContentView: View {
    
    @Environment(AudioManager.self) private var audioManager
    @Environment(\.modelContext) private var modelContext
    @State private var showFullPlayer = false
    @State private var searchText: String = ""
    
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                HomeView()
            }
            
            Tab("Library", systemImage: "square.grid.2x2.fill") {
                LibraryView()
            }
            
            Tab("Settings", systemImage: "gear") {
                SettingsView()
            }
            
            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                SearchView(searchText: $searchText)
                    .searchable(text: $searchText, prompt: "Search for podcasts...")
            }
        }
        .id("MainTabs")
        // Mini player accessory
        .tabViewBottomAccessory {
            MiniPlayerView()
                .opacity(showFullPlayer ? 0 : 1)
                .onTapGesture {
                    if audioManager.currentEpisode != nil {
                        showFullPlayer = true
                    }
                }
        }
        .sheet(isPresented: $showFullPlayer) {
            FullPlayerView()
        }
        .tint(currentAccentColor)
        .accentColor(currentAccentColor)
        .onAppear {
            audioManager.restoreSession(context: modelContext)
        }
    }
    
    private var currentAccentColor: Color {
        // Attempt to extract accent from current episode's podcast
        // This requires 'artworkColors' to be accessible or stored on Podcast.
        // We have 'accentColorHex' in Podcast model. We should use it.
        // Or if we implemented dynamic extraction on PodcastDetail without saving to model, we rely on the View.
        // BUT the user asked for "playing episode" accent. `ArtworkColorExtractor` runs in DetailView.
        // Does Podcast model have the color? 
        // We need to verify if we save colors to Podcast. 
        // In PodcastDetailView.extractArtworkColors, we had a comment `// podcast.backgroundColorHex = ...` but commented out.
        // We MUST save it to model to use it globally.
        // For now, I'll default to blue unless I see a way to get it.
        // Wait, the user wants it. I should update PodcastDetail to SAVE the color.
        
        if let hex = audioManager.currentEpisode?.podcast?.accentColorHex {
             return ColorManager.shared.color(from: hex)
        }
        return .blue
    }
}

#Preview {
    ContentView()
}

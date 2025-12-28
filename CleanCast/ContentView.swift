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
        ZStack {
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
            
            .tabBarMinimizeBehavior(.onScrollDown)
            
            // Mini player accessory
            .tabViewBottomAccessory {
                MiniPlayerView()
                    //.opacity(showFullPlayer ? 0 : 1)
                    //.animation(.easeIn(duration: 0.2), value: showFullPlayer)
                    .onTapGesture {
                        if audioManager.currentEpisode != nil {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showFullPlayer = true
                            }
                        }
                    }
            }
            .tint(currentAccentColor)
            .accentColor(currentAccentColor)
            
            // Full Player Overlay
            if showFullPlayer {
                FullPlayerView(showFullPlayer: $showFullPlayer)
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
            }
        }
        .onAppear {
            audioManager.restoreSession(context: modelContext)
        }
    }
    
    private var currentAccentColor: Color {
        
        if let hex = audioManager.currentEpisode?.podcast?.accentColorHex {
             return ColorManager.shared.color(from: hex)
        }
        return .blue
    }
}

#Preview {
    ContentView()
}

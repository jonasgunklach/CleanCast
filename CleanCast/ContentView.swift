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
                .ignoresSafeArea(edges: .all)
                .presentationDragIndicator(.hidden)
        }
        .tint(currentAccentColor)
        .accentColor(currentAccentColor)
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

//
//  OnboardingSearchPage.swift
//  CleanCast
//
//  Created by Agency on 06/01.
//

import SwiftUI
import SwiftData

struct OnboardingSearchPage: View {
    let nextAction: () -> Void
    @State private var searchText = ""
    @State private var results: [iTunesSearchResult] = []
    @State private var pinnedItems: [iTunesSearchResult] = [] // State for "Top" section
    @State private var isSearching = false
    @Environment(\.modelContext) private var modelContext
    @Query private var existingPodcasts: [Podcast]
    
    // Grid Layout
    let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 20, alignment: .top)
    ]
    
    // Combined list: Pinned items + Search Results (filtered)
    private var displayItems: [iTunesSearchResult] {
        // Filter search results to exclude anything currently in pinnedItems (by feedUrl or Title)
        let filteredResults = results.filter { result in
            !pinnedItems.contains { pinned in
                pinned.feedUrl == result.feedUrl || pinned.collectionName == result.collectionName
            }
        }
        return pinnedItems + filteredResults
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                
                // Fixed Header
                VStack(spacing: 16) {
                    Text("Add Your Favorites")
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search podcasts...", text: $searchText)
                            .submitLabel(.search)
                            .onSubmit {
                                performSearch()
                            }
                        if isSearching {
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .padding(.top, 20)
                .padding(.bottom, 20)
                .background(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 5, y: 5)
                .zIndex(1)
                
                // Content
            ScrollView {
                // If nothing to display and no search text, show "Start typing"
                // If nothing to display but we have search text (and not loading), show "No results"
                if displayItems.isEmpty {
                    if searchText.isEmpty {
                        VStack(spacing: 24) {
                            Spacer(minLength: 60)
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            
                            Text("Start typing to search Apple Podcasts")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 50)
                    } else if !isSearching {
                         ContentUnavailableView.search(text: searchText)
                            .padding(.top, 40)
                    }
                } else {
                    // Show Items (Selected + Results)
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(displayItems) { result in
                            PodcastGridItem(result: result, isAdded: isAdded(result)) {
                                toggleSubscription(for: result)
                            }
                        }
                    }
                    .padding(16)
                    // Add padding at bottom to avoid floating button obscuring content
                    .padding(.bottom, 120)
                }
            }    // Dismiss keyboard on scroll
                .scrollDismissesKeyboard(.immediately)
            }
            
            // Action Button Overlay
            VStack {
                Spacer()
                Button(action: nextAction) {
                    HStack {
                        Text(existingPodcasts.count > 0 ? "Next (\(existingPodcasts.count) added)" : "Skip for now")
                            .font(.headline.bold())
                        if existingPodcasts.count > 0 {
                            Image(systemName: "arrow.right")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .glassEffect(
                        .regular.interactive(),
                        in: .rect(cornerRadius: 16)
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            if newValue.isEmpty {
                results = []
                isSearching = false
                updatePinnedItems(resort: true) // Resort when clearing
            } else {
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    if !Task.isCancelled && searchText == newValue {
                        performSearch()
                    }
                }
            }
        }
        .onChange(of: existingPodcasts) { _, _ in
            // Only prune deselected items, DO NOT resort (add new ones) immediately
            updatePinnedItems(resort: false)
        }
        .onAppear {
            updatePinnedItems(resort: true)
        }
    }
    
    private func updatePinnedItems(resort: Bool) {
        if resort {
            // Full refresh: Everything in existingPodcasts goes to pinnedItems
            pinnedItems = existingPodcasts.map { podcast in
                iTunesSearchResult(
                    collectionId: podcast.feedUrl.hashValue,
                    collectionName: podcast.title,
                    artistName: podcast.author,
                    artworkUrl600: podcast.imageURL?.absoluteString,
                    feedUrl: podcast.feedUrl
                )
            }
        } else {
            // Prune only: Remove items from pinnedItems that are no longer in existingPodcasts
            // We assume name/url match is unique enough
            pinnedItems.removeAll { pinned in
                !existingPodcasts.contains { existing in
                    existing.feedUrl == pinned.feedUrl || existing.title == pinned.collectionName
                }
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        isSearching = true
        // Refresh pinned items on new search to include any newly added ones at the top
        updatePinnedItems(resort: true)
        
        Task {
            do {
                results = try await PodcastService.shared.searchPodcasts(term: searchText)
            } catch {
                print("Search error: \(error)")
            }
            isSearching = false
        }
    }
    
    // MARK: - Logic
    
    private func isAdded(_ result: iTunesSearchResult) -> Bool {
        return existingPodcasts.contains { $0.title == result.collectionName || $0.feedUrl == result.feedUrl }
    }
    
    private func toggleSubscription(for result: iTunesSearchResult) {
        if let existing = existingPodcasts.first(where: { $0.title == result.collectionName }) {
            modelContext.delete(existing)
        } else {
            let newPodcast = Podcast(
                title: result.collectionName,
                author: result.artistName,
                feedUrl: result.feedUrl ?? "",
                imageURL: URL(string: result.artworkUrl600 ?? "")
            )
            modelContext.insert(newPodcast)
        }
    }
}

struct PodcastGridItem: View {
    let result: iTunesSearchResult
    let isAdded: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading) {
                ZStack(alignment: .topTrailing) {
                    // Artwork
                    AsyncImage(url: URL(string: result.artworkUrl600 ?? "")) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                    .frame(width: 160, height: 160)
                    .cornerRadius(12)
                    .clipped()
                    
                    // Checkmark Overlay
                    if isAdded {
                        ZStack {
                            Circle()
                                .fill(Color.blue)
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                        .frame(width: 28, height: 28)
                        .padding(8)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                
                Text(result.collectionName)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                
                Text(result.artistName)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

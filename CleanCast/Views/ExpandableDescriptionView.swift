import SwiftUI

struct ExpandableDescriptionView: View {
    let text: String
    let artworkColors: ArtworkColors
    
    @State private var isExpanded = false
    @State private var isTruncated = false
    
    private let lineLimit = 3
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : lineLimit)
                .background(
                    Text(text)
                        .font(.system(size: 15, design: .rounded))
                        .lineLimit(lineLimit)
                        .background(GeometryReader { geo in
                            Color.clear.onAppear {
                                // Simple approximate check: if height of full text > height of limited text?
                                // Actually better to use a ViewModifier or overlay approach to detect truncation.
                                // For simplicity/robustness without heavy layout calculation: always show 'more' if text is long enough.
                                isTruncated = text.count > 150 
                            }
                        })
                        .hidden()
                )
            
            if isTruncated {
                Button {
                    withAnimation(.easeInOut) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "Show Less" : "Show More")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [artworkColors.primary, artworkColors.secondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
        }
    }
}

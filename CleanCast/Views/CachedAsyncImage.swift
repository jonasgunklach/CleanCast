import SwiftUI
import Combine

class ImageLoader: ObservableObject {
    @Published var image: UIImage?
    
    private let url: URL
    private var cancellable: AnyCancellable?
    
    // Shared memory cache
    private static let cache = NSCache<NSURL, UIImage>()
    
    init(url: URL) {
        self.url = url
    }
    
    deinit {
        cancellable?.cancel()
    }
    
    func load() {
        // Check memory cache first
        if let cachedImage = Self.cache.object(forKey: url as NSURL) {
            self.image = cachedImage
            return
        }
        
        // Load from network (URLSession handles disk caching)
        cancellable = URLSession.shared.dataTaskPublisher(for: url)
            .map { UIImage(data: $0.data) }
            .replaceError(with: nil)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                guard let self = self, let image = image else { return }
                Self.cache.setObject(image, forKey: self.url as NSURL)
                self.image = image
            }
    }
    
    func cancel() {
        cancellable?.cancel()
    }
}

struct CachedAsyncImage<Content>: View where Content: View {
    @StateObject private var loader: ImageLoader
    private let content: (AsyncImagePhase) -> Content
    
    init(url: URL, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        _loader = StateObject(wrappedValue: ImageLoader(url: url))
        self.content = content
    }
    
    var body: some View {
        Group {
            if let image = loader.image {
                content(.success(Image(uiImage: image)))
            } else {
                content(.empty)
            }
        }
        .onAppear {
            loader.load()
        }
        .id(loader.image == nil ? "loading" : "loaded") // Stable once loaded
    }
}

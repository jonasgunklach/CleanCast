import Foundation

struct iTunesSearchResult: Codable, Identifiable {
    var id: Int { collectionId }
    let collectionId: Int
    let collectionName: String
    let artistName: String
    let artworkUrl600: String?
    let feedUrl: String?
}

struct ITunesResponse: Codable {
    let results: [iTunesSearchResult]
}

enum PodcastServiceError: Error {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case noData
}

class PodcastService {
    static let shared = PodcastService()
    
    func searchPodcasts(term: String) async throws -> [iTunesSearchResult] {
        guard let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encodedTerm)&entity=podcast&limit=25") else {
            throw PodcastServiceError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        do {
            let response = try JSONDecoder().decode(ITunesResponse.self, from: data)
            return response.results
        } catch {
            throw PodcastServiceError.decodingError(error)
        }
    }
    
    // Basic XML Parser wrapper for RSS would go here.
    // For now, returning mock episodes to allow UI development without external XML logic.
    func fetchEpisodes(feedUrl: String) async throws -> [Episode] {
        guard let url = URL(string: feedUrl) else {
            throw PodcastServiceError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let parser = FeedParser(data: data)
        return parser.parse()
    }
}

class FeedParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var episodes: [Episode] = []
    
    // Current parsing state
    private var currentElement: String = ""
    private var currentTitle: String = ""
    private var currentDescription: String = ""
    private var currentPubDate: String = ""
    private var currentUrl: String = ""
    private var currentDuration: String = ""
    private var isInsideItem = false
    
    init(data: Data) {
        self.parser = XMLParser(data: data)
        super.init()
        self.parser.delegate = self
    }
    
    func parse() -> [Episode] {
        parser.parse()
        return episodes
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if elementName == "item" {
            isInsideItem = true
            currentTitle = ""
            currentDescription = ""
            currentPubDate = ""
            currentUrl = ""
            currentDuration = ""
        }
        
        if isInsideItem {
            if elementName == "enclosure" {
                if let url = attributeDict["url"] {
                    currentUrl = url
                }
            }
            if elementName == "itunes:duration" {
                // Sometimes duration is in content, sometimes here if empty? 
                // Mostly simple element but handled in foundCharacters or endElement usually if text based.
                // Actually itunes:duration is often element text, but valid to check attributes just in case.
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideItem else { return }
        
        // Clean whitespace
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        // Note: XMLParser can call foundCharacters multiple times for one element, so we must append if we want robustness,
        // but for simple strings appending without a flexible buffer can be tricky if we don't reset per element start.
        // A robust parser keeps a buffer. For simplicity here assuming mostly one-shot or handled by `didEndElement`.
        // Actually, we SHOULD append.
        
        switch currentElement {
        case "title": currentTitle += string
        case "description", "itunes:summary": currentDescription += string // Append raw
        case "pubDate": currentPubDate += string
        case "itunes:duration": currentDuration += string
        default: break
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            // Create Episode
            let duration = parseDuration(currentDuration.trimmingCharacters(in: .whitespacesAndNewlines))
            let date = parseDate(currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines))
            
            // Clean up description (strip HTML tags often in descriptions)
            let cleanDesc = currentDescription.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            let episode = Episode(
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                desc: cleanDesc,
                url: currentUrl,
                duration: duration,
                releaseDate: date
            )
            episodes.append(episode)
            isInsideItem = false
        }
        
        if elementName == "title" || elementName == "description" || elementName == "pubDate" || elementName == "itunes:duration" || elementName == "itunes:summary" {
            // We could reset currentElement here but done in didStart
        }
    }
    
    // Helpers
    private func parseDuration(_ string: String) -> TimeInterval {
        let parts = string.components(separatedBy: ":")
        if parts.count == 3 {
             let h = Double(parts[0]) ?? 0
             let m = Double(parts[1]) ?? 0
             let s = Double(parts[2]) ?? 0
             return h * 3600 + m * 60 + s
        } else if parts.count == 2 {
             let m = Double(parts[0]) ?? 0
             let s = Double(parts[1]) ?? 0
             return m * 60 + s
        } else {
            return Double(string) ?? 0
        }
    }
    
    private func parseDate(_ string: String) -> Date {
        // Try standard RFC 2822 (most common for podcasts)
        let rfc2822 = DateFormatter()
        rfc2822.locale = Locale(identifier: "en_US_POSIX")
        rfc2822.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let date = rfc2822.date(from: string) { return date }
        
        // Try without seconds
        rfc2822.dateFormat = "EEE, dd MMM yyyy HH:mm Z"
        if let date = rfc2822.date(from: string) { return date }
        
        // Try ISO 8601
        let iso8601 = ISO8601DateFormatter()
        if let date = iso8601.date(from: string) { return date }
        
        // Try common variation
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.dateFormat = "dd MMM yyyy HH:mm:ss Z"
        if let date = fallback.date(from: string) { return date }
        
        print("Failed to parse date: \(string)")
        return Date(timeIntervalSince1970: 0) // Return old date instead of 'now' to avoid sorting top
    }
}

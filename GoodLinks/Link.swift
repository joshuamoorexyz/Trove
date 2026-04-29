import Foundation

struct Folder: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var colorName: String = "blue"

    static func == (lhs: Folder, rhs: Folder) -> Bool { lhs.id == rhs.id }
}

extension Folder: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct Highlight: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String
    var note: String = ""
    var createdAt: Date = Date()
}

struct SmartSearchCriteria: Codable {
    var keywords: String?
    var unreadOnly: Bool?
    var favoritesOnly: Bool?
    var archivedOnly: Bool?
    var tag: String?
    var folderName: String?
    var recentDays: Int?
    var minWords: Int?
    var maxWords: Int?
}

enum Priority: Int, Codable, CaseIterable, Identifiable {
    case low = 0, normal = 1, high = 2
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }
}

struct Link: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var url: URL
    var title: String
    var excerpt: String
    var thumbnailURLString: String?
    var domain: String
    var tags: [String] = []
    var folderID: UUID? = nil
    var isRead: Bool = false
    var isFavorite: Bool = false
    var isArchived: Bool = false
    var savedAt: Date = Date()
    var notes: String = ""
    var wordCount: Int = 0
    var readingProgress: Double = 0
    var highlights: [Highlight] = []
    var summary: String = ""
    var priority: Priority? = nil
    var embedding: [Double]? = nil
    var pdfLocalPath: String? = nil   // non-nil → this link is a locally stored PDF

    var thumbnailURL: URL? { thumbnailURLString.flatMap { URL(string: $0) } }

    var isPDF: Bool { pdfLocalPath != nil }

    var resolvedPDFURL: URL? {
        guard let path = pdfLocalPath else { return nil }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Trove/PDFs").appendingPathComponent(path)
    }

    var readingMinutes: Int? {
        guard wordCount > 0 else { return nil }
        return max(1, Int((Double(wordCount) / 220.0).rounded()))
    }

    init(url: URL, title: String = "", excerpt: String = "", thumbnailURLString: String? = nil, wordCount: Int = 0) {
        self.url = url
        self.title = title.isEmpty ? (url.host ?? url.absoluteString) : title
        self.excerpt = excerpt
        self.thumbnailURLString = thumbnailURLString
        self.domain = url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
        self.wordCount = wordCount
    }

    var timeAgo: String {
        let diff = Date().timeIntervalSince(savedAt)
        switch diff {
        case ..<60:     return "just now"
        case ..<3600:   return "\(Int(diff / 60))m ago"
        case ..<86400:  return "\(Int(diff / 3600))h ago"
        case ..<604800: return "\(Int(diff / 86400))d ago"
        default:
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .none
            return f.string(from: savedAt)
        }
    }
}

import Foundation
import NaturalLanguage
import PDFKit

enum SidebarFilter: Hashable {
    case all, unread, favorites, archived
    case tag(String)
    case folder(Folder)

    var title: String {
        switch self {
        case .all:            return "All Links"
        case .unread:         return "Unread"
        case .favorites:      return "Stars"
        case .archived:       return "Archive"
        case .tag(let t):     return t
        case .folder(let f):  return f.name
        }
    }
}

enum SortOption: String, CaseIterable, Identifiable {
    case newest, oldest, title, domain, longest, shortest, priority
    var id: String { rawValue }
    var label: String {
        switch self {
        case .newest:   return "Newest First"
        case .oldest:   return "Oldest First"
        case .title:    return "Title (A–Z)"
        case .domain:   return "Domain (A–Z)"
        case .longest:  return "Longest Read"
        case .shortest: return "Shortest Read"
        case .priority: return "Priority"
        }
    }
}

@MainActor
class LinkStore: ObservableObject {
    @Published var links: [Link] = []
    @Published var folders: [Folder] = []
    @Published var isFetching = false

    private let linksKey   = "goodlinks_v1"
    private let foldersKey = "trove_folders_v1"

    init() { load() }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(links) {
            UserDefaults.standard.set(data, forKey: linksKey)
        }
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: foldersKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: linksKey),
           let decoded = try? JSONDecoder().decode([Link].self, from: data) {
            links = decoded
        }
        if let data = UserDefaults.standard.data(forKey: foldersKey),
           let decoded = try? JSONDecoder().decode([Folder].self, from: data) {
            folders = decoded
        }
    }

    // MARK: - Link CRUD

    func addLink(urlString: String, folderID: UUID? = nil) async {
        var raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.hasPrefix("http") { raw = "https://" + raw }
        guard let url = URL(string: raw) else { return }
        guard !links.contains(where: { $0.url == url }) else { return }

        isFetching = true
        let meta = await MetadataFetcher.fetch(for: url)
        isFetching = false

        var link = Link(url: url,
                        title: meta.title,
                        excerpt: meta.excerpt,
                        thumbnailURLString: meta.thumbnailURLString,
                        wordCount: meta.wordCount)
        link.folderID = folderID
        links.insert(link, at: 0)
        save()

        // Compute embedding for "related links" feature (cheap, on-device).
        Task { [weak self] in await self?.computeAndStoreEmbedding(for: link) }

        // Kick off background AI processing if any auto-flag is enabled
        let d = UserDefaults.standard
        let autoTag      = d.bool(forKey: "autoTagOnSave")
        let autoSummary  = d.bool(forKey: "autoSummarizeOnSave")
        let autoPriority = d.bool(forKey: "autoPriorityOnSave")
        if (autoTag || autoSummary || autoPriority) && AppleIntelligence.isAvailable {
            let captured = link
            Task { [weak self] in
                await self?.processWithAI(link: captured, doTags: autoTag, doSummary: autoSummary, doPriority: autoPriority)
            }
        }
    }

    func processWithAI(link: Link, doTags: Bool, doSummary: Bool, doPriority: Bool) async {
        guard AppleIntelligence.isAvailable else { return }
        let body = await MetadataFetcher.fetchArticleText(for: link.url)
        let text: String = (body != nil && body!.count > 80)
            ? "\(link.title)\n\n\(body!)"
            : "\(link.title)\n\n\(link.excerpt)"

        if doSummary {
            if let s = await AppleIntelligence.summarize(text: text), !s.isEmpty {
                self.setSummary(s, for: link)
            }
        }
        if doTags {
            let suggested = await AppleIntelligence.suggestTags(text: text)
            for tag in suggested { self.addTag(tag, to: link) }
        }
        if doPriority {
            if let p = await AppleIntelligence.suggestPriority(text: text) {
                self.setPriority(p, for: link)
            }
        }
    }

    func delete(_ link: Link) {
        links.removeAll { $0.id == link.id }
        save()
    }

    func delete(at offsets: IndexSet, in filtered: [Link]) {
        let ids = offsets.map { filtered[$0].id }
        links.removeAll { ids.contains($0.id) }
        save()
    }

    func toggleRead(_ link: Link)     { mutate(link) { $0.isRead.toggle() } }
    func toggleFavorite(_ link: Link) { mutate(link) { $0.isFavorite.toggle() } }
    func toggleArchive(_ link: Link)  { mutate(link) { $0.isArchived.toggle() } }

    func archiveAllRead() {
        for i in links.indices where links[i].isRead && !links[i].isArchived {
            links[i].isArchived = true
        }
        save()
    }

    func addTag(_ tag: String, to link: Link) {
        let t = tag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return }
        mutate(link) { if !$0.tags.contains(t) { $0.tags.append(t) } }
    }

    func removeTag(_ tag: String, from link: Link) {
        mutate(link) { $0.tags.removeAll { $0 == tag } }
    }

    func updateTitle(_ title: String, for link: Link) { mutate(link) { $0.title = title } }
    func updateNotes(_ notes: String, for link: Link) { mutate(link) { $0.notes = notes } }
    func setFolder(_ folderID: UUID?, for link: Link) { mutate(link) { $0.folderID = folderID } }

    func setReadingProgress(_ progress: Double, for link: Link) {
        let clamped = max(0, min(1, progress))
        mutate(link) { $0.readingProgress = clamped }
    }

    func setWordCount(_ count: Int, for link: Link) {
        guard count > 0 else { return }
        mutate(link) { $0.wordCount = count }
    }

    func setSummary(_ summary: String, for link: Link) {
        mutate(link) { $0.summary = summary }
    }

    func setPriority(_ priority: Priority?, for link: Link) {
        mutate(link) { $0.priority = priority }
    }

    func addHighlight(text: String, to link: Link) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(link) { $0.highlights.append(Highlight(text: trimmed)) }
    }

    func removeHighlight(_ highlightID: UUID, from link: Link) {
        mutate(link) { $0.highlights.removeAll { $0.id == highlightID } }
    }

    func updateHighlightNote(_ highlightID: UUID, note: String, for link: Link) {
        mutate(link) {
            if let idx = $0.highlights.firstIndex(where: { $0.id == highlightID }) {
                $0.highlights[idx].note = note
            }
        }
    }

    private func mutate(_ link: Link, _ transform: (inout Link) -> Void) {
        guard let idx = links.firstIndex(where: { $0.id == link.id }) else { return }
        transform(&links[idx])
        save()
    }

    // MARK: - Folder CRUD

    func addFolder(name: String, colorName: String = "blue") {
        folders.append(Folder(name: name, colorName: colorName))
        save()
    }

    func deleteFolder(_ folder: Folder) {
        folders.removeAll { $0.id == folder.id }
        for i in links.indices where links[i].folderID == folder.id {
            links[i].folderID = nil
        }
        save()
    }

    func renameFolder(_ folder: Folder, name: String) {
        guard let idx = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[idx].name = name
        save()
    }

    func setFolderColor(_ folder: Folder, colorName: String) {
        guard let idx = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[idx].colorName = colorName
        save()
    }

    // MARK: - Queries

    var allTags: [String] {
        Array(Set(links.flatMap(\.tags))).sorted()
    }

    func filteredLinks(filter: SidebarFilter, search: String, sort: SortOption = .newest) -> [Link] {
        var result = links
        switch filter {
        case .all:             result = result.filter { !$0.isArchived }
        case .unread:          result = result.filter { !$0.isRead && !$0.isArchived }
        case .favorites:       result = result.filter { $0.isFavorite && !$0.isArchived }
        case .archived:        result = result.filter { $0.isArchived }
        case .tag(let t):      result = result.filter { $0.tags.contains(t) && !$0.isArchived }
        case .folder(let f):   result = result.filter { $0.folderID == f.id && !$0.isArchived }
        }

        if !search.isEmpty {
            let q = search.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q) ||
                $0.domain.lowercased().contains(q) ||
                $0.excerpt.lowercased().contains(q) ||
                $0.notes.lowercased().contains(q) ||
                $0.tags.contains(where: { $0.contains(q) }) ||
                $0.highlights.contains(where: { $0.text.lowercased().contains(q) })
            }
        }

        switch sort {
        case .newest:   result.sort { $0.savedAt > $1.savedAt }
        case .oldest:   result.sort { $0.savedAt < $1.savedAt }
        case .title:    result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .domain:   result.sort { $0.domain.localizedCaseInsensitiveCompare($1.domain) == .orderedAscending }
        case .longest:  result.sort { $0.wordCount > $1.wordCount }
        case .shortest: result.sort { ($0.wordCount == 0 ? Int.max : $0.wordCount) < ($1.wordCount == 0 ? Int.max : $1.wordCount) }
        case .priority:
            // High → Normal → no-priority → Low. Then by date (newest first) within each group.
            result.sort {
                let a = $0.priority?.rawValue ?? -1
                let b = $1.priority?.rawValue ?? -1
                if a != b {
                    if a == Priority.low.rawValue && b != Priority.low.rawValue { return false }
                    if b == Priority.low.rawValue && a != Priority.low.rawValue { return true }
                    return a > b
                }
                return $0.savedAt > $1.savedAt
            }
        }

        return result
    }

    func count(for filter: SidebarFilter) -> Int {
        filteredLinks(filter: filter, search: "").count
    }

    func current(_ link: Link) -> Link? {
        links.first { $0.id == link.id }
    }

    // MARK: - Embeddings & related links

    func computeAndStoreEmbedding(for link: Link) async {
        let text = "\(link.title)\n\(link.excerpt)"
        let trimmed = String(text.prefix(1000)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let model = NLEmbedding.sentenceEmbedding(for: .english),
              let vector = model.vector(for: trimmed)
        else { return }
        mutate(link) { $0.embedding = vector }
    }

    func relatedLinks(to link: Link, limit: Int = 5) -> [Link] {
        guard let target = link.embedding, !target.isEmpty else { return [] }
        var scored: [(Link, Double)] = []
        for other in links {
            guard other.id != link.id, !other.isArchived,
                  let emb = other.embedding, !emb.isEmpty else { continue }
            scored.append((other, Self.cosineSimilarity(target, emb)))
        }
        scored.sort { $0.1 > $1.1 }
        return scored.prefix(limit).map { $0.0 }
    }

    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denom = (na * nb).squareRoot()
        return denom == 0 ? 0 : dot / denom
    }

    // MARK: - Smart search

    func applySmartSearch(_ c: SmartSearchCriteria) -> [Link] {
        var result = links
        if c.archivedOnly == true { result = result.filter { $0.isArchived } }
        else { result = result.filter { !$0.isArchived } }
        if c.unreadOnly    == true { result = result.filter { !$0.isRead } }
        if c.favoritesOnly == true { result = result.filter { $0.isFavorite } }
        if let t = c.tag?.lowercased() {
            result = result.filter { $0.tags.contains(t) }
        }
        if let fname = c.folderName?.lowercased(),
           let folder = folders.first(where: { $0.name.lowercased() == fname }) {
            result = result.filter { $0.folderID == folder.id }
        }
        if let days = c.recentDays {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            result = result.filter { $0.savedAt >= cutoff }
        }
        if let m = c.minWords { result = result.filter { $0.wordCount >= m } }
        if let m = c.maxWords { result = result.filter { $0.wordCount <= m } }
        if let kw = c.keywords?.lowercased(), !kw.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(kw)   ||
                $0.excerpt.lowercased().contains(kw) ||
                $0.summary.lowercased().contains(kw) ||
                $0.notes.lowercased().contains(kw)   ||
                $0.tags.contains(where: { $0.contains(kw) })
            }
        }
        return result.sorted { $0.savedAt > $1.savedAt }
    }

    // MARK: - Export / Import

    func exportJSON() -> Data? {
        struct Export: Codable { var links: [Link]; var folders: [Folder]; var exportedAt: Date }
        let payload = Export(links: links, folders: folders, exportedAt: Date())
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try? enc.encode(payload)
    }

    /// Merges an exported Trove JSON file into the library. Returns counts of newly added items.
    @discardableResult
    func importJSON(_ data: Data) -> (links: Int, folders: Int) {
        struct Export: Codable { var links: [Link]; var folders: [Folder]; var exportedAt: Date? }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let payload = try? dec.decode(Export.self, from: data) else { return (0, 0) }

        var newFolders = 0
        for folder in payload.folders where !folders.contains(where: { $0.id == folder.id }) {
            folders.append(folder)
            newFolders += 1
        }
        var newLinks = 0
        for link in payload.links.reversed() where !links.contains(where: { $0.id == link.id }) {
            links.insert(link, at: 0)
            newLinks += 1
        }
        if newLinks > 0 || newFolders > 0 { save() }
        return (newLinks, newFolders)
    }

    // MARK: - PDF Import

    /// Copies a PDF into app support and registers it as a Link. Returns the new link on success.
    func importPDF(from sourceURL: URL, folderID: UUID? = nil) async -> Link? {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let pdfsDir = appSupport.appendingPathComponent("Trove/PDFs")
        try? fm.createDirectory(at: pdfsDir, withIntermediateDirectories: true)

        let filename = UUID().uuidString + ".pdf"
        let destURL = pdfsDir.appendingPathComponent(filename)
        do {
            try fm.copyItem(at: sourceURL, to: destURL)
        } catch { return nil }

        // Extract title and word count from the PDF document
        var title = sourceURL.deletingPathExtension().lastPathComponent
        var wordCount = 0
        if let doc = PDFDocument(url: destURL) {
            if let t = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, !t.isEmpty {
                title = t
            }
            var allText = ""
            for i in 0..<doc.pageCount { allText += doc.page(at: i)?.string ?? "" }
            wordCount = allText.split(whereSeparator: \.isWhitespace).filter { !$0.isEmpty }.count
        }

        var link = Link(url: destURL, title: title, wordCount: wordCount)
        link.pdfLocalPath = filename
        link.folderID = folderID
        links.insert(link, at: 0)
        save()
        return link
    }
}

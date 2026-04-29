import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct PageMetadata {
    var title: String
    var excerpt: String
    var thumbnailURLString: String?
    var wordCount: Int = 0
}

enum MetadataFetcher {
    static func fetch(for url: URL) async -> PageMetadata {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else {
            return PageMetadata(title: url.host ?? "", excerpt: "", thumbnailURLString: nil)
        }

        let title   = ogMeta(html, "og:title")       ?? titleTag(html)          ?? url.host ?? ""
        let excerpt = ogMeta(html, "og:description") ?? metaName(html, "description") ?? ""
        var thumb   = ogMeta(html, "og:image")

        if let t = thumb {
            if t.hasPrefix("//") {
                thumb = "https:" + t
            } else if t.hasPrefix("/") {
                let base = "\(url.scheme ?? "https")://\(url.host ?? "")"
                thumb = base + t
            }
        }

        return PageMetadata(
            title: title.htmlDecoded.trimmingCharacters(in: .whitespacesAndNewlines),
            excerpt: String(excerpt.htmlDecoded.prefix(300)).trimmingCharacters(in: .whitespacesAndNewlines),
            thumbnailURLString: thumb,
            wordCount: estimateWordCount(html)
        )
    }

    private static func ogMeta(_ html: String, _ property: String) -> String? {
        extractMeta(html, key: "property", value: property)
    }

    private static func metaName(_ html: String, _ name: String) -> String? {
        extractMeta(html, key: "name", value: name)
    }

    private static func extractMeta(_ html: String, key: String, value: String) -> String? {
        for pattern in [
            "<meta[^>]+\(key)=[\"']?\(value)[\"']?[^>]+content=[\"']([^\"'<>]*)[\"']",
            "<meta[^>]+content=[\"']([^\"'<>]*)[\"'][^>]+\(key)=[\"']?\(value)[\"']?"
        ] {
            if let m = html.firstRegexGroup(pattern: pattern) { return m }
        }
        return nil
    }

    private static func titleTag(_ html: String) -> String? {
        html.firstRegexGroup(pattern: "<title[^>]*>([^<]{1,300})</title>")
    }

    /// Fetches the page and returns plain article text (best-effort: prefers
    /// <article> / <main>, falls back to <body>). Used by AI features.
    static func fetchArticleText(for url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return nil }

        let body = html.firstRegexGroup(pattern: "<article[^>]*>([\\s\\S]*?)</article>")
            ?? html.firstRegexGroup(pattern: "<main[^>]*>([\\s\\S]*?)</main>")
            ?? html.firstRegexGroup(pattern: "<body[^>]*>([\\s\\S]*?)</body>")
            ?? html

        var s = body
        for pattern in [
            "<script[\\s\\S]*?</script>",
            "<style[\\s\\S]*?</style>",
            "<noscript[\\s\\S]*?</noscript>",
            "<!--[\\s\\S]*?-->",
            "<[^>]+>"
        ] {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
            }
        }
        // Collapse whitespace
        s = s.htmlDecoded
        if let regex = try? NSRegularExpression(pattern: "\\s+", options: []) {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // Rough word-count estimator: strip script/style/HTML tags, count whitespace-delimited tokens.
    private static func estimateWordCount(_ html: String) -> Int {
        var s = html
        for pattern in [
            "<script[\\s\\S]*?</script>",
            "<style[\\s\\S]*?</style>",
            "<noscript[\\s\\S]*?</noscript>",
            "<!--[\\s\\S]*?-->",
            "<[^>]+>"
        ] {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
            }
        }
        let words = s.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        return words.count
    }
}

// MARK: - Apple Intelligence (FoundationModels framework, macOS 26+)

/// Wraps the on-device Apple Intelligence language model. On systems without
/// FoundationModels (or where the model isn't downloaded), all calls return
/// nil/empty so the UI can hide the AI section gracefully.
enum AppleIntelligence {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default: return false
            }
        }
        #endif
        return false
    }

    static func summarize(text: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), isAvailable {
            do {
                let session = LanguageModelSession(
                    instructions: "You write concise, clear summaries of articles. Be specific and informative, not generic."
                )
                let prompt = """
                Summarize this article in 2 to 3 sentences. Focus on the key points and findings.

                \(String(text.prefix(8000)))
                """
                let response = try await session.respond(to: prompt)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    static func suggestTags(text: String) async -> [String] {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), isAvailable {
            do {
                let session = LanguageModelSession(
                    instructions: "You suggest short topical tags for articles."
                )
                let prompt = """
                Suggest 3 to 5 short single-word topical tags for this article.
                Respond with ONLY the tags as a comma-separated list, all lowercase, no other text.
                Example: javascript, performance, optimization

                \(String(text.prefix(4000)))
                """
                let response = try await session.respond(to: prompt)
                let raw = response.content.lowercased()
                let parts: [String] = raw.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let cleaned: [String] = parts.filter { tag in
                    !tag.isEmpty && tag.count <= 25 && !tag.contains(" ") && !tag.contains("\n")
                }
                return Array(cleaned.prefix(5))
            } catch {
                return []
            }
        }
        #endif
        return []
    }

    static func translate(text: String, toLanguage language: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), isAvailable {
            do {
                let session = LanguageModelSession(
                    instructions: "You are a faithful, fluent translator. Preserve meaning, tone, and paragraph structure."
                )
                let prompt = """
                Translate the following text to \(language). Preserve paragraph breaks (one blank line between paragraphs).
                Output ONLY the translation, no preface or explanation.

                \(String(text.prefix(8000)))
                """
                let response = try await session.respond(to: prompt)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    static func studyNotes(title: String, highlights: [String]) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), isAvailable {
            do {
                var listLines: [String] = []
                for (i, h) in highlights.enumerated() {
                    listLines.append("\(i + 1). \(h)")
                }
                let listText = listLines.joined(separator: "\n")
                let session = LanguageModelSession(
                    instructions: "You turn raw highlighted quotes into clear, organized study notes."
                )
                let prompt = """
                Article: \(title)

                Highlighted excerpts:
                \(listText)

                Synthesize these into organized study notes using markdown (headings, bullets).
                Be concise. Group related ideas. Don't just repeat the quotes.
                """
                let response = try await session.respond(to: prompt)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    static func parseSearch(query: String) async -> SmartSearchCriteria? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), isAvailable {
            do {
                let session = LanguageModelSession(
                    instructions: "Extract structured search criteria from natural-language queries. Output JSON only."
                )
                let prompt = """
                Extract criteria from this query: "\(query)"

                Output a JSON object with these optional fields (omit unspecified ones):
                - "keywords": string (specific search terms / topic words)
                - "unreadOnly": boolean
                - "favoritesOnly": boolean
                - "archivedOnly": boolean
                - "tag": string (a single tag name)
                - "folderName": string
                - "recentDays": integer (look at links saved within last N days)
                - "minWords": integer
                - "maxWords": integer

                Output ONLY the JSON object, nothing else.
                """
                let response = try await session.respond(to: prompt)
                let content = response.content
                guard let start = content.firstIndex(of: "{"),
                      let end = content.lastIndex(of: "}") else { return nil }
                let jsonStr = String(content[start...end])
                guard let data = jsonStr.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(SmartSearchCriteria.self, from: data)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    static func suggestPriority(text: String) async -> Priority? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), isAvailable {
            do {
                let session = LanguageModelSession(
                    instructions: "You assess how time-sensitive or important an article is to read."
                )
                let prompt = """
                Rate the reading priority of this article. Consider time-sensitivity, importance, and depth.
                Respond with ONLY one word: high, normal, or low.

                \(String(text.prefix(2000)))
                """
                let response = try await session.respond(to: prompt)
                let word = response.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if word.contains("high") { return .high }
                if word.contains("low")  { return .low }
                return .normal
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}

extension String {
    func firstRegexGroup(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: self)
        else { return nil }
        return String(self[range])
    }

    var htmlDecoded: String {
        var s = self
        [("&amp;","&"),("&lt;","<"),("&gt;",">"),("&quot;","\""),
         ("&#39;","'"),("&apos;","'"),("&nbsp;"," "),
         ("&#8217;","'"),("&#8216;","'"),("&#8220;","\""),("&#8221;","\""),
         ("&#8230;","…"),("&#8211;","–"),("&#8212;","—")].forEach {
            s = s.replacingOccurrences(of: $0.0, with: $0.1)
        }
        return s
    }
}

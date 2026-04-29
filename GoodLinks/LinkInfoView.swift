import SwiftUI
import PDFKit
#if canImport(FoundationModels)
import FoundationModels
#endif

struct LinkInfoView: View {
    @ObservedObject var store: LinkStore
    let link: Link
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var notes: String
    @State private var newTag: String = ""

    @State private var isSummarizing = false
    @State private var isSuggestingTags = false
    @State private var isAssessingPriority = false
    @State private var suggestedTags: [String] = []
    @State private var showingStudyNotes = false

    init(store: LinkStore, link: Link) {
        self.store = store
        self.link = link
        _title = State(initialValue: link.title)
        _notes = State(initialValue: link.notes)
    }

    private var current: Link { store.current(link) ?? link }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Link Info")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    store.updateTitle(title, for: link)
                    store.updateNotes(notes, for: link)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Title", systemImage: "textformat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Title", text: $title, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3)
                    }

                    // URL
                    VStack(alignment: .leading, spacing: 6) {
                        Label("URL", systemImage: "link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(link.url.absoluteString)
                            .font(.system(size: 12))
                            .foregroundStyle(.blue)
                            .textSelection(.enabled)
                            .lineLimit(3)
                    }

                    // Saved date
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Saved", systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(link.savedAt, style: .date)
                            .font(.system(size: 13))
                    }

                    // Folder
                    if !store.folders.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Folder", systemImage: "folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Menu {
                                Button {
                                    store.setFolder(nil, for: link)
                                } label: {
                                    if current.folderID == nil {
                                        Label("None", systemImage: "checkmark")
                                    } else {
                                        Text("None")
                                    }
                                }
                                Divider()
                                ForEach(store.folders) { folder in
                                    Button {
                                        store.setFolder(folder.id, for: link)
                                    } label: {
                                        if current.folderID == folder.id {
                                            Label(folder.name, systemImage: "checkmark")
                                        } else {
                                            Text(folder.name)
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    if let fid = current.folderID,
                                       let folder = store.folders.first(where: { $0.id == fid }) {
                                        Image(systemName: "folder.fill")
                                            .foregroundStyle(folder.swiftUIColor)
                                        Text(folder.name)
                                    } else {
                                        Text("None")
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }

                    // Tags
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Tags", systemImage: "tag")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: 6) {
                            ForEach(current.tags, id: \.self) { tag in
                                HStack(spacing: 3) {
                                    Text(tag)
                                        .font(.system(size: 12, weight: .medium))
                                    Button {
                                        store.removeTag(tag, from: link)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.12))
                                .foregroundStyle(.purple)
                                .clipShape(Capsule())
                            }
                        }

                        HStack {
                            TextField("Add tag", text: $newTag)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .onSubmit { addTag() }
                            Button("Add") { addTag() }
                                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    // Apple Intelligence
                    if AppleIntelligence.isAvailable {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Apple Intelligence", systemImage: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !current.summary.isEmpty {
                                Text(current.summary)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.indigo.opacity(0.10))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }

                            HStack(spacing: 8) {
                                aiButton(
                                    title: current.summary.isEmpty ? "Summarize" : "Re-summarize",
                                    icon: "text.alignleft",
                                    busy: isSummarizing
                                ) { Task { await runSummarize() } }

                                aiButton(
                                    title: "Tags",
                                    icon: "tag",
                                    busy: isSuggestingTags
                                ) { Task { await runSuggestTags() } }

                                aiButton(
                                    title: "Priority",
                                    icon: "exclamationmark.bubble",
                                    busy: isAssessingPriority
                                ) { Task { await runSuggestPriority() } }
                            }

                            if !suggestedTags.isEmpty {
                                Text("Suggested:")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                FlowLayout(spacing: 6) {
                                    ForEach(suggestedTags, id: \.self) { tag in
                                        Button {
                                            store.addTag(tag, to: link)
                                            suggestedTags.removeAll { $0 == tag }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "plus")
                                                    .font(.system(size: 9, weight: .bold))
                                                Text(tag)
                                                    .font(.system(size: 12, weight: .medium))
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.indigo.opacity(0.15))
                                            .foregroundStyle(.indigo)
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    // Priority (manual)
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Priority", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: Binding(
                            get: { current.priority ?? .normal },
                            set: { store.setPriority($0, for: link) }
                        )) {
                            ForEach(Priority.allCases) { p in
                                Text(p.label).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    // Related links
                    let related = store.relatedLinks(to: current, limit: 4)
                    if !related.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Related", systemImage: "link.circle")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(related) { other in
                                Button {
                                    NSWorkspace.shared.open(other.url)
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(other.title)
                                                .font(.system(size: 12, weight: .medium))
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            Text(other.domain)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Highlights
                    if !current.highlights.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Highlights (\(current.highlights.count))", systemImage: "highlighter")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if AppleIntelligence.isAvailable {
                                    Button { showingStudyNotes = true } label: {
                                        Label("Study Notes", systemImage: "sparkles")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.indigo)
                                }
                            }
                            ForEach(current.highlights) { hl in
                                HighlightRow(hl: hl, store: store, link: link)
                            }
                        }
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Notes", systemImage: "note.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $notes)
                            .font(.system(size: 13))
                            .frame(minHeight: 80)
                            .border(Color.secondary.opacity(0.3))
                    }
                }
                .padding()
            }
        }
        .frame(width: 360, height: 600)
        .sheet(isPresented: $showingStudyNotes) {
            StudyNotesSheet(link: current, store: store)
        }
    }

    private func addTag() {
        store.addTag(newTag, to: link)
        newTag = ""
    }

    @ViewBuilder
    private func aiButton(title: String, icon: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if busy {
                    ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                } else {
                    Image(systemName: icon).font(.system(size: 11))
                }
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.indigo.opacity(0.12))
            .foregroundStyle(.indigo)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func aiInputText() async -> String {
        // PDFs: extract text directly from the document
        if current.isPDF, let pdfURL = current.resolvedPDFURL,
           let doc = PDFDocument(url: pdfURL) {
            var allText = ""
            for i in 0..<doc.pageCount {
                allText += doc.page(at: i)?.string ?? ""
                if allText.count > 8000 { break }
            }
            let trimmed = String(allText.prefix(8000)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return "\(current.title)\n\n\(trimmed)" }
            return current.title
        }
        // Web links: fetch article body from the URL
        if let body = await MetadataFetcher.fetchArticleText(for: link.url), body.count > 80 {
            return "\(link.title)\n\n\(body)"
        }
        return "\(link.title)\n\n\(link.excerpt)"
    }

    private func runSummarize() async {
        isSummarizing = true
        defer { isSummarizing = false }
        let text = await aiInputText()
        if let summary = await AppleIntelligence.summarize(text: text), !summary.isEmpty {
            store.setSummary(summary, for: link)
        }
    }

    private func runSuggestTags() async {
        isSuggestingTags = true
        defer { isSuggestingTags = false }
        let text = await aiInputText()
        let tags = await AppleIntelligence.suggestTags(text: text)
        let existing = Set(current.tags)
        suggestedTags = tags.filter { !existing.contains($0) }
    }

    private func runSuggestPriority() async {
        isAssessingPriority = true
        defer { isAssessingPriority = false }
        let text = await aiInputText()
        if let p = await AppleIntelligence.suggestPriority(text: text) {
            store.setPriority(p, for: link)
        }
    }
}

// MARK: - Highlight row with expandable note field

struct HighlightRow: View {
    let hl: Highlight
    @ObservedObject var store: LinkStore
    let link: Link
    @State private var editingNote: String = ""
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(hl.text)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !hl.note.isEmpty && !isExpanded {
                        Text(hl.note)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
                HStack(spacing: 6) {
                    Button {
                        editingNote = hl.note
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "note.text.badge.plus" : "note.text")
                            .font(.system(size: 11))
                            .foregroundStyle(hl.note.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.indigo))
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Close note" : "Add / edit note")

                    Button {
                        store.removeHighlight(hl.id, from: link)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    TextEditor(text: $editingNote)
                        .font(.system(size: 12))
                        .frame(minHeight: 52, maxHeight: 80)
                        .border(Color.secondary.opacity(0.25))
                    HStack {
                        Button("Cancel") {
                            editingNote = hl.note
                            isExpanded = false
                        }
                        .font(.system(size: 11))
                        Spacer()
                        Button("Save") {
                            store.updateHighlightNote(hl.id, note: editingNote, for: link)
                            isExpanded = false
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
        }
        .background(Color.yellow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Study Notes Sheet

struct StudyNotesSheet: View {
    let link: Link
    @ObservedObject var store: LinkStore
    @Environment(\.dismiss) private var dismiss
    @State private var notes = ""
    @State private var isGenerating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Study Notes", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.indigo)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            Divider()

            if isGenerating {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Synthesizing highlights…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if notes.isEmpty {
                ContentUnavailableView {
                    Label("No Notes Yet", systemImage: "note.text")
                } description: {
                    Text("Generate study notes synthesized from your highlights.")
                } actions: {
                    Button("Generate") { Task { await generate() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    Text(.init(notes))  // renders Markdown headings / bullets
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
                Divider()
                HStack {
                    Button { Task { await generate() } } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .disabled(isGenerating)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(notes, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 520)
        .task { await generate() }
    }

    private func generate() async {
        guard !link.highlights.isEmpty else { return }
        isGenerating = true
        defer { isGenerating = false }
        if let result = await AppleIntelligence.studyNotes(
            title: link.title,
            highlights: link.highlights.map(\.text)
        ) {
            notes = result
        }
    }
}

// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

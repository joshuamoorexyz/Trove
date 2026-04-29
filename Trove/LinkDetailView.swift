import SwiftUI

struct LinkDetailView: View {
    @ObservedObject var store: LinkStore
    let link: Link

    @StateObject private var webState = WebViewState()
    @StateObject private var readerState = ReaderState()
    @StateObject private var pdfState = PDFReaderState()
    @State private var isLoading = false
    @State private var currentURL: URL
    @State private var showingInfo = false
    @State private var isReaderMode = false
    @State private var readerTitle = ""
    @State private var readerHTML = ""
    @State private var isExtracting = false

    @AppStorage("readerDarkMode")  private var isDark = false
    @AppStorage("readerFontSize")  private var fontSize: Double = 19
    @AppStorage("readerUseSerif")  private var useSerif: Bool = true

    init(store: LinkStore, link: Link) {
        self.store = store
        self.link = link
        _currentURL = State(initialValue: link.url)
    }

    private var current: Link? { store.current(link) }

    var body: some View {
        Group {
            if let current {
                ZStack(alignment: .top) {
                    if current.isPDF {
                        // PDF viewer
                        if let pdfURL = current.resolvedPDFURL {
                            PDFReaderView(
                                url: pdfURL,
                                isDark: isDark,
                                savedHighlights: current.highlights,
                                state: pdfState,
                                onHighlight: { txt in store.addHighlight(text: txt, to: current) },
                                onWordCount: { n in store.setWordCount(n, for: current) }
                            )
                        } else {
                            ContentUnavailableView("PDF Not Found", systemImage: "doc.fill",
                                description: Text("The PDF file could not be located."))
                        }
                    } else if isReaderMode {
                        ReaderView(
                            title: readerTitle,
                            html: readerHTML,
                            isDark: isDark,
                            fontSize: fontSize,
                            useSerif: useSerif,
                            state: readerState,
                            initialProgress: current.readingProgress,
                            savedHighlights: current.highlights.map(\.text),
                            onProgress: { p in store.setReadingProgress(p, for: current) },
                            onHighlight: { txt in store.addHighlight(text: txt, to: current) },
                            onWordCount: { n in store.setWordCount(n, for: current) }
                        )
                    } else {
                        WebView(
                            url: current.url,
                            isLoading: $isLoading,
                            currentURL: $currentURL,
                            state: webState,
                            isDark: isDark,
                            initialProgress: current.readingProgress,
                            onProgress: { p in store.setReadingProgress(p, for: current) }
                        )
                    }

                    if isLoading && !isReaderMode && !current.isPDF {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(.top, 8)
                    }

                    if isExtracting {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.7)
                            Text("Loading reader…").font(.caption)
                        }
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 8)
                    }
                }
                .toolbar { toolbarItems(current) }
                .sheet(isPresented: $showingInfo) {
                    LinkInfoView(store: store, link: current)
                }
                .onChange(of: link.id) {
                    isReaderMode = false
                    readerTitle = ""
                    readerHTML = ""
                }
            } else {
                ContentUnavailableView("No Link Selected", systemImage: "link",
                    description: Text("Select a link from the list."))
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbarItems(_ link: Link) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { store.toggleRead(link) } label: {
                Image(systemName: link.isRead ? "envelope.badge" : "checkmark.circle")
            }
            .help(link.isRead ? "Mark as Unread" : "Mark as Read")

            Button { store.toggleFavorite(link) } label: {
                Image(systemName: link.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(link.isFavorite ? .yellow : .primary)
            }
            .help(link.isFavorite ? "Remove Star" : "Star")

            Button { store.toggleArchive(link) } label: {
                Image(systemName: link.isArchived ? "tray.and.arrow.up" : "archivebox")
                    .foregroundStyle(link.isArchived ? .orange : .primary)
            }
            .help(link.isArchived ? "Unarchive" : "Archive")

            // Highlight button — works for both reader mode and PDF
            if isReaderMode || link.isPDF {
                Button {
                    if link.isPDF {
                        if let text = pdfState.highlightSelectionAndReturn() {
                            store.addHighlight(text: text, to: link)
                        }
                    } else {
                        readerState.captureSelection()
                    }
                } label: {
                    Image(systemName: "highlighter")
                        .foregroundStyle(.yellow)
                }
                .help("Highlight Selection (⇧⌘H)")
            }

            if !link.isPDF {
                Button { toggleReader() } label: {
                    Image(systemName: isReaderMode ? "doc.plaintext.fill" : "doc.plaintext")
                        .foregroundStyle(isReaderMode ? .orange : .primary)
                }
                .help(isReaderMode ? "Exit Reader Mode" : "Reader Mode")
                .disabled(isExtracting)
            }

            Button { isDark.toggle() } label: {
                Image(systemName: isDark ? "moon.fill" : "moon")
                    .foregroundStyle(isDark ? .indigo : .primary)
            }
            .help(isDark ? "Light Mode" : "Dark Mode")

            // Reader font controls (web reader only)
            if isReaderMode && !link.isPDF {
                Menu {
                    Button("Larger") { fontSize = min(28, fontSize + 1) }
                        .keyboardShortcut("+", modifiers: .command)
                    Button("Smaller") { fontSize = max(13, fontSize - 1) }
                        .keyboardShortcut("-", modifiers: .command)
                    Divider()
                    Button(useSerif ? "Sans-serif" : "Serif") { useSerif.toggle() }
                } label: {
                    Image(systemName: "textformat.size")
                }
                .help("Reader Font")
            }

            if !link.isPDF {
                Button { NSWorkspace.shared.open(currentURL) } label: {
                    Image(systemName: "safari")
                }
                .help("Open in Safari")

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(currentURL.absoluteString, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy URL")
            }

            Button { showingInfo = true } label: {
                Image(systemName: "info.circle")
            }
            .help("Link Info (⌘I)")
            .keyboardShortcut("i", modifiers: .command)
        }
    }

    private func toggleReader() {
        if isReaderMode {
            isReaderMode = false
            return
        }
        isExtracting = true
        webState.extractArticle { title, html in
            self.readerTitle = title
            self.readerHTML  = html
            self.isReaderMode = true
            self.isExtracting = false
        }
    }
}

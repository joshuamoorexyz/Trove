# Trove

> A beautiful, native macOS read-later app with Apple Intelligence, PDF markup, and a built-in reader — built entirely in SwiftUI.

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue?style=flat-square&logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-orange?style=flat-square&logo=swift)
![License MIT](https://img.shields.io/badge/license-MIT-green?style=flat-square)

---

## Features

### Save & Organize
- **Add links** by URL, clipboard paste (⌘L), or drag-and-drop
- **Import PDFs** — research papers, docs, anything — stored locally and fully readable in-app
- **Folders** with custom colors and drag-to-organize support
- **Tags** applied manually or suggested automatically by Apple Intelligence
- **Priority levels** (High / Normal / Low) set manually or assessed by AI
- **Favorites** and **Archive** for easy triage

### Read
- **Built-in web browser** with reading-progress tracking per article
- **Reader Mode** — distraction-free, typographic view with serif/sans toggle and font size control
- **PDF Reader** powered by PDFKit — continuous scroll, dark mode, full text selection
- **Dark mode** across both the web view and PDF reader
- **Reading-time estimates** based on word count

### Highlight & Annotate
- **Text highlighting** in both Reader Mode and PDFs — select any text and tap the yellow ✦ button
- **Highlight notes** — expand any highlight to add a personal annotation inline
- **Persistent highlights** — restored automatically when you reopen an article or PDF

### Apple Intelligence (macOS 26+ with on-device model)
- **Summarize** any article in 2–3 sentences
- **Auto-tag** — suggests 3–5 topical tags from article content
- **Priority assessment** — rates urgency as High / Normal / Low
- **Study Notes** — synthesizes all your highlights into organized Markdown study notes
- **Natural-language search** — type "unread Swift articles from last week" and press Return
- All AI runs **on-device**; nothing is sent to the cloud

### Manage
- **Smart search** across titles, excerpts, notes, tags, and highlights
- **Sort** by newest, oldest, title, domain, reading time, or priority
- **Related links** — semantically similar articles surfaced automatically using NaturalLanguage embeddings
- **Export** your full library as JSON
- **Import** a previously exported JSON file to merge libraries
- **Reading Stats** — overview cards, top-domain bar chart, tag cloud, 8-week activity chart

---

## Screenshots

> _Coming soon — contributions welcome!_

---

## Requirements

| | Minimum |
|---|---|
| macOS | 26.0 (Tahoe) |
| Xcode | 16.0+ |
| Swift | 6.0+ |
| Apple Intelligence | Required for AI features only; all other features work without it |

---

## Building from Source

```bash
git clone https://github.com/joshuamoore/Trove.git
cd Trove
open GoodLinks.xcodeproj
```

Press **⌘R** to run. No third-party dependencies — pure Apple frameworks only.

### Release build & install

```bash
xcodebuild -scheme Trove \
  -project GoodLinks.xcodeproj \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  ONLY_ACTIVE_ARCH=NO

cp -R build/Build/Products/Release/Trove.app /Applications/
```

---

## Architecture

Trove is a single-target SwiftUI app with no third-party dependencies.

```
GoodLinks/
├── GoodLinksApp.swift      # App entry point, menu commands, Settings
├── ContentView.swift       # Root NavigationSplitView, drag-drop, import/export
│
├── Model
│   ├── Link.swift          # Link, Folder, Highlight, Priority, SmartSearchCriteria
│   └── LinkStore.swift     # @MainActor ObservableObject — all CRUD, embeddings, PDF import
│
├── Sidebar
│   └── SidebarView.swift   # Filter list, folder management, tag list
│
├── Link List
│   ├── LinkListView.swift  # Filtered list, sort picker, AI search mode
│   └── LinkRowView.swift   # Row with favicon, progress ring, tags, priority badge
│
├── Detail
│   ├── LinkDetailView.swift    # Toolbar, web/reader/PDF switcher
│   ├── WebView.swift           # WKWebView wrapper with scroll tracking
│   ├── WebViewState.swift      # Article extraction for Reader Mode
│   ├── ReaderView.swift        # Full HTML reader with highlight injection
│   └── PDFReaderView.swift     # PDFKit reader with highlight annotation
│
├── Panels
│   ├── AddLinkView.swift       # URL + PDF import sheet
│   ├── LinkInfoView.swift      # Metadata editor, tags, AI buttons, highlights + notes
│   └── StatsView.swift         # Reading statistics dashboard
│
└── Intelligence
    └── MetadataFetcher.swift   # HTML metadata, article extraction, AppleIntelligence wrappers
```

**Data persistence:** `UserDefaults` (JSON-encoded). PDF files live in `~/Library/Application Support/Trove/PDFs/`.

**Embeddings:** On-device `NLEmbedding.sentenceEmbedding` vectors stored per link; cosine-similarity used for Related Links.

---

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Add Link | ⇧⌘A |
| Add from Clipboard | ⌘L |
| Export Library | ⇧⌘E |
| Import Library | File → Import Library… |
| Link Info | ⌘I |
| Highlight Selection | ⇧⌘H |
| Reader font larger | ⌘+ |
| Reader font smaller | ⌘- |

---

## Contributing

Pull requests are welcome. For major changes, open an issue first to discuss what you'd like to change.

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Push and open a PR

Please keep the zero-dependency philosophy — only Apple frameworks.

---

## License

MIT — see [LICENSE](LICENSE) for details.

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: LinkStore
    @State private var sidebarFilter: SidebarFilter = .all
    @State private var selectedLink: Link?
    @State private var showingAdd = false
    @State private var clipboardError: String?
    @State private var showingClipboardError = false
    @State private var showingStats = false
    @State private var importedLinkCount = 0
    @State private var showingImportResult = false
    @State private var isDroppingPDF = false

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store, selection: $sidebarFilter)
                .navigationSplitViewColumnWidth(min: 160, ideal: 210, max: 260)
        } content: {
            LinkListView(store: store, filter: sidebarFilter, selectedLink: $selectedLink)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        } detail: {
            if let link = selectedLink {
                LinkDetailView(store: store, link: link)
            } else {
                ContentUnavailableView {
                    Label("No Link Selected", systemImage: "link")
                } description: {
                    Text("Choose a link from the list, or add a new one.")
                } actions: {
                    Button("Add Link") { showingAdd = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
                .help("Add Link or PDF (⇧⌘A)")
            }
            ToolbarItem(placement: .automatic) {
                Button { showingStats = true } label: {
                    Image(systemName: "chart.bar.fill")
                }
                .help("Reading Stats")
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddLinkView(store: store)
        }
        .sheet(isPresented: $showingStats) {
            StatsView(store: store)
        }
        .alert("Clipboard", isPresented: $showingClipboardError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(clipboardError ?? "")
        }
        .alert("Import Complete", isPresented: $showingImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Imported \(importedLinkCount) new link\(importedLinkCount == 1 ? "" : "s").")
        }
        .onDrop(of: [UTType.pdf, UTType.fileURL], isTargeted: $isDroppingPDF) { providers in
            for provider in providers {
                _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, _ in
                    guard let url else { return }
                    // Synchronously copy to temp so the file is available after the callback returns
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + ".pdf")
                    try? FileManager.default.copyItem(at: url, to: tmp)
                    Task { @MainActor in
                        await store.importPDF(from: tmp)
                        try? FileManager.default.removeItem(at: tmp)
                    }
                }
            }
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: .addLink)) { _ in
            showingAdd = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickAddFromClipboard)) { _ in
            quickAddFromClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportLibrary)) { _ in
            exportLibrary()
        }
        .onReceive(NotificationCenter.default.publisher(for: .importLibrary)) { _ in
            importLibrary()
        }
        .onReceive(NotificationCenter.default.publisher(for: .archiveAllRead)) { _ in
            store.archiveAllRead()
        }
    }

    private func quickAddFromClipboard() {
        guard let raw = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            clipboardError = "Clipboard is empty."
            showingClipboardError = true
            return
        }
        let candidate = raw.hasPrefix("http") ? raw : "https://\(raw)"
        guard URL(string: candidate)?.host != nil else {
            clipboardError = "Clipboard does not contain a valid URL."
            showingClipboardError = true
            return
        }
        Task { await store.addLink(urlString: candidate) }
    }

    private func exportLibrary() {
        guard let data = store.exportJSON() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "trove-export-\(dateStamp()).json"
        panel.title = "Export Trove Library"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func importLibrary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.title = "Import Trove Library"
        panel.message = "Select a previously exported Trove JSON file."
        panel.prompt = "Import"
        guard panel.runModal() == .OK,
              let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        let result = store.importJSON(data)
        importedLinkCount = result.links
        showingImportResult = true
    }

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

extension Notification.Name {
    static let addLink                = Notification.Name("addLink")
    static let quickAddFromClipboard  = Notification.Name("quickAddFromClipboard")
    static let exportLibrary          = Notification.Name("exportLibrary")
    static let importLibrary          = Notification.Name("importLibrary")
    static let archiveAllRead         = Notification.Name("archiveAllRead")
}

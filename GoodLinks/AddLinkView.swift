import SwiftUI
import UniformTypeIdentifiers

struct AddLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: LinkStore

    @State private var urlText = ""
    @State private var selectedFolderID: UUID? = nil
    @State private var selectedPDF: URL? = nil
    @State private var isImportingPDF = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header
            HStack(spacing: 8) {
                Image(systemName: selectedPDF != nil ? "doc.fill" : "link.badge.plus")
                    .font(.title2)
                    .foregroundStyle(selectedPDF != nil ? .orange : .blue)
                Text(selectedPDF != nil ? "Import PDF" : "Add Link")
                    .font(.headline)
            }

            // URL field
            if selectedPDF == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("URL").font(.caption).foregroundStyle(.secondary)
                    TextField("https://example.com", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onSubmit { add() }
                }

                // Divider with "or"
                HStack {
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
                    Text("or").font(.caption).foregroundStyle(.secondary).fixedSize()
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
                }

                // PDF import button
                Button {
                    choosePDF()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.badge.plus")
                        Text("Import a PDF File…")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }

            // PDF selected state
            if let pdf = selectedPDF {
                HStack(spacing: 10) {
                    Image(systemName: "doc.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pdf.deletingPathExtension().lastPathComponent)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(2)
                        Text(pdf.lastPathComponent)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        selectedPDF = nil
                        focused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove selected PDF")
                }
                .padding(12)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Folder picker
            if !store.folders.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Folder").font(.caption).foregroundStyle(.secondary)
                    Menu {
                        Button("None") { selectedFolderID = nil }
                        Divider()
                        ForEach(store.folders) { folder in
                            Button(folder.name) { selectedFolderID = folder.id }
                        }
                    } label: {
                        HStack {
                            if let fid = selectedFolderID,
                               let folder = store.folders.first(where: { $0.id == fid }) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(folder.swiftUIColor)
                                Text(folder.name)
                            } else {
                                Text("None").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            // Progress
            if store.isFetching || isImportingPDF {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text(isImportingPDF ? "Importing PDF…" : "Fetching link info…")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button(selectedPDF != nil ? "Import PDF" : "Add Link") { add() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .disabled(addDisabled)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { focused = true }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            if selectedPDF == nil,
               let clip = NSPasteboard.general.string(forType: .string),
               clip.hasPrefix("http"), urlText.isEmpty {
                urlText = clip
            }
        }
    }

    private var addDisabled: Bool {
        if isImportingPDF || store.isFetching { return true }
        if let _ = selectedPDF { return false }
        return urlText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func choosePDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.allowsMultipleSelection = false
        panel.title = "Choose a PDF"
        panel.prompt = "Import"
        if panel.runModal() == .OK { selectedPDF = panel.url }
    }

    private func add() {
        let folderID = selectedFolderID
        if let pdfURL = selectedPDF {
            isImportingPDF = true
            Task {
                await store.importPDF(from: pdfURL, folderID: folderID)
                isImportingPDF = false
                dismiss()
            }
        } else {
            let raw = urlText.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { return }
            Task { await store.addLink(urlString: raw, folderID: folderID) }
            dismiss()
        }
    }
}

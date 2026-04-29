import SwiftUI
import UniformTypeIdentifiers

struct AddLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: LinkStore

    @State private var urlText = ""
    @State private var selectedFolderID: UUID? = nil
    @State private var selectedPDF: URL? = nil
    @State private var isImportingPDF = false
    @State private var mode: AddMode = .url
    @FocusState private var focused: Bool

    enum AddMode { case url, pdf }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header + mode picker
            HStack {
                Image(systemName: mode == .pdf ? "doc.fill" : "link.badge.plus")
                    .font(.title2)
                    .foregroundStyle(mode == .pdf ? .orange : .blue)
                Text(mode == .pdf ? "Import PDF" : "Add Link")
                    .font(.headline)
                Spacer()
                Picker("", selection: $mode) {
                    Label("URL", systemImage: "link").tag(AddMode.url)
                    Label("PDF", systemImage: "doc.fill").tag(AddMode.pdf)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .onChange(of: mode) { urlText = ""; selectedPDF = nil }
            }

            if mode == .url {
                VStack(alignment: .leading, spacing: 6) {
                    Text("URL").font(.caption).foregroundStyle(.secondary)
                    TextField("https://example.com", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onSubmit { add() }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PDF File").font(.caption).foregroundStyle(.secondary)
                    if let pdf = selectedPDF {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading) {
                                Text(pdf.deletingPathExtension().lastPathComponent)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                Text(pdf.lastPathComponent)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { selectedPDF = nil } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Button {
                            choosePDF()
                        } label: {
                            Label("Choose PDF File…", systemImage: "doc.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
            }

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

            if store.isFetching || isImportingPDF {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text(isImportingPDF ? "Importing PDF…" : "Fetching link info…")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button(mode == .pdf ? "Import PDF" : "Add Link") { add() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .disabled(addDisabled)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { focused = true }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            if mode == .url, let clip = NSPasteboard.general.string(forType: .string),
               clip.hasPrefix("http"), urlText.isEmpty {
                urlText = clip
            }
        }
    }

    private var addDisabled: Bool {
        if isImportingPDF || store.isFetching { return true }
        if mode == .pdf { return selectedPDF == nil }
        return urlText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func choosePDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.allowsMultipleSelection = false
        panel.title = "Choose a PDF"
        if panel.runModal() == .OK { selectedPDF = panel.url }
    }

    private func add() {
        let folderID = selectedFolderID
        if mode == .pdf, let pdfURL = selectedPDF {
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

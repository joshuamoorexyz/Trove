import SwiftUI

// MARK: - Folder color helper (view-layer only, keeps model clean)

extension Folder {
    var swiftUIColor: Color {
        switch colorName {
        case "green":  return .green
        case "orange": return .orange
        case "red":    return .red
        case "purple": return .purple
        case "teal":   return .teal
        case "yellow": return .yellow
        case "pink":   return .pink
        case "indigo": return .indigo
        default:       return .blue
        }
    }

    static let colorOptions: [(name: String, color: Color)] = [
        ("blue",   .blue),
        ("green",  .green),
        ("orange", .orange),
        ("red",    .red),
        ("purple", .purple),
        ("teal",   .teal),
        ("yellow", .yellow),
        ("pink",   .pink),
        ("indigo", .indigo),
    ]
}

// MARK: - SidebarView

struct SidebarView: View {
    @ObservedObject var store: LinkStore
    @Binding var selection: SidebarFilter

    @State private var isAddingFolder  = false
    @State private var newFolderName   = ""
    @State private var folderToRename: Folder?
    @State private var renameText      = ""

    private var nextFolderColor: String {
        let colors = Folder.colorOptions.map(\.name)
        return colors[store.folders.count % colors.count]
    }

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                SidebarRow(icon: "books.vertical.fill", label: "All Links", color: .blue,
                           count: store.count(for: .all))
                    .tag(SidebarFilter.all)

                SidebarRow(icon: "circle.fill", label: "Unread", color: .blue,
                           count: store.count(for: .unread))
                    .tag(SidebarFilter.unread)

                SidebarRow(icon: "star.fill", label: "Stars", color: .yellow,
                           count: store.count(for: .favorites))
                    .tag(SidebarFilter.favorites)

                SidebarRow(icon: "archivebox.fill", label: "Archive", color: .orange,
                           count: store.count(for: .archived))
                    .tag(SidebarFilter.archived)
            }

            Section {
                ForEach(store.folders) { folder in
                    SidebarRow(icon: "folder.fill", label: folder.name,
                               color: folder.swiftUIColor,
                               count: store.count(for: .folder(folder)))
                        .tag(SidebarFilter.folder(folder))
                        .contextMenu {
                            Button("Rename…") {
                                folderToRename = folder
                                renameText = folder.name
                            }
                            Menu("Color") {
                                ForEach(Folder.colorOptions, id: \.name) { opt in
                                    Button {
                                        store.setFolderColor(folder, colorName: opt.name)
                                    } label: {
                                        Label(opt.name.capitalized,
                                              systemImage: folder.colorName == opt.name
                                                ? "checkmark.circle.fill" : "circle.fill")
                                    }
                                }
                            }
                            Divider()
                            Button("Delete Folder", role: .destructive) {
                                if case .folder(let f) = selection, f.id == folder.id {
                                    selection = .all
                                }
                                store.deleteFolder(folder)
                            }
                        }
                }

                Button {
                    isAddingFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            } header: {
                Text("Folders")
            }

            if !store.allTags.isEmpty {
                Section("Tags") {
                    ForEach(store.allTags, id: \.self) { tag in
                        SidebarRow(icon: "tag.fill", label: tag, color: .purple,
                                   count: store.count(for: .tag(tag)))
                            .tag(SidebarFilter.tag(tag))
                            .contextMenu {
                                Button("Delete Tag", role: .destructive) {
                                    deleteTag(tag)
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Trove")
        // New folder alert
        .alert("New Folder", isPresented: $isAddingFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                let name = newFolderName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    store.addFolder(name: name, colorName: nextFolderColor)
                }
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        // Rename folder alert
        .alert("Rename Folder", isPresented: Binding(
            get: { folderToRename != nil },
            set: { if !$0 { folderToRename = nil } }
        )) {
            TextField("Folder name", text: $renameText)
            Button("Rename") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, let folder = folderToRename {
                    store.renameFolder(folder, name: name)
                }
                folderToRename = nil
            }
            Button("Cancel", role: .cancel) { folderToRename = nil }
        }
    }

    private func deleteTag(_ tag: String) {
        for link in store.links where link.tags.contains(tag) {
            store.removeTag(tag, from: link)
        }
    }
}

struct SidebarRow: View {
    let icon: String
    let label: String
    let color: Color
    let count: Int

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(label)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

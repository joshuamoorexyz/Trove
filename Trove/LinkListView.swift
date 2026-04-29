import SwiftUI

struct LinkListView: View {
    @ObservedObject var store: LinkStore
    let filter: SidebarFilter
    @Binding var selectedLink: Link?
    @State private var searchText = ""
    @AppStorage("listSortOption") private var sortRaw: String = SortOption.newest.rawValue

    // AI search
    @State private var aiSearchMode = false
    @State private var aiResults: [Link]? = nil
    @State private var isAISearching = false

    private var sort: SortOption {
        SortOption(rawValue: sortRaw) ?? .newest
    }

    private var filtered: [Link] {
        store.filteredLinks(filter: filter, search: aiSearchMode ? "" : searchText, sort: sort)
    }

    private var displayedLinks: [Link] {
        aiResults ?? filtered
    }

    var body: some View {
        Group {
            if displayedLinks.isEmpty {
                emptyState
            } else {
                List(selection: $selectedLink) {
                    // AI search result banner
                    if aiResults != nil {
                        HStack(spacing: 6) {
                            Image(systemName: isAISearching ? "ellipsis" : "sparkles")
                                .foregroundStyle(.indigo)
                                .font(.system(size: 11))
                            Text(isAISearching ? "Searching…" : "AI results for \"\(searchText)\"")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear") {
                                aiResults = nil
                                searchText = ""
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(.indigo)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.indigo.opacity(0.06))
                    }

                    ForEach(displayedLinks) { link in
                        LinkRowView(link: link)
                            .tag(link)
                            .contextMenu { contextMenu(for: link) }
                    }
                    .onDelete { offsets in
                        store.delete(at: offsets, in: displayedLinks)
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(
            text: $searchText,
            placement: .sidebar,
            prompt: aiSearchMode ? "Ask AI: find unread Swift articles…" : "Search links, notes, highlights"
        )
        .onSubmit(of: .search) {
            guard aiSearchMode, !searchText.isEmpty else { return }
            Task { await runAISearch() }
        }
        .onChange(of: searchText) {
            if searchText.isEmpty { aiResults = nil }
        }
        .navigationTitle(filter.title)
        .navigationSubtitle(subtitleText)
        .toolbar {
            if AppleIntelligence.isAvailable {
                ToolbarItem(placement: .automatic) {
                    Button {
                        aiSearchMode.toggle()
                        if !aiSearchMode {
                            aiResults = nil
                            searchText = ""
                        }
                    } label: {
                        Image(systemName: aiSearchMode ? "sparkles.rectangle.stack.fill" : "sparkles")
                            .foregroundStyle(aiSearchMode ? .indigo : .primary)
                    }
                    .help(aiSearchMode ? "Exit AI Search" : "AI Natural Language Search")
                }
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    Picker("Sort", selection: $sortRaw) {
                        ForEach(SortOption.allCases) { opt in
                            Text(opt.label).tag(opt.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .help("Sort")
            }
        }
    }

    private func runAISearch() async {
        guard !searchText.isEmpty else { return }
        isAISearching = true
        defer { isAISearching = false }
        if let criteria = await AppleIntelligence.parseSearch(query: searchText) {
            aiResults = store.applySmartSearch(criteria)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if searchText.isEmpty {
            ContentUnavailableView {
                Label("No Links", systemImage: "link")
            } description: {
                Text("Add links using the + button.")
            }
        } else if aiSearchMode && aiResults != nil {
            ContentUnavailableView {
                Label("No AI Results", systemImage: "sparkles")
            } description: {
                Text("No links matched \"\(searchText)\".")
            }
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private var subtitleText: String {
        let n = displayedLinks.count
        return n == 1 ? "1 link" : "\(n) links"
    }

    @ViewBuilder
    private func contextMenu(for link: Link) -> some View {
        Button(link.isRead ? "Mark as Unread" : "Mark as Read") {
            store.toggleRead(link)
        }
        Button(link.isFavorite ? "Remove Star" : "Add Star") {
            store.toggleFavorite(link)
        }
        Button(link.isArchived ? "Unarchive" : "Archive") {
            if !link.isArchived, selectedLink?.id == link.id { selectedLink = nil }
            store.toggleArchive(link)
        }

        if !store.folders.isEmpty {
            Divider()
            Menu("Move to Folder") {
                Button("None") { store.setFolder(nil, for: link) }
                Divider()
                ForEach(store.folders) { folder in
                    Button(folder.name) { store.setFolder(folder.id, for: link) }
                }
            }
        }

        Divider()
        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
        }
        Button("Open in Browser") {
            NSWorkspace.shared.open(link.url)
        }
        Divider()
        Button("Delete", role: .destructive) {
            if selectedLink?.id == link.id { selectedLink = nil }
            store.delete(link)
        }
    }
}

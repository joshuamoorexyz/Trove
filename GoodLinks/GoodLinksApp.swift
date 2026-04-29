import SwiftUI

@main
struct TroveApp: App {
    @StateObject private var store = LinkStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .defaultSize(width: 1200, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Link…") {
                    NotificationCenter.default.post(name: .addLink, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button("Add Link from Clipboard") {
                    NotificationCenter.default.post(name: .quickAddFromClipboard, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command])

                Divider()

                Button("Export Library…") {
                    NotificationCenter.default.post(name: .exportLibrary, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Import Library…") {
                    NotificationCenter.default.post(name: .importLibrary, object: nil)
                }

                Divider()

                Button("Archive All Read") {
                    NotificationCenter.default.post(name: .archiveAllRead, object: nil)
                }
            }
            CommandGroup(replacing: .help) {}
        }

        Settings {
            SettingsView(store: store)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: LinkStore
    @AppStorage("autoTagOnSave")       private var autoTag: Bool = false
    @AppStorage("autoSummarizeOnSave") private var autoSummary: Bool = false
    @AppStorage("autoPriorityOnSave")  private var autoPriority: Bool = false

    var body: some View {
        Form {
            Section {
                if AppleIntelligence.isAvailable {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").foregroundStyle(.indigo)
                        Text("Apple Intelligence is available on this Mac.")
                            .font(.callout)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Intelligence is unavailable.")
                                .font(.callout)
                            Text("Requires macOS 26+ with the on-device model downloaded in System Settings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Toggle("Auto-tag new links", isOn: $autoTag)
                    .disabled(!AppleIntelligence.isAvailable)
                Toggle("Auto-summarize new links", isOn: $autoSummary)
                    .disabled(!AppleIntelligence.isAvailable)
                Toggle("Auto-assess priority for new links", isOn: $autoPriority)
                    .disabled(!AppleIntelligence.isAvailable)

                Text("Runs in the background after a link is saved. May take a few seconds per link.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("AI Auto-processing", systemImage: "sparkles")
            }

            Section {
                Button("Process All Unprocessed Links Now") {
                    Task { await processBacklog() }
                }
                .disabled(!AppleIntelligence.isAvailable || backlogCount == 0)
                Text("\(backlogCount) link\(backlogCount == 1 ? "" : "s") missing AI summary/tags/priority.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Backlog")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
    }

    private var backlogCount: Int {
        store.links.filter {
            (autoSummary && $0.summary.isEmpty)
            || (autoTag && $0.tags.isEmpty)
            || (autoPriority && $0.priority == nil)
        }.count
    }

    private func processBacklog() async {
        for link in store.links {
            let needsSummary  = autoSummary  && link.summary.isEmpty
            let needsTags     = autoTag      && link.tags.isEmpty
            let needsPriority = autoPriority && link.priority == nil
            if needsSummary || needsTags || needsPriority {
                await store.processWithAI(link: link,
                                          doTags: needsTags,
                                          doSummary: needsSummary,
                                          doPriority: needsPriority)
            }
        }
    }
}

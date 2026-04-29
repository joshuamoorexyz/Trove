import SwiftUI

struct StatsView: View {
    @ObservedObject var store: LinkStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Reading Stats", systemImage: "chart.bar.fill")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    overviewSection
                    Divider()
                    topDomainsSection
                    if !store.allTags.isEmpty {
                        Divider()
                        topTagsSection
                    }
                    Divider()
                    recentActivitySection
                }
                .padding()
            }
        }
        .frame(width: 440, height: 580)
    }

    // MARK: - Overview cards

    @ViewBuilder
    private var overviewSection: some View {
        let total    = store.links.count
        let read     = store.links.filter(\.isRead).count
        let unread   = store.links.filter { !$0.isRead && !$0.isArchived }.count
        let starred  = store.links.filter(\.isFavorite).count
        let archived = store.links.filter(\.isArchived).count
        let pdfs     = store.links.filter(\.isPDF).count
        let totalWords = store.links.reduce(0) { $0 + $1.wordCount }
        let hours    = totalWords / 220 / 60
        let mins     = (totalWords / 220) % 60
        let timeLabel = hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"

        VStack(alignment: .leading, spacing: 10) {
            Label("Overview", systemImage: "chart.bar.fill")
                .font(.caption).foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatCard(value: "\(total)",    label: "Saved",    color: .blue)
                StatCard(value: "\(read)",     label: "Read",     color: .green)
                StatCard(value: "\(unread)",   label: "Unread",   color: .orange)
                StatCard(value: "\(starred)",  label: "Starred",  color: .yellow)
                StatCard(value: "\(archived)", label: "Archived", color: .gray)
                StatCard(value: pdfs > 0 ? "\(pdfs)" : timeLabel,
                         label: pdfs > 0 ? "PDFs" : "Content",
                         color: .indigo)
            }

            if total > 0 {
                let pct = Int(Double(read) / Double(total) * 100)
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(read), total: Double(total))
                        .tint(.green)
                    Text("\(pct)% of library read")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Top Domains

    @ViewBuilder
    private var topDomainsSection: some View {
        let domains = topDomains(limit: 6)
        let maxCount = domains.first?.count ?? 1

        if !domains.isEmpty { VStack(alignment: .leading, spacing: 8) {
            Label("Top Domains", systemImage: "globe")
                .font(.caption).foregroundStyle(.secondary)

            ForEach(domains, id: \.domain) { entry in
                HStack(spacing: 8) {
                    AsyncImage(url: URL(string: "https://www.google.com/s2/favicons?sz=32&domain=\(entry.domain)")) { img in
                        img.resizable().frame(width: 14, height: 14)
                    } placeholder: {
                        Image(systemName: "globe")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    Text(entry.domain)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .frame(minWidth: 80, alignment: .leading)

                    GeometryReader { geo in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.blue.opacity(0.35))
                                .frame(width: max(4, geo.size.width * CGFloat(entry.count) / CGFloat(maxCount)),
                                       height: 10)
                            Text("\(entry.count)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 14)
                }
            }
        } }
    }

    // MARK: - Top Tags

    @ViewBuilder
    private var topTagsSection: some View {
        let tags = topTags(limit: 10)

        if !tags.isEmpty { VStack(alignment: .leading, spacing: 8) {
            Label("Top Tags", systemImage: "tag.fill")
                .font(.caption).foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.tag) { entry in
                    HStack(spacing: 4) {
                        Text(entry.tag)
                            .font(.system(size: 12, weight: .medium))
                        Text("\(entry.count)")
                            .font(.system(size: 11))
                            .foregroundStyle(.purple.opacity(0.65))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.purple.opacity(0.10))
                    .foregroundStyle(.purple)
                    .clipShape(Capsule())
                }
            }
        } }
    }

    // MARK: - Recent Activity (bar chart by week)

    @ViewBuilder
    private var recentActivitySection: some View {
        let weeks = recentWeeks(count: 8)
        let maxW  = weeks.map(\.count).max() ?? 1

        VStack(alignment: .leading, spacing: 8) {
            Label("Saved — Last 8 Weeks", systemImage: "calendar")
                .font(.caption).foregroundStyle(.secondary)

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(weeks.reversed(), id: \.label) { w in
                    VStack(spacing: 4) {
                        if w.count > 0 {
                            Text("\(w.count)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue.opacity(w.count > 0 ? 0.55 : 0.12))
                            .frame(width: 26, height: max(6, 64.0 * Double(w.count) / Double(max(maxW, 1))))
                        Text(w.label)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 88, alignment: .bottom)

            let thisWeek = weeks.first?.count ?? 0
            let lastWeek = weeks.dropFirst().first?.count ?? 0
            let diff = thisWeek - lastWeek
            if thisWeek > 0 || lastWeek > 0 {
                Text(diff > 0
                     ? "+\(diff) vs. previous week"
                     : diff < 0 ? "\(diff) vs. previous week" : "Same as previous week")
                    .font(.caption)
                    .foregroundStyle(diff > 0 ? .green : diff < 0 ? .secondary : .secondary)
            }
        }
    }

    // MARK: - Data helpers

    private func topDomains(limit: Int) -> [(domain: String, count: Int)] {
        var counts: [String: Int] = [:]
        for link in store.links where !link.isArchived && !link.isPDF {
            counts[link.domain, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map { (domain: $0.key, count: $0.value) }
    }

    private func topTags(limit: Int) -> [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for link in store.links {
            for tag in link.tags { counts[tag, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map { (tag: $0.key, count: $0.value) }
    }

    private struct WeekEntry { let label: String; let count: Int }

    private func recentWeeks(count: Int = 8) -> [WeekEntry] {
        let cal = Calendar.current
        let now = Date()
        return (0..<count).compactMap { i in
            guard let end   = cal.date(byAdding: .day, value: -(i * 7),     to: now),
                  let start = cal.date(byAdding: .day, value: -((i + 1) * 7), to: now)
            else { return nil }
            let c = store.links.filter { $0.savedAt >= start && $0.savedAt < end }.count
            return WeekEntry(label: i == 0 ? "Now" : "-\(i)w", count: c)
        }
    }
}

// MARK: - Stat card

struct StatCard: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

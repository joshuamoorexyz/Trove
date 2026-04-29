import SwiftUI

struct LinkRowView: View {
    let link: Link

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Unread / progress dot
            ZStack {
                Circle()
                    .stroke(link.isRead ? Color.clear : Color.blue.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 8, height: 8)
                if !link.isRead && link.readingProgress > 0.02 && link.readingProgress < 0.95 {
                    Circle()
                        .trim(from: 0, to: link.readingProgress)
                        .stroke(Color.blue, lineWidth: 1.5)
                        .frame(width: 8, height: 8)
                        .rotationEffect(.degrees(-90))
                } else if !link.isRead {
                    Circle().fill(Color.blue).frame(width: 8, height: 8)
                }
            }
            .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(link.title)
                    .font(.system(size: 13, weight: link.isRead ? .regular : .semibold))
                    .lineLimit(2)

                if !link.excerpt.isEmpty {
                    Text(link.excerpt)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 4) {
                    AsyncImage(url: faviconURL) { img in
                        img.resizable().frame(width: 12, height: 12)
                    } placeholder: {
                        Image(systemName: "globe")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    Text(link.domain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text("·").foregroundStyle(.tertiary)

                    Text(link.timeAgo)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if let mins = link.readingMinutes {
                        Text("·").foregroundStyle(.tertiary)
                        Text("\(mins) min")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    if let p = link.priority, p != .normal {
                        Image(systemName: p == .high ? "exclamationmark.circle.fill" : "moon.zzz.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(p == .high ? .red : .gray)
                    }
                    if link.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                    }
                    if link.isArchived {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                    if !link.highlights.isEmpty {
                        Image(systemName: "highlighter")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                    }
                }

                if !link.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(link.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.12))
                                .foregroundStyle(.purple)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if let thumbURL = link.thumbnailURL {
                AsyncImage(url: thumbURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    default:
                        Color.clear.frame(width: 0, height: 0)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var faviconURL: URL? {
        URL(string: "https://www.google.com/s2/favicons?sz=32&domain=\(link.domain)")
    }
}

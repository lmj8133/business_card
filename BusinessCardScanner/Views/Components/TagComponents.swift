import SwiftUI

// MARK: - Tag Badge

/// Capsule-shaped tag badge with optional delete button.
struct TagBadge: View {
    let name: String
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.caption)
                .lineLimit(1)

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.blue.opacity(0.15), in: Capsule())
        .foregroundStyle(.blue)
    }
}

// MARK: - Selectable Tag Badge

/// Gray-outlined capsule for Quick Pick; tapping adds the tag.
private struct SelectableTagBadge: View {
    let name: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(name)
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.gray.opacity(0.2), in: Capsule())
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tag Flow Layout

/// Horizontal wrapping layout using the iOS 16+ Layout protocol.
struct TagFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        guard !rows.isEmpty else { return .zero }

        let height = rows.enumerated().reduce(CGFloat.zero) { total, entry in
            let (index, row) = entry
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            return total + rowHeight + (index > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX

            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentWidth += size.width + spacing
        }
        return rows
    }
}

// MARK: - Tag Input Field

/// Tag editor with Quick Pick sections and autocomplete support.
struct TagInputField: View {
    @Binding var tags: [String]
    var allCards: [BusinessCard] = []

    @State private var inputText = ""
    @State private var showAllTags = false
    @FocusState private var isFocused: Bool

    /// All unique tags across every card.
    private var allUniqueTags: [String] {
        Array(Set(allCards.flatMap(\.tags))).sorted()
    }

    /// Recent tags: from the latest 5 cards, ranked by frequency, excluding already-selected.
    private var recentTags: [String] {
        let recentCards = allCards.prefix(5) // allCards is already sorted by capturedAt desc
        let flatTags = recentCards.flatMap(\.tags)

        // Count frequency
        var freq: [String: Int] = [:]
        for tag in flatTags { freq[tag, default: 0] += 1 }

        return freq.keys
            .filter { !tags.contains($0) }
            .sorted { freq[$0, default: 0] > freq[$1, default: 0] }
    }

    /// Other tags: all unique tags minus recent and already-selected, sorted alphabetically.
    private var otherTags: [String] {
        let recentSet = Set(recentTags)
        let selectedSet = Set(tags)
        return allUniqueTags.filter { !recentSet.contains($0) && !selectedSet.contains($0) }
    }

    /// Tags shown in the "All" section (respects fold state).
    private var displayedOtherTags: [String] {
        if showAllTags || otherTags.count <= 8 {
            return otherTags
        }
        return Array(otherTags.prefix(8))
    }

    /// Autocomplete suggestions based on text input.
    private var suggestions: [String] {
        guard !inputText.isEmpty else { return [] }
        let query = inputText.lowercased()
        return allUniqueTags
            .filter { tag in
                tag.lowercased().contains(query) && !tags.contains(tag)
            }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. Selected tags
            if !tags.isEmpty {
                TagFlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        TagBadge(name: tag) {
                            tags.removeAll { $0 == tag }
                        }
                    }
                }
            }

            // 2. Quick Pick: Recent
            if !recentTags.isEmpty {
                Text("Recent")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TagFlowLayout(spacing: 6) {
                    ForEach(recentTags, id: \.self) { tag in
                        SelectableTagBadge(name: tag) { addTag(tag) }
                    }
                }
            }

            // 3. Quick Pick: All others
            if !otherTags.isEmpty {
                Text("All")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TagFlowLayout(spacing: 6) {
                    ForEach(displayedOtherTags, id: \.self) { tag in
                        SelectableTagBadge(name: tag) { addTag(tag) }
                    }
                }
                if otherTags.count > 8 && !showAllTags {
                    Button("Show All (\(otherTags.count - 8) more)") {
                        showAllTags = true
                    }
                    .font(.caption2)
                }
            }

            // 4. Text input
            TextField("Add tag\u{2026}", text: $inputText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .onSubmit { commitTag() }

            // 5. Autocomplete suggestions
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                addTag(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.gray.opacity(0.15), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func commitTag() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        addTag(trimmed)
    }

    private func addTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else {
            inputText = ""
            return
        }
        tags.append(trimmed)
        inputText = ""
    }
}

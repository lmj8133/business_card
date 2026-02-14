import SwiftData
import SwiftUI

/// List of all scanned business cards, sorted by capture date.
struct CardListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BusinessCard.capturedAt, order: .reverse) private var cards: [BusinessCard]
    @State private var searchText = ""
    @State private var selectedTag: String?

    private var allTags: [String] {
        Array(Set(cards.flatMap(\.tags))).sorted()
    }

    private var filteredCards: [BusinessCard] {
        var result = cards

        // Filter by selected tag
        if let selectedTag {
            result = result.filter { $0.tags.contains(selectedTag) }
        }

        // Filter by search text
        guard !searchText.isEmpty else { return result }
        let query = searchText.lowercased()
        return result.filter { card in
            card.name.lowercased().contains(query)
                || (card.company?.lowercased().contains(query) ?? false)
                || (card.email?.lowercased().contains(query) ?? false)
                || (card.position?.lowercased().contains(query) ?? false)
                || (card.notes?.lowercased().contains(query) ?? false)
                || card.tags.contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if cards.isEmpty {
                    ContentUnavailableView(
                        "No Cards Yet",
                        systemImage: "rectangle.stack",
                        description: Text("Scan a business card to get started.")
                    )
                } else {
                    VStack(spacing: 0) {
                        // Tag filter bar
                        if !allTags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(allTags, id: \.self) { tag in
                                        TagFilterChip(
                                            name: tag,
                                            isSelected: selectedTag == tag
                                        ) {
                                            selectedTag = selectedTag == tag ? nil : tag
                                        }
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                            }
                            .background(.bar)
                        }

                        List {
                            ForEach(filteredCards) { card in
                                NavigationLink(value: card) {
                                    CardRow(card: card)
                                }
                            }
                            .onDelete(perform: deleteCards)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search cards")
                }
            }
            .navigationTitle("Cards")
            .navigationDestination(for: BusinessCard.self) { card in
                CardDetailView(card: card)
            }
        }
    }

    private func deleteCards(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredCards[index])
        }
    }
}

// MARK: - Tag Filter Chip

struct TagFilterChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isSelected ? Color.blue : Color.gray.opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card Row

struct CardRow: View {
    let card: BusinessCard

    private var visibleTags: [String] { Array(card.tags.prefix(3)) }
    private var extraTagCount: Int { max(0, card.tags.count - 3) }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let imageData = card.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 56, height: 36)
                    .overlay {
                        Image(systemName: "person.crop.rectangle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(.headline)

                if let company = card.company {
                    Text(company)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let position = card.position {
                    Text(position)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Tags
                if !card.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(visibleTags, id: \.self) { tag in
                            TagBadge(name: tag)
                        }
                        if extraTagCount > 0 {
                            Text("+\(extraTagCount)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            Text(card.capturedAt, format: .dateTime.month(.abbreviated).day())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

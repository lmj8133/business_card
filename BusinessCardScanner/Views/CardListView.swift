import SwiftData
import SwiftUI

/// List of all scanned business cards, sorted by capture date.
struct CardListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BusinessCard.capturedAt, order: .reverse) private var cards: [BusinessCard]
    @State private var searchText = ""

    private var filteredCards: [BusinessCard] {
        guard !searchText.isEmpty else { return cards }
        let query = searchText.lowercased()
        return cards.filter { card in
            card.name.lowercased().contains(query)
                || (card.company?.lowercased().contains(query) ?? false)
                || (card.email?.lowercased().contains(query) ?? false)
                || (card.position?.lowercased().contains(query) ?? false)
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
                    List {
                        ForEach(filteredCards) { card in
                            NavigationLink(value: card) {
                                CardRow(card: card)
                            }
                        }
                        .onDelete(perform: deleteCards)
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

// MARK: - Card Row

struct CardRow: View {
    let card: BusinessCard

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
            }

            Spacer()

            Text(card.capturedAt, format: .dateTime.month(.abbreviated).day())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

import SwiftData
import SwiftUI
import UIKit

/// List of all scanned business cards, sorted by capture date.
struct CardListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BusinessCard.capturedAt, order: .reverse) private var cards: [BusinessCard]
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var selectionMode = false
    @State private var selectedCards: Set<PersistentIdentifier> = []
    @State private var showDeleteConfirmation = false
    @State private var cardToDelete: BusinessCard?

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
                            if selectionMode {
                                ForEach(filteredCards) { card in
                                    HStack(spacing: 8) {
                                        Image(systemName: selectedCards.contains(card.persistentModelID)
                                              ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(
                                                selectedCards.contains(card.persistentModelID)
                                                ? .blue : .gray.opacity(0.4)
                                            )
                                            .font(.title3)
                                        CardRow(card: card)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { toggleSelection(for: card) }
                                }
                            } else {
                                ForEach(filteredCards) { card in
                                    NavigationLink(value: card) {
                                        CardRow(card: card)
                                    }
                                    .contextMenu {
                                        if let company = card.company {
                                            Button {
                                                UIPasteboard.general.string = company
                                            } label: {
                                                Label("Copy Company", systemImage: "doc.on.doc")
                                            }
                                        }
                                        if let email = card.email {
                                            Button {
                                                UIPasteboard.general.string = email
                                            } label: {
                                                Label("Copy Email", systemImage: "doc.on.doc")
                                            }
                                        }
                                        Button(role: .destructive) {
                                            cardToDelete = card
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            modelContext.delete(card)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .overlay {
                            if filteredCards.isEmpty && !cards.isEmpty {
                                if !searchText.isEmpty {
                                    ContentUnavailableView.search(text: searchText)
                                } else if selectedTag != nil {
                                    ContentUnavailableView(
                                        "No Cards",
                                        systemImage: "tag",
                                        description: Text("No cards match the selected tag.")
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(selectionMode ? "" : "Cards")
            .searchable(text: $searchText, prompt: "Search cards")
            .toolbar {
                if selectionMode {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { exitSelectionMode() }
                    }
                    ToolbarItem(placement: .principal) {
                        Text("\(selectedCards.count) Selected")
                            .font(.headline)
                    }
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) { showDeleteConfirmation = true }
                            .disabled(selectedCards.isEmpty)
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button(selectedCards.count == filteredCards.count ? "Deselect All" : "Select All") {
                            if selectedCards.count == filteredCards.count {
                                selectedCards.removeAll()
                            } else {
                                selectedCards = Set(filteredCards.map(\.persistentModelID))
                            }
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Select") { enterSelectionMode() }
                    }
                }
            }
            .alert(
                "Delete this card?",
                isPresented: Binding(
                    get: { cardToDelete != nil },
                    set: { if !$0 { cardToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let card = cardToDelete {
                        modelContext.delete(card)
                    }
                    cardToDelete = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
            .alert(
                "Delete \(selectedCards.count) Card\(selectedCards.count == 1 ? "" : "s")?",
                isPresented: $showDeleteConfirmation
            ) {
                Button("Delete", role: .destructive) { deleteSelectedCards() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
            .onChange(of: searchText) { _, _ in pruneSelection() }
            .onChange(of: selectedTag) { _, _ in pruneSelection() }
            .navigationDestination(for: BusinessCard.self) { card in
                CardPagerView(
                    filteredCards: filteredCards,
                    selectedCardID: card.persistentModelID
                )
            }
        }
    }

    // MARK: - Multi-Select Helpers

    private func enterSelectionMode() {
        selectionMode = true
    }

    private func toggleSelection(for card: BusinessCard) {
        let id = card.persistentModelID
        if selectedCards.contains(id) {
            selectedCards.remove(id)
        } else {
            selectedCards.insert(id)
        }
    }

    private func exitSelectionMode() {
        selectionMode = false
        selectedCards.removeAll()
    }

    private func deleteSelectedCards() {
        for card in filteredCards where selectedCards.contains(card.persistentModelID) {
            modelContext.delete(card)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        exitSelectionMode()
    }

    private func pruneSelection() {
        let visibleIDs = Set(filteredCards.map(\.persistentModelID))
        selectedCards.formIntersection(visibleIDs)
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
                    isSelected ? Color.accentColor : Color.gray.opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            Group {
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
            }
            .accessibilityHidden(true)

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

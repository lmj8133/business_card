import SwiftData
import SwiftUI

/// Paged container that wraps CardDetailView instances for swipe navigation.
struct CardPagerView: View {
    let filteredCards: [BusinessCard]
    @State var selectedCardID: PersistentIdentifier

    var body: some View {
        TabView(selection: $selectedCardID) {
            ForEach(filteredCards) { card in
                CardDetailView(card: card)
                    .tag(card.persistentModelID)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(currentCard?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                if let index = currentIndex {
                    Text("\(index + 1) / \(filteredCards.count)")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(.bar, in: Capsule())
                }
            }
        }
    }

    private var currentCard: BusinessCard? {
        filteredCards.first { $0.persistentModelID == selectedCardID }
    }

    private var currentIndex: Int? {
        filteredCards.firstIndex { $0.persistentModelID == selectedCardID }
    }
}

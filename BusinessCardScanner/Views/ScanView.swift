import CoreImage
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

// MARK: - Batch Processing Models

enum ScanPhase: Equatable {
    case idle
    case processing(current: Int, total: Int)
    case results
}

struct ProcessedItem: Identifiable {
    let id = UUID()
    var card: BusinessCard?
    var errorMessage: String?
    var isIncluded: Bool = true
}

/// Main scanning view — camera + photo picker + processing status.
struct ScanView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var parser: BusinessCardParser

    @State private var showCamera = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var scannedCard: BusinessCard?
    @State private var ocrOnlyText: String?
    @State private var errorMessage: String?
    @State private var showResult = false

    // Batch processing state
    @State private var scanPhase: ScanPhase = .idle
    @State private var processedResults: [ProcessedItem] = []
    @State private var batchTags: [String] = []
    @State private var batchCancelled = false

    var body: some View {
        NavigationStack {
            Group {
                switch scanPhase {
                case .idle:
                    idleContent
                case .processing(let current, let total):
                    processingContent(current: current, total: total)
                case .results:
                    idleContent
                }
            }
            .navigationTitle("Scan")
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                AppDelegate.allowLandscape = false
                UIViewController.attemptRotationToDeviceOrientation()
            }) {
                CameraView { image, skipCardDetection in
                    showCamera = false
                    Task { await processImage(image, skipCardDetection: skipCardDetection) }
                }
                .ignoresSafeArea()
                .onAppear {
                    AppDelegate.allowLandscape = true
                    UIViewController.attemptRotationToDeviceOrientation()
                }
            }
            .onChange(of: selectedPhotos) { _, newItems in
                guard !newItems.isEmpty else { return }
                if newItems.count == 1 {
                    let item = newItems[0]
                    selectedPhotos = []
                    Task { await loadAndProcess(item: item) }
                } else {
                    let items = newItems
                    selectedPhotos = []
                    Task { await processBatch(pickerItems: items) }
                }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: Binding(
                get: { scanPhase == .results },
                set: { if !$0 { resetBatchState() } }
            )) {
                BatchResultsView(items: $processedResults, batchTags: $batchTags) {
                    for item in processedResults where item.isIncluded {
                        if let card = item.card {
                            modelContext.insert(card)
                        }
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    resetBatchState()
                } onDiscard: {
                    resetBatchState()
                }
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showResult) {
                if let card = scannedCard {
                    ScanResultView(card: card) {
                        modelContext.insert(card)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        showResult = false
                        scannedCard = nil
                    } onDiscard: {
                        showResult = false
                        scannedCard = nil
                    }
                    .interactiveDismissDisabled()
                } else if let text = ocrOnlyText {
                    OCROnlyResultView(text: text) {
                        showResult = false
                        ocrOnlyText = nil
                    }
                }
            }
        }
    }

    private func resetBatchState() {
        scanPhase = .idle
        processedResults = []
        batchTags = []
    }

    // MARK: - Subviews

    @ViewBuilder
    private var idleContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "creditcard.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)

            Text("Scan a Business Card")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Take a photo or choose from your library")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                Button {
                    showCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 20,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 40)

            Spacer()

            if parser.isProcessing {
                ProgressView("Processing…")
                    .padding()
            }
        }
    }

    @ViewBuilder
    private func processingContent(current: Int, total: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .controlSize(.large)

            Text("Processing \(current + 1) of \(total)…")
                .font(.headline)

            ProgressView(value: Double(current), total: Double(total))
                .padding(.horizontal, 60)

            Button("Cancel", role: .cancel) {
                batchCancelled = true
            }
            .buttonStyle(.bordered)

            if !processedResults.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(processedResults) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.card != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(item.card != nil ? .green : .red)
                            Text(item.card?.name ?? item.errorMessage ?? "Unknown")
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 40)
            }

            Spacer()
        }
    }

    // MARK: - Processing

    private func loadAndProcess(item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let ciImage = CIImage(data: data)
        else {
            errorMessage = "Failed to load the selected photo."
            return
        }
        let oriented: CIImage
        if let val = ciImage.properties[kCGImagePropertyOrientation as String] as? UInt32,
           let cgOrientation = CGImagePropertyOrientation(rawValue: val) {
            oriented = ciImage.oriented(cgOrientation).baked()
        } else {
            oriented = ciImage
        }
        await processImage(oriented)
    }

    private func processImage(_ image: CIImage, skipCardDetection: Bool = false) async {
        do {
            let card = try await parser.parse(image: image, skipCardDetection: skipCardDetection)
            scannedCard = card
            showResult = true
        } catch is URLError {
            // Network error — fall back to OCR-only mode
            await fallbackOCROnly(image: image, skipCardDetection: skipCardDetection)
        } catch let error as ExtractorError {
            if case .connectionFailed = error {
                await fallbackOCROnly(image: image, skipCardDetection: skipCardDetection)
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fallbackOCROnly(image: CIImage, skipCardDetection: Bool = false) async {
        do {
            let result = try await parser.parseOCROnly(image: image, skipCardDetection: skipCardDetection)
            if result.text.isEmpty {
                errorMessage = "No text detected in the image."
            } else {
                ocrOnlyText = result.text
                showResult = true
            }
        } catch {
            errorMessage = "OCR failed: \(error.localizedDescription)"
        }
    }

    private func processBatch(pickerItems: [PhotosPickerItem]) async {
        processedResults = []
        batchTags = []
        batchCancelled = false
        let total = pickerItems.count

        for (index, pickerItem) in pickerItems.enumerated() {
            if batchCancelled { break }
            scanPhase = .processing(current: index, total: total)

            guard let data = try? await pickerItem.loadTransferable(type: Data.self),
                  let ciImage = CIImage(data: data) else {
                processedResults.append(ProcessedItem(errorMessage: "Failed to load image."))
                continue
            }

            let oriented: CIImage
            if let val = ciImage.properties[kCGImagePropertyOrientation as String] as? UInt32,
               let cgOrientation = CGImagePropertyOrientation(rawValue: val) {
                oriented = ciImage.oriented(cgOrientation).baked()
            } else {
                oriented = ciImage
            }

            do {
                let card = try await parser.parse(image: oriented)
                processedResults.append(ProcessedItem(card: card))
            } catch is URLError {
                processedResults.append(ProcessedItem(errorMessage: "Network error"))
            } catch {
                processedResults.append(ProcessedItem(errorMessage: error.localizedDescription))
            }
        }

        if batchCancelled && processedResults.isEmpty {
            resetBatchState()
        } else if !processedResults.isEmpty {
            scanPhase = .results
        } else {
            resetBatchState()
        }
    }
}

// MARK: - Scan Result View

struct ScanResultView: View {
    @Bindable var card: BusinessCard
    @Query(sort: \BusinessCard.capturedAt, order: .reverse) private var allCards: [BusinessCard]
    let onSave: () -> Void
    let onDiscard: () -> Void
    @State private var showDiscardConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Extracted Information") {
                    LabeledRow(label: "Name", value: card.name)
                    LabeledRow(label: "Company", value: card.company)
                    LabeledRow(label: "Position", value: card.position)
                    LabeledRow(label: "Email", value: card.email)
                }

                Section("Tags") {
                    TagInputField(tags: $card.tags, allCards: allCards)
                }

                Section("Notes") {
                    TextField("Add notes…", text: Binding(
                        get: { card.notes ?? "" },
                        set: { card.notes = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(3...6)
                }

                #if DEBUG
                Section("Confidence") {
                    HStack {
                        Text("Score")
                        Spacer()
                        Text(String(format: "%.0f%%", card.confidence * 100))
                            .foregroundStyle(card.confidence >= 0.7 ? .green : .orange)
                            .fontWeight(.semibold)
                    }
                }

                Section("Raw OCR Text") {
                    Text(card.rawText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                #endif
            }
            .navigationTitle("Scan Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        showDiscardConfirmation = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Discard this scan?", isPresented: $showDiscardConfirmation) {
                Button("Discard", role: .destructive, action: onDiscard)
            }
        }
    }
}

// MARK: - OCR-Only Result View

struct OCROnlyResultView: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(
                        "Could not connect to Ollama server. Showing raw OCR text only.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding()
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                    Text(text)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                .padding()
            }
            .navigationTitle("OCR Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }
}

// MARK: - Batch Results View

struct BatchResultsView: View {
    @Binding var items: [ProcessedItem]
    @Binding var batchTags: [String]
    @Query(sort: \BusinessCard.capturedAt, order: .reverse) private var allCards: [BusinessCard]

    let onSave: () -> Void
    let onDiscard: () -> Void

    @State private var showDiscardConfirmation = false

    private var includedCount: Int {
        items.filter { $0.isIncluded && $0.card != nil }.count
    }

    private var successfulItems: [ProcessedItem] {
        items.filter { $0.card != nil }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Tags") {
                    TagInputField(tags: $batchTags, allCards: allCards)
                }

                Section("Results") {
                    ForEach($items) { $item in
                        if let card = item.card {
                            HStack(spacing: 8) {
                                Image(systemName: item.isIncluded ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isIncluded ? .blue : .gray.opacity(0.4))
                                    .font(.title3)
                                    .onTapGesture {
                                        let newValue = !item.isIncluded
                                        $item.wrappedValue.isIncluded = newValue
                                        if newValue {
                                            for tag in batchTags where !card.tags.contains(tag) {
                                                card.tags.append(tag)
                                            }
                                        }
                                    }

                                NavigationLink(value: item.id) {
                                    CardRow(card: card)
                                }
                            }
                        } else {
                            HStack(spacing: 12) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)

                                Text(item.errorMessage ?? "Unknown error")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .onChange(of: batchTags) { oldTags, newTags in
                let oldSet = Set(oldTags)
                let newSet = Set(newTags)
                let added = newSet.subtracting(oldSet)
                let removed = oldSet.subtracting(newSet)

                for item in items where item.isIncluded {
                    guard let card = item.card else { continue }
                    for tag in added where !card.tags.contains(tag) {
                        card.tags.append(tag)
                    }
                    for tag in removed {
                        card.tags.removeAll { $0 == tag }
                    }
                }
            }
            .navigationTitle("Batch Results")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { itemID in
                BatchCardPagerView(
                    items: successfulItems,
                    selectedID: itemID
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard All") {
                        showDiscardConfirmation = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save (\(includedCount))") {
                        onSave()
                    }
                    .fontWeight(.semibold)
                    .disabled(includedCount == 0)
                }
            }
            .confirmationDialog("Discard all results?", isPresented: $showDiscardConfirmation) {
                Button("Discard All", role: .destructive, action: onDiscard)
            }
        }
    }
}

// MARK: - Batch Card Pager

/// Swipeable pager for previewing batch-processed cards (mirrors CardPagerView).
struct BatchCardPagerView: View {
    let items: [ProcessedItem]
    @State var selectedID: UUID

    var body: some View {
        TabView(selection: $selectedID) {
            ForEach(items) { item in
                if let card = item.card {
                    CardDetailView(card: card)
                        .tag(item.id)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(currentCard?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                if let index = currentIndex {
                    Text("\(index + 1) / \(items.count)")
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
        items.first { $0.id == selectedID }?.card
    }

    private var currentIndex: Int? {
        items.firstIndex { $0.id == selectedID }
    }
}

// MARK: - Helper

struct LabeledRow: View {
    let label: String
    let value: String?

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—")
                .multilineTextAlignment(.trailing)
        }
    }
}

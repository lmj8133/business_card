import CoreImage
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// Main scanning view — camera + photo picker + processing status.
struct ScanView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var parser = BusinessCardParser()

    @State private var showCamera = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var scannedCard: BusinessCard?
    @State private var ocrOnlyText: String?
    @State private var errorMessage: String?
    @State private var showResult = false

    var body: some View {
        NavigationStack {
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
                        selection: $selectedPhoto,
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
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                Task { await loadAndProcess(item: newItem) }
                selectedPhoto = nil
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showResult) {
                if let card = scannedCard {
                    ScanResultView(card: card) {
                        modelContext.insert(card)
                        showResult = false
                        scannedCard = nil
                    } onDiscard: {
                        showResult = false
                        scannedCard = nil
                    }
                } else if let text = ocrOnlyText {
                    OCROnlyResultView(text: text) {
                        showResult = false
                        ocrOnlyText = nil
                    }
                }
            }
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
}

// MARK: - Scan Result View

struct ScanResultView: View {
    @Bindable var card: BusinessCard
    @Query(sort: \BusinessCard.capturedAt, order: .reverse) private var allCards: [BusinessCard]
    let onSave: () -> Void
    let onDiscard: () -> Void

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
                    Button("Discard", role: .destructive, action: onDiscard)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .fontWeight(.semibold)
                }
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

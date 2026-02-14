import Contacts
import SwiftData
import SwiftUI

/// Detail view for a scanned business card with editing and contact export.
struct CardDetailView: View {
    @Bindable var card: BusinessCard
    @Query(sort: \BusinessCard.capturedAt, order: .reverse) private var allCards: [BusinessCard]
    @State private var showContactAlert = false
    @State private var contactAlertMessage = ""

    var body: some View {
        List {
            // Card image
            if let imageData = card.imageData, let uiImage = UIImage(data: imageData) {
                Section {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                }
            }

            // Editable fields
            Section("Contact Information") {
                EditableField(label: "Name", text: $card.name)
                OptionalEditableField(label: "Company", text: $card.company)
                OptionalEditableField(label: "Position", text: $card.position)
                OptionalEditableField(label: "Email", text: $card.email)
            }

            // Tags
            Section("Tags") {
                TagInputField(tags: $card.tags, allCards: allCards)
            }

            // Notes
            Section("Notes") {
                TextField("Add notes…", text: Binding(
                    get: { card.notes ?? "" },
                    set: { card.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(3...6)
            }

            // Metadata
            Section("Details") {
                #if DEBUG
                HStack {
                    Text("Confidence")
                    Spacer()
                    ConfidenceBadge(value: card.confidence)
                }
                #endif

                HStack {
                    Text("Captured")
                    Spacer()
                    Text(card.capturedAt, format: .dateTime)
                        .foregroundStyle(.secondary)
                }

                if let ocr = card.ocrBackend {
                    HStack {
                        Text("OCR Engine")
                        Spacer()
                        Text(ocr).foregroundStyle(.secondary)
                    }
                }

                if let extractor = card.extractorBackend {
                    HStack {
                        Text("Extractor")
                        Spacer()
                        Text(extractor).foregroundStyle(.secondary)
                    }
                }

                if let ms = card.processingTimeMs {
                    HStack {
                        Text("Processing Time")
                        Spacer()
                        Text(String(format: "%.0f ms", ms))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Raw OCR text
            #if DEBUG
            Section("Raw OCR Text") {
                Text(card.rawText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif

            // Actions
            Section {
                Button {
                    saveToContacts()
                } label: {
                    Label("Save to Contacts", systemImage: "person.crop.circle.badge.plus")
                }
            }
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Contacts", isPresented: $showContactAlert) {
            Button("OK") {}
        } message: {
            Text(contactAlertMessage)
        }
    }

    // MARK: - Contacts

    private func saveToContacts() {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, error in
            DispatchQueue.main.async {
                guard granted else {
                    contactAlertMessage = "Contacts access denied. Please enable in Settings."
                    showContactAlert = true
                    return
                }

                let contact = card.toCNContact()
                let saveRequest = CNSaveRequest()
                saveRequest.add(contact, toContainerWithIdentifier: nil)

                do {
                    try store.execute(saveRequest)
                    contactAlertMessage = "Contact saved successfully."
                } catch {
                    contactAlertMessage = "Failed to save contact: \(error.localizedDescription)"
                }
                showContactAlert = true
            }
        }
    }
}

// MARK: - Editable Field

struct EditableField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            TextField(label, text: $text)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct OptionalEditableField: View {
    let label: String
    @Binding var text: String?

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            TextField(label, text: Binding(
                get: { text ?? "" },
                set: { text = $0.isEmpty ? nil : $0 }
            ))
            .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Confidence Badge

struct ConfidenceBadge: View {
    let value: Double

    var body: some View {
        Text(String(format: "%.0f%%", value * 100))
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        if value >= 0.8 { return .green }
        if value >= 0.5 { return .orange }
        return .red
    }
}

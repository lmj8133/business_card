import Foundation
import SwiftData

/// Persisted business card — maps to Python BusinessCard + Metadata.
@Model
class BusinessCard {
    var company: String?
    var name: String
    var position: String?
    var email: String?
    var rawText: String
    var confidence: Double
    var capturedAt: Date
    var imageData: Data?

    // User-editable metadata
    var notes: String?
    var tags: [String] = []

    // Metadata (flattened, no need for a separate table)
    var ocrBackend: String?
    var extractorBackend: String?
    var processingTimeMs: Double?

    init(
        company: String? = nil,
        name: String,
        position: String? = nil,
        email: String? = nil,
        rawText: String,
        confidence: Double = 0.0,
        capturedAt: Date = .now,
        imageData: Data? = nil,
        notes: String? = nil,
        tags: [String] = [],
        ocrBackend: String? = nil,
        extractorBackend: String? = nil,
        processingTimeMs: Double? = nil
    ) {
        self.company = company
        self.name = name
        self.position = position
        self.email = email
        self.rawText = rawText
        self.confidence = confidence
        self.capturedAt = capturedAt
        self.imageData = imageData
        self.notes = notes
        self.tags = tags
        self.ocrBackend = ocrBackend
        self.extractorBackend = extractorBackend
        self.processingTimeMs = processingTimeMs
    }
}

/// LLM-extracted card data (transient, before persisting).
struct ExtractedCard: Decodable {
    let company: String?
    let name: String
    let position: String?
    let email: String?
    let confidence: Double
}

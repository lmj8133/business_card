import CoreImage
import Foundation
import UIKit

/// Pipeline controller — corresponds to Python `BusinessCardParser`.
/// Flow: detect card → OCR → LLM extract → attach metadata.
@MainActor
final class BusinessCardParser: ObservableObject {
    let ocrEngine: OCREngine
    let extractor: CardExtractor

    @Published var isProcessing = false
    @Published var lastError: String?

    init(ocrEngine: OCREngine = VisionOCREngine(), extractor: CardExtractor = OllamaExtractor()) {
        self.ocrEngine = ocrEngine
        self.extractor = extractor
    }

    /// Full pipeline: OCR + LLM extraction.
    func parse(image: CIImage, skipCardDetection: Bool = false) async throws -> BusinessCard {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        let start = CFAbsoluteTimeGetCurrent()

        // Step 1 & 2: Card detection + OCR (handled inside the engine)
        let ocrResult = try await ocrEngine.recognize(in: image, skipCardDetection: skipCardDetection)

        guard !ocrResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParserError.noTextExtracted
        }

        // Step 3: LLM extraction
        let extracted = try await extractor.extract(ocrText: ocrResult.text)

        // Step 4: Build persisted model with metadata
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

        let card = BusinessCard(
            company: extracted.company,
            name: extracted.name,
            position: extracted.position,
            email: extracted.email?.lowercased(),
            rawText: ocrResult.text,
            confidence: extracted.confidence,
            imageData: (ocrResult.processedImage ?? image).pngData(),
            ocrBackend: ocrEngine.name,
            extractorBackend: extractor.name,
            processingTimeMs: (elapsedMs * 100).rounded() / 100
        )

        return card
    }

    /// OCR-only mode (offline fallback).
    func parseOCROnly(image: CIImage, skipCardDetection: Bool = false) async throws -> OCRResult {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        return try await ocrEngine.recognize(in: image, skipCardDetection: skipCardDetection)
    }
}

// MARK: - Errors

enum ParserError: LocalizedError {
    case noTextExtracted

    var errorDescription: String? {
        switch self {
        case .noTextExtracted:
            return "OCR extracted no text from the image."
        }
    }
}

// MARK: - CIImage Helpers

extension CIImage {
    /// Render all pending transforms into actual pixels, ensuring extent.origin == (0, 0).
    func baked() -> CIImage {
        let ctx = CIContext()
        guard let cgImage = ctx.createCGImage(self, from: extent) else { return self }
        return CIImage(cgImage: cgImage)
    }

    /// Convert CIImage to PNG Data for storage.
    func pngData(maxDimension: CGFloat = 800) -> Data? {
        let scale = min(maxDimension / extent.width, maxDimension / extent.height, 1.0)
        let scaled = transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage).pngData()
    }
}

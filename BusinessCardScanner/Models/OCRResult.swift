import Foundation
import CoreGraphics

/// Single OCR detection with position.
struct OCRBox {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}

/// Aggregated OCR output from a single image.
struct OCRResult {
    let text: String
    let confidence: Float
    let boxes: [OCRBox]

    static let empty = OCRResult(text: "", confidence: 0, boxes: [])
}

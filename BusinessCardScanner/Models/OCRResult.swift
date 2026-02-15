import CoreImage
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
    /// The image after card detection / cropping (if any).
    var processedImage: CIImage?

    static let empty = OCRResult(text: "", confidence: 0, boxes: [])
}

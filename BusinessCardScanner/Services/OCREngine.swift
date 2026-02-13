import CoreImage

/// Abstract OCR engine — corresponds to Python `OCRBackend`.
protocol OCREngine {
    var name: String { get }
    func recognize(in image: CIImage) async throws -> OCRResult
}

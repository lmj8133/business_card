import Foundation

/// Abstract LLM extractor — corresponds to Python `Extractor`.
protocol CardExtractor {
    var name: String { get }
    func extract(ocrText: String) async throws -> ExtractedCard
}

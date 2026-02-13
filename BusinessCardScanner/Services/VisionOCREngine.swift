import CoreImage
import Vision

/// Apple Vision OCR engine with built-in card detection.
final class VisionOCREngine: OCREngine {
    let name = "apple_vision"

    /// Recognition languages (configurable from Settings).
    var recognitionLanguages: [String] = ["zh-Hant", "en", "ja"]

    // MARK: - Public

    func recognize(in image: CIImage) async throws -> OCRResult {
        // Step 1: Try to detect and crop the card region
        let cropped = (try? await detectCard(in: image)) ?? image

        // Step 2: Run text recognition on the (optionally cropped) image
        return try await recognizeText(in: cropped)
    }

    // MARK: - Card Detection

    /// Detect the largest rectangle (business card) in the image.
    private func detectCard(in image: CIImage) async throws -> CIImage {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.4
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.2
        request.maximumObservations = 1
        request.minimumConfidence = 0.5

        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        guard let observation = request.results?.first else {
            throw OCRError.noCardDetected
        }

        return cropToQuadrilateral(image: image, observation: observation)
    }

    /// Crop a CIImage to the detected quadrilateral.
    private func cropToQuadrilateral(
        image: CIImage,
        observation: VNRectangleObservation
    ) -> CIImage {
        let width = image.extent.width
        let height = image.extent.height

        // Vision coordinates are normalized (0-1), origin bottom-left
        let topLeft = CGPoint(
            x: observation.topLeft.x * width,
            y: observation.topLeft.y * height
        )
        let topRight = CGPoint(
            x: observation.topRight.x * width,
            y: observation.topRight.y * height
        )
        let bottomLeft = CGPoint(
            x: observation.bottomLeft.x * width,
            y: observation.bottomLeft.y * height
        )
        let bottomRight = CGPoint(
            x: observation.bottomRight.x * width,
            y: observation.bottomRight.y * height
        )

        let corrected = image.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": CIVector(cgPoint: topLeft),
            "inputTopRight": CIVector(cgPoint: topRight),
            "inputBottomLeft": CIVector(cgPoint: bottomLeft),
            "inputBottomRight": CIVector(cgPoint: bottomRight),
        ])

        return corrected
    }

    // MARK: - Text Recognition

    private func recognizeText(in image: CIImage) async throws -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = recognitionLanguages
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        guard let observations = request.results, !observations.isEmpty else {
            return .empty
        }

        var boxes: [OCRBox] = []
        var totalConfidence: Float = 0

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let box = OCRBox(
                text: candidate.string,
                confidence: candidate.confidence,
                boundingBox: observation.boundingBox
            )
            boxes.append(box)
            totalConfidence += candidate.confidence
        }

        let fullText = boxes.map(\.text).joined(separator: "\n")
        let avgConfidence = boxes.isEmpty ? 0 : totalConfidence / Float(boxes.count)

        return OCRResult(text: fullText, confidence: avgConfidence, boxes: boxes)
    }
}

// MARK: - Errors

enum OCRError: LocalizedError {
    case noCardDetected

    var errorDescription: String? {
        switch self {
        case .noCardDetected:
            return "No business card detected in the image."
        }
    }
}

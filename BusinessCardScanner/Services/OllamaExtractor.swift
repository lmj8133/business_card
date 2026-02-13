import Foundation

/// Ollama LLM extractor — ported from Python `extractor/ollama.py`.
final class OllamaExtractor: CardExtractor {
    let name = "ollama"

    private let session = URLSession.shared
    private let timeoutSeconds: TimeInterval = 60

    // MARK: - Prompts (1:1 from Python)

    static let systemPrompt = """
    You are a business card information extractor.
    Extract structured contact information from OCR text.

    Return ONLY a valid JSON object with this structure (no markdown, no explanation):
    {
      "company": "string or null",
      "name": "string (required)",
      "position": "string or null (combine department and title, e.g. 'Sales Dept, Manager')",
      "email": "string or null",
      "confidence": 0.0-1.0
    }

    Guidelines:
    - Cross-validate company name with email domain (e.g., if email is "@algoltek.com", company is likely "Algoltek")
    - Cross-validate name with email prefix (e.g., "jeff.fu@" suggests name is "Jeff Fu"; use to fix OCR errors like "Jeft Fu" -> "Jeff Fu")
    - Cross-validate email prefix with name (e.g., if name is "Jeff Fu" but email shows "jeft.fu@", correct to "jeff.fu@")
    - When name and email prefix conflict, prefer email (more reliable OCR) unless email is abbreviated or doesn't contain name info
    - If multiple emails exist, pick the primary one (typically the person's own email)
    - Split names by case transitions: "MJLi" -> "MJ Li", "JohnSmith" -> "John Smith"
    - Common OCR confusions: L↔I, O↔0, 1↔l - use context to resolve
    - Always return valid JSON
    """

    static func userPrompt(ocrText: String) -> String {
        """
        Extract business card information from this OCR text:

        ---
        \(ocrText)
        ---

        Return only the JSON object.
        """
    }

    // MARK: - Configuration

    /// Ollama server base URL (configurable from Settings).
    var baseURL: String {
        UserDefaults.standard.string(forKey: "ollamaBaseURL")
            ?? "http://localhost:11434"
    }

    /// Ollama model name (configurable from Settings).
    var modelName: String {
        UserDefaults.standard.string(forKey: "ollamaModel")
            ?? "gemma3:27b"
    }

    // MARK: - CardExtractor

    func extract(ocrText: String) async throws -> ExtractedCard {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw ExtractorError.connectionFailed("Invalid Ollama URL: \(baseURL)")
        }

        let payload: [String: Any] = [
            "model": modelName,
            "system": Self.systemPrompt,
            "prompt": Self.userPrompt(ocrText: ocrText),
            "stream": false,
            "format": "json",
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutSeconds
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ExtractorError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ExtractorError.serverError(statusCode: http.statusCode, body: body)
        }

        return try parseResponse(data)
    }

    // MARK: - Response Parsing (ported from Python _parse_response / _extract_json)

    private func parseResponse(_ data: Data) throws -> ExtractedCard {
        // Ollama wraps the answer in { "response": "..." }
        guard let wrapper = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseString = wrapper["response"] as? String
        else {
            throw ExtractorError.parseError("Missing 'response' field in Ollama reply")
        }

        let json = try extractJSON(from: responseString)
        return try decodeCard(from: json)
    }

    /// Extract a JSON object string from the LLM response.
    /// Handles: raw JSON, ```json code blocks, and arrays (takes first element).
    private func extractJSON(from text: String) throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try ```json ... ``` code block first
        if let range = trimmed.range(
            of: #"```(?:json)?\s*([\s\S]*?)```"#,
            options: .regularExpression
        ) {
            let match = String(trimmed[range])
            let inner = match
                .replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
            if let data = inner.data(using: .utf8) {
                return data
            }
        }

        // Try raw JSON object { ... }
        if let range = trimmed.range(of: #"\{[\s\S]*?\}"#, options: .regularExpression) {
            let jsonStr = String(trimmed[range])
            if let data = jsonStr.data(using: .utf8) {
                return data
            }
        }

        // Try JSON array — take first element
        if let range = trimmed.range(of: #"\[[\s\S]*\]"#, options: .regularExpression) {
            let arrayStr = String(trimmed[range])
            if let arrayData = arrayStr.data(using: .utf8),
               let array = try JSONSerialization.jsonObject(with: arrayData) as? [[String: Any]],
               let first = array.first
            {
                return try JSONSerialization.data(withJSONObject: first)
            }
        }

        throw ExtractorError.parseError("No valid JSON found in LLM response")
    }

    private func decodeCard(from data: Data) throws -> ExtractedCard {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ExtractedCard.self, from: data)
        } catch {
            throw ExtractorError.parseError("Failed to decode ExtractedCard: \(error.localizedDescription)")
        }
    }
}

// MARK: - Errors

enum ExtractorError: LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int, body: String)
    case parseError(String)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Ollama server."
        case .serverError(let code, let body):
            return "Ollama server error (\(code)): \(body)"
        case .parseError(let detail):
            return "Failed to parse LLM response: \(detail)"
        case .connectionFailed(let detail):
            return "Cannot connect to Ollama server: \(detail)"
        }
    }
}

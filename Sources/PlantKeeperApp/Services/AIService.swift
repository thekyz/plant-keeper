import Foundation
import Security
import PlantKeeperCore

enum AIServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is missing. Add it in Settings."
        case .invalidResponse:
            return "AI service returned an invalid response."
        case .invalidPayload:
            return "AI service returned an unreadable payload."
        }
    }
}

enum OpenAIKeyValidationError: LocalizedError {
    case emptyKey
    case invalidKey
    case forbidden
    case rateLimited
    case apiError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            return "Enter an OpenAI API key first."
        case .invalidKey:
            return "OpenAI rejected this API key. Check that it is correct."
        case .forbidden:
            return "This API key cannot access the configured OpenAI model."
        case .rateLimited:
            return "OpenAI rate limited the validation request. Try again in a moment."
        case .apiError(let message):
            return message
        case .invalidResponse:
            return "OpenAI validation returned an invalid response."
        }
    }
}

protocol APIKeyStoring: Sendable {
    func loadCloudAPIKey() -> String?
    func saveCloudAPIKey(_ key: String) -> Bool
    func removeCloudAPIKey() -> Bool
}

protocol OpenAIKeyValidating: Sendable {
    func validateAPIKey(_ key: String) async throws
}

struct KeychainKeyStore: APIKeyStoring {
    private let service = "com.plantkeeper.openai"
    private let account = "openai_api_key"

    func loadCloudAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    func saveCloudAPIKey(_ key: String) -> Bool {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributesToUpdate: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

        if updateStatus == errSecSuccess {
            return true
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    func removeCloudAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

struct OnDevicePlantAnalyzer: PlantAnalyzing {
    func analyzePhotoData(_ data: Data) async throws -> AIAnalysisResult {
        AIAnalysisResult(
            nameEnglish: "Unknown Plant",
            nameFrench: "Plante inconnue",
            confidence: 0.35,
            suggestedWateringIntervalDays: 7,
            suggestedCheckIntervalDays: 3,
            careHints: ["Needs manual confirmation"],
            identificationStatus: .placeholder
        )
    }
}

struct CloudPlantAnalyzer: PlantAnalyzing, OpenAIKeyValidating {
    let keyStore: APIKeyStoring
    var model: String = "gpt-4.1-mini"
    var urlSession: URLSession = .shared

    func analyzePhotoData(_ data: Data) async throws -> AIAnalysisResult {
        guard let apiKey = keyStore.loadCloudAPIKey(), !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey
        }

        let dataURL = "data:image/jpeg;base64,\(data.base64EncodedString())"
        let analysisPrompt = """
        Analyze this plant photo and return JSON with keys: english_name, french_name, confidence, watering_interval_days, check_interval_days, care_hints.
        Use integer day counts for watering_interval_days and check_interval_days.
        watering_interval_days is your best estimate for how many days should usually pass between waterings for this plant.
        check_interval_days is your best estimate for how many days should pass before checking soil moisture or plant condition again.
        Do not use generic defaults like 7 unless the plant genuinely fits that cadence.
        care_hints must be an array of short, practical tips specific to this plant.
        """
        let request = try makeRequest(
            apiKey: apiKey,
            body: OpenAIChatRequest(
                model: model,
                temperature: 0.2,
                responseFormat: .init(type: "json_object"),
                messages: [
                    .init(
                        role: "system",
                        content: .text("You analyze plant photos, identify the plant, and return strict JSON only.")
                    ),
                    .init(
                        role: "user",
                        content: .multi([
                            .init(type: "text", text: analysisPrompt),
                            .init(type: "image_url", imageURL: .init(url: dataURL))
                        ])
                    )
                ]
            )
        )

        let (responseData, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw AIServiceError.invalidResponse
        }

        let completion = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: responseData)
        guard let rawContent = completion.choices.first?.message.content,
              let payloadData = normalizedJSONContent(rawContent).data(using: .utf8) else {
            throw AIServiceError.invalidPayload
        }

        let parsed = try JSONDecoder().decode(PlantExtractionPayload.self, from: payloadData)

        return AIAnalysisResult(
            nameEnglish: parsed.englishName,
            nameFrench: parsed.frenchName,
            confidence: min(max(parsed.confidence, 0.0), 1.0),
            suggestedWateringIntervalDays: max(1, parsed.wateringIntervalDays),
            suggestedCheckIntervalDays: max(1, parsed.checkIntervalDays),
            careHints: parsed.careHints,
            identificationStatus: .identified
        )
    }

    func validateAPIKey(_ key: String) async throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAIKeyValidationError.emptyKey
        }

        let request = try makeRequest(
            apiKey: trimmedKey,
            body: OpenAIChatRequest(
                model: model,
                temperature: 0,
                responseFormat: .init(type: "json_object"),
                messages: [
                    .init(
                        role: "system",
                        content: .text("Return strict JSON only.")
                    ),
                    .init(
                        role: "user",
                        content: .text("Return this exact JSON: {\"ok\":true}")
                    )
                ]
            )
        )

        let (responseData, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIKeyValidationError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw validationError(statusCode: httpResponse.statusCode, responseData: responseData)
        }
    }

    private func makeRequest(apiKey: String, body: OpenAIChatRequest) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}

private func validationError(statusCode: Int, responseData: Data) -> OpenAIKeyValidationError {
    let apiMessage = decodeOpenAIErrorMessage(from: responseData)

    switch statusCode {
    case 401:
        return .invalidKey
    case 403:
        return .forbidden
    case 429:
        return .rateLimited
    default:
        if let apiMessage, !apiMessage.isEmpty {
            return .apiError(apiMessage)
        }
        return .apiError("OpenAI validation failed with status \(statusCode).")
    }
}

private func decodeOpenAIErrorMessage(from data: Data) -> String? {
    guard let payload = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) else {
        return nil
    }
    return payload.error.message
}

private func normalizedJSONContent(_ content: String) -> String {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```") else { return trimmed }

    var cleaned = trimmed
    cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
    cleaned = cleaned.replacingOccurrences(of: "```", with: "")
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
}

struct HybridAIService: PlantAnalyzing {
    let onDevice: PlantAnalyzing
    let cloud: PlantAnalyzing
    let keyStore: APIKeyStoring
    var fallbackThreshold: Double = 0.6

    func analyzePhotoData(_ data: Data) async throws -> AIAnalysisResult {
        let onDeviceResult = try await onDevice.analyzePhotoData(data)
        guard onDeviceResult.confidence < fallbackThreshold,
              keyStore.loadCloudAPIKey() != nil else {
            return onDeviceResult
        }

        return try await cloud.analyzePhotoData(data)
    }
}

private struct OpenAIChatRequest: Encodable {
    struct ResponseFormat: Encodable {
        let type: String
    }

    struct Message: Encodable {
        enum Content: Encodable {
            case text(String)
            case multi([Part])

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let text):
                    try container.encode(text)
                case .multi(let parts):
                    try container.encode(parts)
                }
            }
        }

        struct Part: Encodable {
            struct ImageURL: Encodable {
                let url: String

                enum CodingKeys: String, CodingKey {
                    case url
                }
            }

            let type: String
            var text: String?
            var imageURL: ImageURL?

            enum CodingKeys: String, CodingKey {
                case type
                case text
                case imageURL = "image_url"
            }

            init(type: String, text: String? = nil, imageURL: ImageURL? = nil) {
                self.type = type
                self.text = text
                self.imageURL = imageURL
            }
        }

        let role: String
        let content: Content
    }

    let model: String
    let temperature: Double
    let responseFormat: ResponseFormat
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case temperature
        case responseFormat = "response_format"
        case messages
    }
}

private struct OpenAIChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct OpenAIErrorResponse: Decodable {
    struct Payload: Decodable {
        let message: String
    }

    let error: Payload
}

private struct PlantExtractionPayload: Decodable {
    let englishName: String
    let frenchName: String
    let confidence: Double
    let wateringIntervalDays: Int
    let checkIntervalDays: Int
    let careHints: [String]

    enum CodingKeys: String, CodingKey {
        case englishName = "english_name"
        case frenchName = "french_name"
        case confidence
        case wateringIntervalDays = "watering_interval_days"
        case checkIntervalDays = "check_interval_days"
        case careHints = "care_hints"
    }
}

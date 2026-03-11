import XCTest
import Foundation
@testable import PlantKeeperApp
@testable import PlantKeeperCore

private final class URLProtocolStub: URLProtocol {
    static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct ConstantAnalyzer: PlantAnalyzing {
    let result: AIAnalysisResult
    func analyzePhotoData(_ data: Data) async throws -> AIAnalysisResult { result }
}

private func requestBodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let readCount = stream.read(&buffer, maxLength: buffer.count)
        guard readCount >= 0 else {
            return nil
        }
        if readCount == 0 {
            break
        }
        data.append(buffer, count: readCount)
    }
    return data
}

final class AIServiceTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testOnDeviceAnalyzerReturnsBaselinePayload() async throws {
        let analyzer = OnDevicePlantAnalyzer()

        let result = try await analyzer.analyzePhotoData(Data([0x11]))

        XCTAssertEqual(result.nameEnglish, "Unknown Plant")
        XCTAssertEqual(result.nameFrench, "Plante inconnue")
        XCTAssertEqual(result.suggestedWateringIntervalDays, 7)
        XCTAssertEqual(result.suggestedCheckIntervalDays, 3)
        XCTAssertEqual(result.identificationStatus, .placeholder)
    }

    func testCloudAnalyzerThrowsWhenKeyMissing() async {
        let analyzer = CloudPlantAnalyzer(keyStore: MockAPIKeyStore(loadedKey: nil))

        do {
            _ = try await analyzer.analyzePhotoData(Data([0x01]))
            XCTFail("Expected missing-key error.")
        } catch let error as AIServiceError {
            switch error {
            case .missingAPIKey:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCloudAnalyzerThrowsInvalidResponseForNonSuccessStatus() async {
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let analyzer = CloudPlantAnalyzer(
            keyStore: MockAPIKeyStore(loadedKey: "test-key"),
            urlSession: session
        )

        do {
            _ = try await analyzer.analyzePhotoData(Data([0x09]))
            XCTFail("Expected invalid-response error.")
        } catch let error as AIServiceError {
            switch error {
            case .invalidResponse:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCloudAnalyzerThrowsInvalidPayloadWhenContentMissing() async {
        let payload = #"{"choices":[{"message":{"content":null}}]}"#
        URLProtocolStub.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(payload.utf8))
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let analyzer = CloudPlantAnalyzer(
            keyStore: MockAPIKeyStore(loadedKey: "key"),
            urlSession: session
        )

        do {
            _ = try await analyzer.analyzePhotoData(Data([0x09]))
            XCTFail("Expected invalid-payload error.")
        } catch let error as AIServiceError {
            switch error {
            case .invalidPayload:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCloudAnalyzerParsesFencedJSONAndClampsValues() async throws {
        let completion = """
        {"choices":[{"message":{"content":"```json\\n{\\"english_name\\":\\"Mint\\",\\"french_name\\":\\"Menthe\\",\\"confidence\\":1.4,\\"watering_interval_days\\":0,\\"check_interval_days\\":-2,\\"care_hints\\":[\\"sun\\",\\"water\\"]}\\n```"}}]}
        """
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer api-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(completion.utf8))
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let analyzer = CloudPlantAnalyzer(
            keyStore: MockAPIKeyStore(loadedKey: "api-key"),
            model: "gpt-4.1-mini",
            urlSession: session
        )

        let result = try await analyzer.analyzePhotoData(Data([0xFF, 0xD8, 0xFF]))

        XCTAssertEqual(result.nameEnglish, "Mint")
        XCTAssertEqual(result.nameFrench, "Menthe")
        XCTAssertEqual(result.confidence, 1.0)
        XCTAssertEqual(result.suggestedWateringIntervalDays, 1)
        XCTAssertEqual(result.suggestedCheckIntervalDays, 1)
        XCTAssertEqual(result.careHints, ["sun", "water"])
    }

    func testCloudAnalyzerRequestAsksForSpecificCareIntervals() async throws {
        let completion = """
        {"choices":[{"message":{"content":"{\\"english_name\\":\\"Mint\\",\\"french_name\\":\\"Menthe\\",\\"confidence\\":0.8,\\"watering_interval_days\\":5,\\"check_interval_days\\":2,\\"care_hints\\":[\\"Bright indirect light\\"]}"}}]}
        """
        URLProtocolStub.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(from: request))
            let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))
            XCTAssertTrue(bodyString.contains("Do not use generic defaults like 7 unless the plant genuinely fits that cadence."))
            XCTAssertTrue(bodyString.contains("care_hints must be an array of short, practical tips specific to this plant."))

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(completion.utf8))
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let analyzer = CloudPlantAnalyzer(
            keyStore: MockAPIKeyStore(loadedKey: "api-key"),
            urlSession: session
        )

        _ = try await analyzer.analyzePhotoData(Data([0x01]))
    }

    func testCloudAnalyzerValidateAPIKeySucceedsForSuccessStatus() async throws {
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer valid-key")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"choices":[{"message":{"content":"{\"ok\":true}"}}]}"#.utf8))
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let analyzer = CloudPlantAnalyzer(
            keyStore: MockAPIKeyStore(loadedKey: nil),
            urlSession: session
        )

        try await analyzer.validateAPIKey(" valid-key ")
    }

    func testCloudAnalyzerValidateAPIKeyThrowsInvalidKeyForUnauthorizedStatus() async {
        URLProtocolStub.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"error":{"message":"Incorrect API key provided."}}"#.utf8))
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let analyzer = CloudPlantAnalyzer(
            keyStore: MockAPIKeyStore(loadedKey: nil),
            urlSession: session
        )

        do {
            try await analyzer.validateAPIKey("bad-key")
            XCTFail("Expected validation to fail.")
        } catch let error as OpenAIKeyValidationError {
            switch error {
            case .invalidKey:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHybridServiceReturnsOnDeviceWhenConfidenceHigh() async throws {
        let onDevice = ConstantAnalyzer(
            result: AIAnalysisResult(
                nameEnglish: "On-device",
                nameFrench: "On-device FR",
                confidence: 0.95,
                suggestedWateringIntervalDays: 5,
                suggestedCheckIntervalDays: 2,
                careHints: []
            )
        )
        let cloud = ConstantAnalyzer(
            result: AIAnalysisResult(
                nameEnglish: "Cloud",
                nameFrench: "Cloud FR",
                confidence: 0.99,
                suggestedWateringIntervalDays: 2,
                suggestedCheckIntervalDays: 1,
                careHints: []
            )
        )
        let service = HybridAIService(
            onDevice: onDevice,
            cloud: cloud,
            keyStore: MockAPIKeyStore(loadedKey: "key"),
            fallbackThreshold: 0.6
        )

        let result = try await service.analyzePhotoData(Data([0x01]))

        XCTAssertEqual(result.nameEnglish, "On-device")
    }

    func testHybridServiceReturnsOnDeviceWhenKeyMissing() async throws {
        let onDevice = ConstantAnalyzer(
            result: AIAnalysisResult(
                nameEnglish: "On-device",
                nameFrench: "On-device FR",
                confidence: 0.2,
                suggestedWateringIntervalDays: 5,
                suggestedCheckIntervalDays: 2,
                careHints: []
            )
        )
        let cloud = ConstantAnalyzer(
            result: AIAnalysisResult(
                nameEnglish: "Cloud",
                nameFrench: "Cloud FR",
                confidence: 0.99,
                suggestedWateringIntervalDays: 2,
                suggestedCheckIntervalDays: 1,
                careHints: []
            )
        )
        let service = HybridAIService(
            onDevice: onDevice,
            cloud: cloud,
            keyStore: MockAPIKeyStore(loadedKey: nil),
            fallbackThreshold: 0.6
        )

        let result = try await service.analyzePhotoData(Data([0x01]))

        XCTAssertEqual(result.nameEnglish, "On-device")
    }

    func testHybridServiceFallsBackToCloudWhenConfidenceLowAndKeyPresent() async throws {
        let onDevice = ConstantAnalyzer(
            result: AIAnalysisResult(
                nameEnglish: "On-device",
                nameFrench: "On-device FR",
                confidence: 0.2,
                suggestedWateringIntervalDays: 5,
                suggestedCheckIntervalDays: 2,
                careHints: []
            )
        )
        let cloud = ConstantAnalyzer(
            result: AIAnalysisResult(
                nameEnglish: "Cloud",
                nameFrench: "Cloud FR",
                confidence: 0.99,
                suggestedWateringIntervalDays: 2,
                suggestedCheckIntervalDays: 1,
                careHints: []
            )
        )
        let service = HybridAIService(
            onDevice: onDevice,
            cloud: cloud,
            keyStore: MockAPIKeyStore(loadedKey: "key"),
            fallbackThreshold: 0.6
        )

        let result = try await service.analyzePhotoData(Data([0x01]))

        XCTAssertEqual(result.nameEnglish, "Cloud")
    }

    func testAIServiceErrorsExposeMessages() {
        XCTAssertEqual(AIServiceError.missingAPIKey.errorDescription, "OpenAI API key is missing. Add it in Settings.")
        XCTAssertEqual(AIServiceError.invalidResponse.errorDescription, "AI service returned an invalid response.")
        XCTAssertEqual(AIServiceError.invalidPayload.errorDescription, "AI service returned an unreadable payload.")
        XCTAssertEqual(OpenAIKeyValidationError.emptyKey.errorDescription, "Enter an OpenAI API key first.")
        XCTAssertEqual(OpenAIKeyValidationError.invalidKey.errorDescription, "OpenAI rejected this API key. Check that it is correct.")
    }

}

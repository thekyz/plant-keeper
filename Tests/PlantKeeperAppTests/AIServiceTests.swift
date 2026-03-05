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
    }

}

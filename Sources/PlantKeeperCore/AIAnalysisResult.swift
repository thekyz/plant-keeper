import Foundation

public struct AIAnalysisResult: Equatable, Sendable {
    public var nameEnglish: String
    public var nameFrench: String
    public var confidence: Double
    public var suggestedWateringIntervalDays: Int
    public var suggestedCheckIntervalDays: Int
    public var careHints: [String]

    public init(
        nameEnglish: String,
        nameFrench: String,
        confidence: Double,
        suggestedWateringIntervalDays: Int,
        suggestedCheckIntervalDays: Int,
        careHints: [String]
    ) {
        self.nameEnglish = nameEnglish
        self.nameFrench = nameFrench
        self.confidence = confidence
        self.suggestedWateringIntervalDays = suggestedWateringIntervalDays
        self.suggestedCheckIntervalDays = suggestedCheckIntervalDays
        self.careHints = careHints
    }
}

public protocol PlantAnalyzing: Sendable {
    func analyzePhotoData(_ data: Data) async throws -> AIAnalysisResult
}

import Foundation

enum PlantPhotoStore {
    private static let photosDirectoryName = "PlantPhotos"

    static func savePhotoData(_ data: Data, for plantID: UUID) throws -> String {
        let fileName = "\(plantID.uuidString).jpg"
        let fileURL = try photosDirectoryURL().appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        return fileName
    }

    static func photoURL(for identifier: String?) -> URL? {
        guard let identifier, !identifier.isEmpty else { return nil }

        if identifier.hasPrefix("/") {
            return URL(fileURLWithPath: identifier)
        }

        guard let directoryURL = try? photosDirectoryURL() else {
            return nil
        }

        return directoryURL.appendingPathComponent(identifier)
    }

    private static func photosDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let photosDirectoryURL = appSupportURL.appendingPathComponent(photosDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: photosDirectoryURL.path) {
            try fileManager.createDirectory(at: photosDirectoryURL, withIntermediateDirectories: true)
        }
        return photosDirectoryURL
    }
}

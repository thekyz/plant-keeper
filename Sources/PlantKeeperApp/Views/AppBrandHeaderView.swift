import SwiftUI

#if os(iOS)
import UIKit
private typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
private typealias PlatformImage = NSImage
#endif

struct AppBrandHeaderView: View {
    private let logoImage: PlatformImage? = Self.loadLogoImage()

    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                if let logoImage {
                    platformImageView(logoImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 104, height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                Text("Plant Keeper")
                    .font(.title2.weight(.semibold))
            }
            .padding(.vertical, 12)
            Spacer()
        }
    }

    private static func loadLogoImage() -> PlatformImage? {
        let fileManager = FileManager.default
        let candidateURLs: [URL] = [
            Bundle.main.url(forResource: "logo", withExtension: "png"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("logo.png")
        ].compactMap { $0 }

        for url in candidateURLs where fileManager.fileExists(atPath: url.path) {
            if let image = PlatformImage(contentsOfFile: url.path) {
                return image
            }
        }

        return nil
    }

    @ViewBuilder
    private func platformImageView(_ image: PlatformImage) -> Image {
        #if os(iOS)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
        #endif
    }
}

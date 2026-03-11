import SwiftUI

#if os(iOS)
import UIKit
private typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
private typealias PlatformImage = NSImage
#endif

struct PlantRowView: View {
    let row: PlantRowViewModel
    let onWatered: () -> Void
    let onCheck: () -> Void
    let onSnooze: () -> Void
    let onAction: (OverflowAction) -> Void

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView

            VStack(alignment: .leading, spacing: 4) {
                Text(row.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text("Water: \(row.nextWaterText) | Check: \(row.nextCheckText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let careRecommendationSummary = row.careRecommendationSummary {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "leaf.circle.fill")
                            .foregroundStyle(.green)
                        Text(careRecommendationSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Text(row.urgencyBadge)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(row.urgency.isOverdue ? .red.opacity(0.18) : .green.opacity(0.18), in: Capsule())
            }

            Spacer()

            Button {
                onWatered()
            } label: {
                Image(systemName: "drop.fill")
                    .foregroundStyle(.blue)
                    .padding(8)
                    .background(.blue.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Mark watered")

            Button {
                onCheck()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .padding(8)
                    .background(.green.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Check plant")

            Button {
                onSnooze()
            } label: {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(.indigo)
                    .padding(8)
                    .background(.indigo.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Snooze watering for one day")

            Menu {
                ForEach(OverflowAction.allCases) { action in
                    Button(action.title, role: action == .delete ? .destructive : nil) {
                        onAction(action)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .padding(8)
            }
            .accessibilityLabel("More options")
        }
        .padding(.vertical, 4)
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack {
            if let image = thumbnailImage {
                platformImageView(image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.green.opacity(0.18), Color.teal.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "leaf.fill")
                    .font(.title3)
                    .foregroundStyle(.green.opacity(0.75))
            }
        }
        .frame(width: 54, height: 74)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.secondary.opacity(0.18), lineWidth: 0.5)
        )
    }

    private var thumbnailImage: PlatformImage? {
        guard
            let photoURL = PlantPhotoStore.photoURL(for: row.plant.photoIdentifier),
            FileManager.default.fileExists(atPath: photoURL.path)
        else {
            return nil
        }

        return PlatformImage(contentsOfFile: photoURL.path)
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

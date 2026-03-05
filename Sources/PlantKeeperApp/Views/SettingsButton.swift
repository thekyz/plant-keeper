import SwiftUI

struct SettingsButton: View {
    let action: () -> Void
    var compact: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(compact ? .system(size: 18, weight: .semibold) : .body)
                .frame(width: compact ? 36 : 44, height: compact ? 36 : 44)
                .background(
                    compact ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.clear),
                    in: Circle()
                )
        }
        .accessibilityLabel("Settings")
    }
}

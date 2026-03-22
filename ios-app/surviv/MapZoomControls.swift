import SwiftUI

struct MapZoomControls: View {
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            zoomButton(systemImage: "plus", label: "Zoom in", action: onZoomIn)
            zoomButton(systemImage: "minus", label: "Zoom out", action: onZoomOut)
        }
    }

    private func zoomButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(ProjectTheme.textPrimary)
                .frame(width: 40, height: 40)
                .background(Color(red: 0.07, green: 0.11, blue: 0.14).opacity(0.94), in: Circle())
                .overlay(
                    Circle().stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

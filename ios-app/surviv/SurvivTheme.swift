import SwiftUI

enum SurvivTheme {
    static let background = Color.black
    static let danger = Color.red
    static let safe = Color.green
    static let panel = Color.black.opacity(0.2)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.72)
}

enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}

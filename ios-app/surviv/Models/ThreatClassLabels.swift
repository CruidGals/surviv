import Foundation

/// Danger classifications used by Core ML inference and manual admin pins (keep in sync with the model).
enum ThreatClassLabels {
    static let all: [String] = [
        "Shooting", "Shelling", "Helicopter", "Fighter", "Vehicle", "Drone",
    ]

    static var set: Set<String> { Set(all) }
}

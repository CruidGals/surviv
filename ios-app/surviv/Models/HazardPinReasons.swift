import Foundation

/// Placeholder explanations until pins carry user-entered reasons.
enum HazardPinReasons {
    private static let dangerPool = [
        "Field report: unstable conditions; avoid until cleared.",
        "Localized hazard flagged by nearby responders.",
        "Temporary restriction due to observed risk in this zone.",
        "Community alert: use alternate paths when possible.",
        "Verification requested—stay clear pending update.",
    ]

    private static let safePool = [
        "Marked corridor verified for foot traffic during incident.",
        "Known safe passage from recent neighborhood coordination.",
        "Preferred route while avoiding adjacent hazard zones.",
        "Community-confirmed path; remain situationally aware.",
        "Staging area adjacent to cleared routes only.",
    ]

    static func arbitrary(for pinType: PinType, seed: UUID) -> String {
        var h = Hasher()
        h.combine(seed)
        let idx = abs(h.finalize())
        switch pinType {
        case .danger:
            return dangerPool[idx % dangerPool.count]
        case .safeRoute:
            return safePool[idx % safePool.count]
        }
    }
}

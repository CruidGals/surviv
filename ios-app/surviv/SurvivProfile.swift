import UIKit

enum SurvivProfile {
    static let displayNameAppStorageKey = "profile.displayName"

    /// Mesh / hazard attribution: profile name, or device name if unset.
    static var displayName: String {
        let s = UserDefaults.standard.string(forKey: displayNameAppStorageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? UIDevice.current.name : s
    }
}

import Foundation

/// The three classifications we care about from the 7-class MAD model.
/// Communication is non-threatening; Shooting and Shelling trigger danger pins.
enum ThreatClassLabels {
    /// Threat types shown in the admin manual-pin picker.
    static let all: [String] = ["Shooting", "Shelling"]

    /// All model classes whose probabilities we renormalize over at inference time.
    /// Includes the non-threat "Communication" so the denominator is meaningful.
    static let relevant: Set<String> = ["Communication", "Shooting", "Shelling"]

    /// Subset that actually constitutes a threat (triggers danger pins).
    static let threats: Set<String> = ["Shooting", "Shelling"]
}

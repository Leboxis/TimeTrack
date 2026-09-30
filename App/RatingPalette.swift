import SwiftUI
import WellbeingCore

/// One source of truth for the app's colours.
///
/// Two systems sit side by side on purpose, and mixing them would let a row contradict
/// itself:
///
/// - **What gets rated** carries the red-to-green ramp, so a session's quality reads at
///   a glance. The row stripe and the "Ressenti" chip use the same band, which is why
///   they can never disagree.
/// - **What names something** keeps a fixed identity hue: an orgasm score is always
///   indigo, a duration always teal. Rating one of them would be meaningless, since
///   they are already 1-to-5 summaries and two of them were purple and indigo before
///   the felt rating took over the ramp.
enum RatingPalette {
    /// Red at 1, warming through amber, green at 5.
    static func ramp(_ band: RatingBand) -> Color {
        switch band {
        case .lowest: Color(red: 0.84, green: 0.27, blue: 0.27)
        case .low: Color(red: 0.91, green: 0.53, blue: 0.20)
        case .middle: Color(red: 0.85, green: 0.70, blue: 0.29)
        case .high: Color(red: 0.36, green: 0.70, blue: 0.58)
        case .highest: Color(red: 0.19, green: 0.66, blue: 0.44)
        }
    }

    static func ramp(_ value: Int) -> Color { ramp(RatingBand(value: value)) }

    /// The same ramp, sampled at a lower opacity, for a large surface such as a stripe
    /// where the full-strength colour would shout.
    static func rampTint(_ value: Int) -> Color { ramp(value).opacity(0.85) }

    // Fixed identity hues. Orange repeats inside the ramp on purpose-free ground: the
    // ramp only ever appears on the stripe and the "Ressenti" chip, never here.
    static let duration = Color.teal
    static let orgasm = Color.indigo
    static let mental = Color.pink
    static let ejaculation = Color.orange
}

import SwiftUI
import UIKit
import WellbeingCore

/// The screen's hero: a quiet ring with the elapsed time in the middle.
///
/// The ring deliberately encodes no target. This app states outright that its charts
/// "ne fixent aucun objectif de durée ou de performance", so filling towards 24 hours
/// would contradict that, and a 60-second sweep would be a stopwatch lap carrying no
/// meaning either. It only breathes while the timer runs, which is enough to read the
/// state at a glance without inventing a goal.
struct TimerDial: View {
    let elapsed: TimeInterval
    let isRunning: Bool
    /// Set to false when the app is not frontmost: a repeating animation on a hidden tab
    /// is the same kind of waste as the periodic timeline it sits next to.
    var animates = true

    private let diameter: CGFloat = 240
    private let ringWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color(.systemGray5), lineWidth: ringWidth)

            Circle()
                .trim(from: 0, to: 1)
                .stroke(ringGradient, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: RatingPalette.duration.opacity(breathe ? 0.5 : 0), radius: breathe ? 12 : 0)
                .scaleEffect(breathe ? 1.012 : 1)
                .animation(breathe && animates
                           ? .easeInOut(duration: 1.9).repeatForever(autoreverses: true)
                           : .default,
                           value: breathe && animates)

            VStack(spacing: 6) {
                Text(durationLabel(elapsed))
                    .font(.system(size: 52, weight: .light, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.4).lineLimit(1)
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Durée : \(durationLabel(elapsed))")
        .accessibilityValue(status)
        .animation(.snappy(duration: 0.3), value: elapsed)
    }

    private var breathe: Bool { isRunning && animates }

    private var status: String {
        if isRunning { return "Séance en cours" }
        return elapsed > 0 ? "En pause" : "À votre rythme"
    }

    private var ringGradient: AngularGradient {
        AngularGradient(
            colors: [
                RatingPalette.duration.opacity(0.45),
                RatingPalette.duration,
                RatingPalette.duration.opacity(0.45),
            ],
            center: .center)
    }
}

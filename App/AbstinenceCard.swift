import SwiftUI
import WellbeingCore

/// Porn-free day counts. Deliberately independent of the period picker above it: a streak
/// is an absolute figure, and narrowing it to "the last 7 days" would hide the one number
/// this card exists to show.
struct AbstinenceCard: View {
    let sessions: [Session]

    private var result: Abstinence { abstinence(sessions: sessions) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Jours sans porno").font(.headline)

            if sessions.isEmpty {
                Text("Les jours sans porno apparaîtront après votre première séance.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    metric("Série en cours", "\(result.days) j", "clock")
                    metric("Record", "\(result.longest) j", "trophy")
                }
                band
                // The rate is measured over the sessions actually recorded, which is why
                // the sentence says so: a journal that predates the flag reads as clean.
                Text("\(result.relapses) rechute\(result.relapses > 1 ? "s" : "") · \(percentage) % de jours propres selon les séances cochées.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityLabel("\(result.relapses) rechute\(result.relapses > 1 ? "s" : ""), \(percentage) pour cent de jours propres selon les séances cochées.")
            }
        }
        .padding(16).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    private var percentage: Int { Int((result.cleanRate * 100).rounded()) }

    /// One square per day over the last 30 days, so a run of unrecorded days is visible as
    /// a run rather than being indistinguishable from a clean streak.
    private var band: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dirty = Set(sessions.filter(\.hasPorn).map { calendar.startOfDay(for: $0.date) })
        return HStack(spacing: 3) {
            ForEach(0..<30, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset - 29, to: today)!
                let clean = !dirty.contains(day)
                RoundedRectangle(cornerRadius: 2)
                    .fill(clean ? Color.teal.opacity(0.55) : Color.orange.opacity(0.75))
                    .frame(height: 18)
                    .accessibilityLabel(day.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue(clean ? "sans porno" : "avec porno")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trente derniers jours")
    }

    /// Same shape as the metrics already in `TrendsView`: caption, monospaced value, 16pt
    /// padding on the same tint.
    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }
}
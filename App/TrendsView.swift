import SwiftUI
import Charts
import WellbeingCore

struct TrendsView: View {
    @Environment(JournalStore.self) private var store
    @State private var days = 30

    private var sessions: [Session] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return store.sessions.filter { days == 0 || $0.date >= cutoff }.sorted { $0.date < $1.date }
    }
    private var average: Double {
        sessions.isEmpty ? 0 : sessions.reduce(0) { $0 + $1.duration } / Double(sessions.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Période", selection: $days) {
                        Text("7 jours").tag(7)
                        Text("30 jours").tag(30)
                        Text("Tout").tag(0)
                    }.pickerStyle(.segmented)
                    if sessions.isEmpty {
                        ContentUnavailableView("Votre histoire commence ici", systemImage: "chart.xyaxis.line",
                            description: Text("Les tendances apparaîtront après votre première séance."))
                    } else {
                        HStack(spacing: 12) {
                            metric("Séances", value: "\(sessions.count)", symbol: "calendar")
                            metric("Durée moyenne", value: durationLabel(average), symbol: "clock")
                        }
                        Text("Durées observées").font(.title3.bold())
                        Chart(sessions) { session in
                            LineMark(x: .value("Date", session.date), y: .value("Secondes", session.duration))
                                .foregroundStyle(.teal)
                            PointMark(x: .value("Date", session.date), y: .value("Secondes", session.duration))
                                .foregroundStyle(.teal)
                        }
                        .chartYScale(domain: 0...max(60, (sessions.map(\.duration).max() ?? 60) * 1.1))
                        .chartYAxisLabel("Secondes")
                        .frame(height: 230)
                        .accessibilityLabel("Durée de chaque séance en secondes")

                        Text("Ressenti au fil du temps").font(.title3.bold())
                        Chart(sessions) { session in
                            PointMark(x: .value("Date", session.date), y: .value("Ressenti", session.feeling))
                                .foregroundStyle(.purple)
                        }
                        .chartYScale(domain: 1...5)
                        .chartYAxis { AxisMarks(values: [1, 2, 3, 4, 5]) }
                        .frame(height: 170)
                        Text("Ces graphiques décrivent vos observations. Ils ne fixent aucun objectif de durée ou de performance.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }.navigationTitle("Tendances")
        }
    }

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }
}

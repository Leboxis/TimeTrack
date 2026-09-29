import SwiftUI
import Charts
import WellbeingCore

struct TrendsView: View {
    @Environment(JournalStore.self) private var store
    @State private var days = 30
    @State private var selectedID: UUID?
    @State private var editing: Session?

    private var sessions: [Session] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return store.sessions.filter { days == 0 || $0.date >= cutoff }.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
    }
    private var selected: Session? { sessions.first { $0.id == selectedID } }
    private var selectedIndex: Int? { sessions.firstIndex { $0.id == selectedID } }
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
                        Text("Touchez un graphique ou faites glisser le doigt pour explorer les séances.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        SessionChart(sessions: sessions, selectedID: $selectedID, metric: .duration)
                        selectionCard
                        SessionChart(sessions: sessions, selectedID: $selectedID, metric: .feeling)
                        Text("Ces graphiques décrivent vos observations. Ils ne fixent aucun objectif de durée ou de performance.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
            .navigationTitle("Tendances")
            .onChange(of: days) { _, _ in selectedID = nil }
            .onChange(of: sessions.map(\.id)) { _, ids in
                if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
            }
            .sheet(item: $editing) { session in
                SessionEditor(session: session) { store.save($0) }
            }
        }
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Séance sélectionnée").font(.headline)
                Spacer()
                if selected != nil {
                    Button { selectedID = nil } label: {
                        Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44)
                    }.accessibilityLabel("Effacer la sélection")
                }
            }
            if let selected {
                Text(selected.date, format: .dateTime.day().month(.wide).year().hour().minute())
                    .font(.subheadline.bold())
                HStack {
                    Label(durationLabel(selected.duration), systemImage: "clock")
                    Spacer()
                    Label("\(selected.feeling)/5", systemImage: "heart")
                }.foregroundStyle(.secondary)
                Text(selected.notes.isEmpty ? "Aucune note pour cette séance." : selected.notes)
                    .font(.subheadline).lineLimit(4)
                Button { editing = selected } label: {
                    Label("Ouvrir / modifier la séance", systemImage: "square.and.pencil")
                }.buttonStyle(.bordered)
            } else {
                Text("Choisissez un point ou utilisez les flèches ci-dessous.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack {
                Button { moveSelection(by: -1) } label: {
                    Label("Précédente", systemImage: "chevron.left").frame(minHeight: 44)
                }.disabled(selectedIndex == 0)
                Spacer()
                Text(selectedIndex.map { "\($0 + 1) / \(sessions.count)" } ?? "—")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button { moveSelection(by: 1) } label: {
                    Label("Suivante", systemImage: "chevron.right").frame(minHeight: 44)
                }.disabled(selectedIndex == sessions.count - 1)
            }
            .font(.subheadline)
        }
        .padding(16).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    private func moveSelection(by offset: Int) {
        guard !sessions.isEmpty else { return }
        let index = selectedIndex.map { min(sessions.count - 1, max(0, $0 + offset)) }
            ?? (offset < 0 ? sessions.count - 1 : 0)
        selectedID = sessions[index].id
    }

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }
}

private enum ChartMetric {
    case duration, feeling
    var title: String { self == .duration ? "Durées observées" : "Ressenti au fil du temps" }
    var axisLabel: String { self == .duration ? "Secondes" : "Ressenti sur 5" }
    var color: Color { self == .duration ? .teal : .purple }
    func value(_ session: Session) -> Double {
        self == .duration ? session.duration : Double(session.feeling)
    }
}

private struct SessionChart: View {
    let sessions: [Session]
    @Binding var selectedID: UUID?
    let metric: ChartMetric
    @State private var touchedDate: Date?

    private var selected: Session? { sessions.first { $0.id == selectedID } }
    private var domain: ClosedRange<Double> {
        metric == .duration ? 0...max(60, (sessions.map(\.duration).max() ?? 60) * 1.1) : 1...5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(metric.title).font(.title3.bold())
            Chart {
                ForEach(sessions) { session in
                    if metric == .duration {
                        LineMark(x: .value("Date", session.date), y: .value(metric.axisLabel, metric.value(session)))
                            .foregroundStyle(metric.color)
                    }
                    PointMark(x: .value("Date", session.date), y: .value(metric.axisLabel, metric.value(session)))
                        .foregroundStyle(metric.color)
                        .symbolSize(selectedID == session.id ? 140 : 35)
                        .accessibilityLabel(session.date.formatted(date: .abbreviated, time: .shortened))
                        .accessibilityValue(metric == .duration ? durationLabel(session.duration) : "\(session.feeling) sur 5")
                }
                if let selected {
                    RuleMark(x: .value("Sélection", selected.date))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .accessibilityHidden(true)
                }
            }
            .chartYScale(domain: domain)
            .chartYAxisLabel(metric.axisLabel)
            .chartXSelection(value: $touchedDate)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let anchor = proxy.plotFrame else { return }
                            let frame = geometry[anchor]
                            guard frame.contains(location),
                                  let date = proxy.value(atX: location.x - frame.minX, as: Date.self) else { return }
                            selectedID = nearestSession(to: date, in: sessions)?.id
                        }
                        .accessibilityHidden(true)
                }
            }
            .onChange(of: touchedDate) { _, date in
                // Keep the selection visible after the native drag gesture ends.
                if let date { selectedID = nearestSession(to: date, in: sessions)?.id }
            }
            .frame(height: metric == .duration ? 230 : 180)
            .accessibilityLabel(metric.title)
            .accessibilityHint("Les boutons Précédente et Suivante permettent aussi de consulter chaque séance.")
        }
    }
}

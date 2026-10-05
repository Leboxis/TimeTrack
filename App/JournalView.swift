import SwiftUI
import WellbeingCore

struct JournalView: View {
    @Environment(JournalStore.self) private var store
    @State private var editing: Session?
    @State private var deleting: Session?
    @State private var search = ""
    @State private var filterDay = false
    @State private var selectedDay = Date()

    private var filtered: [Session] {
        store.sessions.filter {
            (search.isEmpty || $0.notes.localizedStandardContains(search)) &&
            (!filterDay || Calendar.current.isDate($0.date, inSameDayAs: selectedDay))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Filtrer par jour", isOn: $filterDay)
                    if filterDay {
                        DatePicker("Jour", selection: $selectedDay, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                    }
                }
                if store.loadFailed {
                    LoadFailureNotice()
                }
                if filtered.isEmpty && !store.loadFailed {
                    ContentUnavailableView("Aucune séance", systemImage: "book.closed",
                        description: Text("Ajoutez une séance ou ajustez vos filtres."))
                }
                ForEach(filtered) { session in
                    Button { editing = session } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(session.date, format: .dateTime.day().month(.wide).year())
                                    .font(.headline).foregroundStyle(.primary)
                                Spacer()
                                Text(durationLabel(session.duration)).font(.headline.monospacedDigit())
                                    .foregroundStyle(RatingPalette.duration)
                            }
                            HStack {
                                Text(session.date, format: .dateTime.hour().minute())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                // Same band as the stripe and the "Ressenti" chip, so the
                                // three read as one signal rather than three.
                                Label("\(session.feeling)/5", systemImage: "heart.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(RatingPalette.ramp(session.feeling))
                            }
                            .font(.caption)
                            HStack(spacing: 6) {
                                // Same band as the stripe, so the row's colour and the
                                // rating it reports can never disagree.
                                chip("Ressenti \(session.feeling)/5", RatingPalette.ramp(session.feeling))
                                chip("Orgasme \(session.orgasm)/5", RatingPalette.orgasm)
                                chip("Mental \(session.mental)/5", RatingPalette.mental)
                                chip(session.ejaculation.label, RatingPalette.ejaculation)
                                // Only shown when true: a chip reading "Porno" on every row
                                // would train the eye to skip it.
                                if session.hasPorn {
                                    chip("Porno", RatingPalette.ejaculation)
                                }
                            }
                            if !session.notes.isEmpty {
                                Text(session.notes).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.leading, 16)
                        .background(alignment: .leading) {
                            Rectangle()
                                .fill(RatingPalette.rampTint(session.feeling))
                                .frame(width: 4)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    // Without this the row's label inherits the accent colour, which is
                    // what painted the whole journal blue and overrode every deliberate
                    // foreground inside it.
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Supprimer", role: .destructive) { deleting = session }
                    }
                    // The value stays in the text, so the colour never carries the
                    // rating on its own.
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilitySummary(session))
                }
            }
            .navigationTitle("Journal")
            .searchable(text: $search, prompt: "Rechercher dans les notes")
            .onChange(of: filterDay) { _, enabled in
                // Start from the most recent session so enabling the filter never
                // silently hides the whole history behind an empty day.
                if enabled, let latest = store.sessions.first { selectedDay = latest.date }
            }
            .toolbar {
                Button { editing = Session(duration: 60) } label: { Label("Ajouter", systemImage: "plus") }
                    .disabled(store.loadFailed)
            }
            .sheet(item: $editing) { session in
                SessionEditor(session: session, onSave: { store.save($0) }) {
                    store.delete(session.id)
                }
            }
            .alert("Supprimer cette séance ?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            )) {
                Button("Supprimer", role: .destructive) {
                    if let deleting { store.delete(deleting.id) }
                    deleting = nil
                }
                Button("Annuler", role: .cancel) { deleting = nil }
            } message: { Text("Cette action est définitive.") }
        }
    }

    /// Soft tint behind the label, semibold text, and a ring in the same hue.
    ///
    /// The ring is what makes these readable at a glance without inverting text against
    /// the fill: a saturated background with white text is the loud option, and it fails
    /// on the amber band of the ramp, where white does not reach the contrast ratio.
    /// A ring adds the presence and never inverts anything.
    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
            .overlay {
                Capsule().strokeBorder(color.opacity(0.55), lineWidth: 1.5)
            }
    }

    private func accessibilitySummary(_ session: Session) -> String {
        var parts = [
            session.date.formatted(date: .long, time: .shortened),
            durationLabel(session.duration),
            "ressenti \(session.feeling) sur 5",
            "orgasme \(session.orgasm) sur 5",
            "ressenti mental \(session.mental) sur 5",
            "type d'éjaculation : \(session.ejaculation.label)",
            session.hasPorn ? "avec porno" : "sans porno",
        ]
        if !session.notes.isEmpty { parts.append(session.notes) }
        return parts.joined(separator: ", ")
    }
}

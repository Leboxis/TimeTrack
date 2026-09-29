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
                                Text(durationLabel(session.duration)).font(.headline.monospacedDigit()).foregroundStyle(.teal)
                            }
                            HStack {
                                Text(session.date, format: .dateTime.hour().minute())
                                Spacer()
                                Label("\(session.feeling)/5", systemImage: "heart")
                            }.font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                chip("Ressenti \(session.feeling)/5")
                                chip("Orgasme \(session.orgasm)/5")
                                chip("Mental \(session.mental)/5")
                                chip(session.ejaculation.label)
                            }
                            if !session.notes.isEmpty {
                                Text(session.notes).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }.padding(.vertical, 6)
                    }
                    .swipeActions {
                        Button("Supprimer", role: .destructive) { deleting = session }
                    }
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

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color.teal.opacity(0.12), in: Capsule())
    }
}

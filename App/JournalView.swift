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
                if filtered.isEmpty {
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
                                Label("Ressenti \(session.feeling)/5", systemImage: "heart")
                            }.font(.caption).foregroundStyle(.secondary)
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
            .toolbar {
                Button { editing = Session(duration: 60) } label: { Label("Ajouter", systemImage: "plus") }
                    .disabled(store.loadFailed)
            }
            .sheet(item: $editing) { session in
                SessionEditor(session: session) { store.save($0) }
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
}

import SwiftUI

struct MethodDetailView: View {
    let method: PracticeMethod

    var body: some View {
        List {
            Section {
                Text(method.summary).font(.subheadline)
            }
            Section("Étapes") {
                ForEach(Array(method.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(.teal)
                            .frame(minWidth: 20, alignment: .trailing)
                        Text(step).font(.subheadline)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Étape \(index + 1). \(step)")
                }
            }
            if let cadence = method.cadence {
                Section("Rythme") {
                    Label {
                        Text(cadence).font(.subheadline)
                    } icon: {
                        Image(systemName: "calendar").foregroundStyle(.teal)
                    }
                }
            }
        }
        .navigationTitle(method.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

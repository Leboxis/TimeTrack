import SwiftUI

/// One 1-5 scale as a single button that opens the choices, so the editor stays short.
struct RatingRow: View {
    let title: String
    let labels: [String]
    @Binding var value: Int

    private var current: String {
        let index = min(max(value, 1), labels.count) - 1
        return "\(value)/5 · \(labels[index])"
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Menu {
                Picker(title, selection: $value) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                        Text("\(index + 1) · \(label)").tag(index + 1)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(current).monospacedDigit().foregroundStyle(.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
    }
}

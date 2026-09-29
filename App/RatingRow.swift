import SwiftUI

/// One 1-5 scale as a row of buttons. Used for every rating the editor collects.
struct RatingRow: View {
    let title: String
    let labels: [String]
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(min(max(value, 1), labels.count))/5")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            HStack(spacing: 8) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    let score = index + 1
                    Button {
                        value = score
                    } label: {
                        Text(label)
                            .font(.caption.weight(score <= value ? .semibold : .regular))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .background(score <= value ? Color.teal.opacity(0.18) : Color(.tertiarySystemFill),
                                in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(score <= value ? Color.primary : Color.secondary)
                    .accessibilityLabel("\(title) : \(label)")
                    .accessibilityAddTraits(score <= value ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
    }
}

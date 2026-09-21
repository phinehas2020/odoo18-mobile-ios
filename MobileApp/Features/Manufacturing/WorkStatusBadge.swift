import SwiftUI

struct WorkStatusBadge: View {
    let state: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Label(warehouseStateLabel(state), systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(color.opacity(contrast == .increased ? 0.24 : 0.12), in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4).padding(.vertical, 6)
            }
            .accessibilityLabel("Status: \(warehouseStateLabel(state))")
    }

    private var color: Color {
        switch state {
        case "ready", "assigned": return .teal
        case "progress": return .blue
        case "pending", "waiting": return .orange
        case "to_close": return .purple
        case "done": return .green
        case "blocked": return .red
        case "confirmed": return .indigo
        default: return .gray
        }
    }
    private var symbol: String {
        switch state {
        case "ready", "assigned": return "play.circle.fill"
        case "progress": return "gearshape.2.fill"
        case "pending", "waiting": return "clock.fill"
        case "to_close": return "checkmark.seal"
        case "done": return "checkmark.circle.fill"
        case "blocked": return "exclamationmark.octagon.fill"
        case "cancel": return "xmark.circle"
        case "confirmed": return "clipboard.fill"
        default: return "doc.text"
        }
    }
}

struct WorkDetailRow: View {
    let title: String
    let value: String
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        if textSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(.secondary)
                Text(value).fontWeight(.medium)
            }.accessibilityElement(children: .combine)
        } else {
            LabeledContent(title) { Text(value).foregroundStyle(.primary).multilineTextAlignment(.trailing) }
        }
    }
}

#Preview("Status language") {
    List {
        ForEach(["draft", "confirmed", "ready", "progress", "waiting", "pending", "to_close", "done", "cancel"], id: \.self) { state in
            WorkStatusBadge(state: state)
        }
    }
}

import SwiftUI

struct WorkStatusBadge: View {
    let state: String

    var body: some View {
        Label(title, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Status")
            .accessibilityValue(title)
    }

    private var title: String {
        switch state {
        case "pass", "passed": return "Passed"
        case "fail", "failed": return "Failed"
        case "none": return "Not checked"
        default: return warehouseStateLabel(state)
        }
    }

    private var color: Color {
        switch state {
        case "ready", "assigned", "confirmed", "to_close": return WorkplaceTheme.accent
        case "progress": return WorkplaceTheme.information
        case "pending", "waiting", "none": return WorkplaceTheme.attention
        case "done", "pass", "passed": return WorkplaceTheme.success
        case "blocked", "fail", "failed": return WorkplaceTheme.danger
        default: return .secondary
        }
    }
    private var symbol: String {
        switch state {
        case "ready", "assigned": return "play.circle.fill"
        case "progress": return "gearshape.2.fill"
        case "pending", "waiting": return "clock.fill"
        case "to_close": return "checkmark.seal"
        case "done", "pass", "passed": return "checkmark.circle.fill"
        case "blocked", "fail", "failed": return "exclamationmark.octagon.fill"
        case "none": return "checkmark.shield"
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
            }.padding(.vertical, 2).accessibilityElement(children: .combine)
        } else {
            LabeledContent(title) { Text(value).foregroundStyle(.primary).multilineTextAlignment(.trailing) }
        }
    }
}

#Preview("Status language") {
    List {
        ForEach(["draft", "confirmed", "ready", "progress", "waiting", "pending", "to_close", "done", "cancel", "passed", "failed"], id: \.self) { state in
            WorkStatusBadge(state: state)
        }
    }.workplaceScreen()
}

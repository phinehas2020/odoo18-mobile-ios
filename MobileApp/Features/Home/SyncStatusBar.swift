import SwiftUI

enum WorkplaceTheme {
    static let accent = adaptive(light: UIColor(red: 0.0, green: 0.30, blue: 0.70, alpha: 1),
                                 dark: UIColor(red: 0.45, green: 0.72, blue: 1, alpha: 1))
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let rule = Color(uiColor: .separator)
    static let buttonFill = Color(uiColor: UIColor(red: 0.0, green: 0.30, blue: 0.70, alpha: 1))
    static let dangerFill = Color(uiColor: UIColor { traits in
        traits.accessibilityContrast == .high
            ? UIColor(red: 0.52, green: 0.08, blue: 0.10, alpha: 1)
            : UIColor(red: 0.67, green: 0.13, blue: 0.15, alpha: 1)
    })
    static let success = adaptive(light: UIColor(red: 0.13, green: 0.42, blue: 0.25, alpha: 1),
                                  dark: UIColor(red: 0.48, green: 0.80, blue: 0.59, alpha: 1))
    static let attention = adaptive(light: UIColor(red: 0.54, green: 0.36, blue: 0.04, alpha: 1),
                                    dark: UIColor(red: 0.93, green: 0.76, blue: 0.40, alpha: 1))
    static let danger = adaptive(light: UIColor(red: 0.72, green: 0.14, blue: 0.16, alpha: 1),
                                 dark: UIColor(red: 1, green: 0.56, blue: 0.53, alpha: 1))
    static let information = accent

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let base = isDark ? dark : light
            guard traits.accessibilityContrast == .high else { return base }
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
            base.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            // Stronger foregrounds without changing the meaning of each color.
            if isDark {
                return UIColor(red: red + (1 - red) * 0.18,
                               green: green + (1 - green) * 0.18,
                               blue: blue + (1 - blue) * 0.18, alpha: alpha)
            }
            return UIColor(red: red * 0.76, green: green * 0.76, blue: blue * 0.76, alpha: alpha)
        })
    }
}

struct WorkplaceIcon: View {
    let symbol: String
    var tint: Color = WorkplaceTheme.accent
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 32
    var body: some View {
        Image(systemName: symbol)
            .font(.system(.body, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct WorkplaceHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if !textSize.isAccessibilitySize { WorkplaceIcon(symbol: symbol) }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
    }
}

struct WorkplaceActionLabel: View {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    var emphasized = false
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        HStack(spacing: 14) {
            if !textSize.isAccessibilitySize { WorkplaceIcon(symbol: symbol) }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body).foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }.padding(.vertical, 2).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

struct WorkplaceStatusPill: View {
    let text: String
    let symbol: String
    var tint: Color = WorkplaceTheme.accent
    var body: some View {
        Label(text, systemImage: symbol).font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore).accessibilityLabel(text)
    }
}

struct WorkplaceMetric: View {
    let title: String
    let value: String
    var symbol: String? = nil
    var tint: Color = WorkplaceTheme.accent
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(.title3, weight: .semibold)).monospacedDigit().foregroundStyle(tint)
            if let symbol { Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary) }
            else { Text(title).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title).accessibilityValue(value)
    }
}

struct WorkplaceNotice: View {
    let title: String
    let message: String
    let symbol: String
    var tint: Color = WorkplaceTheme.attention
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

extension View {
    func workplaceScreen() -> some View {
        background(WorkplaceTheme.canvas).tint(WorkplaceTheme.accent)
    }

    @ViewBuilder
    func workplaceBottomBar<Bar: View>(isPresented: Bool = true, @ViewBuilder content: () -> Bar) -> some View {
        if isPresented {
            safeAreaInset(edge: .bottom, spacing: 0) {
                content()
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.bar)
            }
        } else { self }
    }

    func workplaceProminentControl() -> some View {
        buttonStyle(.borderedProminent).tint(WorkplaceTheme.buttonFill).controlSize(.large)
    }

    func workplaceSecondaryControl() -> some View {
        buttonStyle(.bordered).controlSize(.large)
    }

}

struct SyncStatusBar: View {
    let lastSync: Date?
    let pending: Int
    let isOnline: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(isOnline ? "Connected" : "You’re offline", systemImage: isOnline ? "wifi" : "wifi.slash")
                .font(.subheadline.weight(.semibold))
            if pending > 0 {
                Text("\(pending) changes waiting to sync")
                    .font(.subheadline)
            }
            if !isOnline {
                Text("Reconnect to load the latest information.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if let lastSync {
                Text("Last synced \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background((isOnline ? WorkplaceTheme.accent : WorkplaceTheme.attention).opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct WorkplaceFilterButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(selected ? .semibold : .medium))
                .padding(.horizontal, 12).frame(minHeight: 44)
                .foregroundStyle(selected ? WorkplaceTheme.accent : Color.secondary)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(selected ? WorkplaceTheme.accent : .clear).frame(height: 2)
                }
        }.buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

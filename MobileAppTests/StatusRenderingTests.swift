import XCTest
import SwiftUI
@testable import MobileOdoo

final class StatusRenderingTests: XCTestCase {
    @MainActor
    func testSemanticColorsAndButtonLabelsRetainReadableContrast() {
        func channels(_ color: UIColor, _ traits: UITraitCollection) -> [Double] {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return [Double(red), Double(green), Double(blue)]
        }
        func luminance(_ values: [Double]) -> Double {
            let linear = values.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        func contrast(_ a: [Double], _ b: [Double]) -> Double {
            let x = luminance(a), y = luminance(b)
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }
        for style in [UIUserInterfaceStyle.light, .dark] {
            for accessibility in [UIAccessibilityContrast.normal, .high] {
                let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: style), UITraitCollection(accessibilityContrast: accessibility)])
                let background = channels(.secondarySystemGroupedBackground, traits)
                for color in [WorkplaceTheme.accent, WorkplaceTheme.success, WorkplaceTheme.attention, WorkplaceTheme.danger, WorkplaceTheme.information] {
                    let foreground = channels(UIColor(color), traits)
                    let opacity = accessibility == .high ? 0.22 : 0.11
                    let pill = zip(foreground, background).map { $0 * opacity + $1 * (1 - opacity) }
                    XCTAssertGreaterThanOrEqual(contrast(foreground, background), 4.5)
                    XCTAssertGreaterThanOrEqual(contrast(foreground, pill), 4.5)
                }
                for fill in [WorkplaceTheme.buttonFill, WorkplaceTheme.dangerFill] {
                    XCTAssertGreaterThanOrEqual(contrast([1, 1, 1], channels(UIColor(fill), traits)), 4.5)
                }
            }
        }
    }
    @MainActor
    func testStatusRendering() throws {
        for (name, scheme, size) in [("light", ColorScheme.light, DynamicTypeSize.large), ("dark", .dark, .large), ("large-text", .light, .accessibility3)] {
            let content = VStack(alignment: .leading, spacing: 16) {
                Text("Work status").font(.largeTitle.bold())
                Text("Know what needs to happen next.").foregroundStyle(.secondary)
                ForEach(["draft", "confirmed", "ready", "progress", "waiting", "to_close", "done"], id: \.self) { state in
                    WorkStatusBadge(state: state)
                }
                WorkDetailRow(title: "Employee", value: "Assigned operator")
                WorkDetailRow(title: "Expected time (h:mm)", value: "00:37")
            }
            .padding(24).frame(width: 393, alignment: .leading)
            .background(scheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, size)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let data = try XCTUnwrap(image.pngData())
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("odoo-status-\(name).png")
            try data.write(to: url)
            print("STATUS_PREVIEW \(url.path)")
        }
    }
}

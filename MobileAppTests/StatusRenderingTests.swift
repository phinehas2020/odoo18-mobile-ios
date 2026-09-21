import XCTest
import SwiftUI
@testable import MobileOdoo

final class StatusRenderingTests: XCTestCase {
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

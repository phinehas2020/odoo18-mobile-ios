import XCTest
import SwiftUI
@testable import MobileOdoo

final class QualityInstructionTests: XCTestCase {
    @MainActor
    func testOdooSOPMarkupBecomesReadableLinkedText() {
        let html = #"<div data-oe-version="1.2"><span class="o_file_box"><span class="o_file_image" title="Pre Production SOP.pdf"></span><span class="o_file_name_container"><a class="o_link_readonly" href="/web/content/1677?download=true&amp;access_token=fixture-token">Pre Production SOP.pdf</a></span></span></div>"#
        let result = QualityInstructionText.render(html, baseURL: URL(string: "https://example.com"))
        XCTAssertTrue(String(result.characters).contains("Pre Production SOP.pdf"))
        XCTAssertFalse(String(result.characters).contains("<div"))
        XCTAssertFalse(String(result.characters).contains("fixture-token"))
        let link = result.runs.compactMap { $0.link }.first
        XCTAssertEqual(link?.host, "example.com")
        XCTAssertEqual(link?.path, "/web/content/1677")
        XCTAssertTrue(link?.query?.contains("access_token=fixture-token") == true)
    }
    @MainActor
    func testFormattingEntitiesAndActiveContent() {
        let result = QualityInstructionText.render("<p><b>Clean &amp; inspect</b></p><script>alert('bad')</script><img src='https://invalid.example/private'><p>Then continue.</p>", baseURL: nil)
        let text = String(result.characters)
        XCTAssertTrue(text.contains("Clean & inspect"))
        XCTAssertTrue(text.contains("Then continue."))
        XCTAssertFalse(text.contains("alert"))
        XCTAssertFalse(text.contains("private"))
    }
    @MainActor
    func testPlainTextRemainsUnchanged() {
        XCTAssertEqual(String(QualityInstructionText.render("Clean equipment before starting.", baseURL: nil).characters), "Clean equipment before starting.")
    }
    @MainActor
    func testQualitySheetRendersReadableSOP() async throws {
        let config = EnvironmentConfig()
        let original = config.baseURL
        config.baseURL = URL(string: "https://example.com")
        defer { config.baseURL = original }
        let json = #"{"id":1,"name":"Batch sanitation.","state":"pending","control_type":"instructions","instructions":"<p>Read the sanitation procedure before starting this batch.</p><div><span class='o_file_box'><a href='/web/content/1677?download=true&amp;access_token=fixture-token'>Pre Production SOP.pdf</a></span></div>"}"#
        let check = try JSONDecoder().decode(ManufacturingQualityCheck.self, from: Data(json.utf8))
        let view = QualityCheckSheet(check: check) { _, _, _ in false }.environmentObject(config)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(800))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quality-sop-preview.png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("QUALITY_PREVIEW \(url.path)")
    }

}

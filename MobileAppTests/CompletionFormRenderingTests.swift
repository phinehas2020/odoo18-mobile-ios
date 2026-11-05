import XCTest
import SwiftUI
@testable import MobileOdoo

final class CompletionFormRenderingTests: XCTestCase {
    @MainActor
    func testReadyOrderPrefillsProducedQuantityWithoutSubmitting() async throws {
        let json = #"{"id":1027,"name":"MO/TEST","state":"to_close","product_name":"Test production","quantity":96,"product_tracking":"none","components":[{"id":1,"product_name":"Bulk ingredient","quantity":1333.44,"done_quantity":1333.44,"picked":true,"tracking":"none"},{"id":2,"product_name":"Packaging","quantity":96,"done_quantity":96,"picked":true,"tracking":"none"}],"workorders":[]}"#
        let detail = try JSONDecoder().decode(ManufacturingDetail.self, from: Data(json.utf8))
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/manufacturing/orders/1027/completion-review")
            let review = #"{"order_id":1027,"can_complete":true,"blockers":[],"warnings":[],"suggested_quantity":96,"quantity_remaining":96,"requires_finished_lot":false,"open_workorder_ids":[],"pending_quality_check_ids":[]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(review.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = APIClient(baseURL: URL(string: "https://example.com")!, authStore: AuthStore(), session: URLSession(configuration: config), errorStore: nil)
        let view = ManufacturingCompletionSheet(detail: detail) { _ in XCTFail("Opening a review must not submit"); return false }
            .environmentObject(APIClientProvider(client: client))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(900))
        host.view.layoutIfNeeded()
        func fields(_ view: UIView) -> [UITextField] {
            (view as? UITextField).map { [$0] } ?? view.subviews.flatMap(fields)
        }
        let produced = try XCTUnwrap(fields(host.view).first { $0.placeholder == "Quantity produced" })
        XCTAssertEqual(produced.text, "96")
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("production-completion-review.png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("COMPLETION_PREVIEW \(url.path)")
    }
}

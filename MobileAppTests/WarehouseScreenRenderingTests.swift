import XCTest
import SwiftUI
@testable import MobileOdoo

final class WarehouseScreenRenderingTests: XCTestCase {
    @MainActor
    func testManufacturingScreenRendersServerDetails() async throws {
        let json = #"{"id":1,"name":"MO/DEMO/001","state":"progress","product_name":"Stoneground Whole Wheat Flour","quantity":24,"uom_name":"Bags","is_planned":true,"components":[{"id":3,"product_id":6,"product_name":"Whole wheat grain","quantity":48,"done_quantity":12,"tracking":"lot","uom_name":"lb"}],"workorders":[{"id":2,"name":"Mill, fill and label","state":"progress","workcenter_name":"Production","product_name":"2 lb Whole Wheat Flour","employee_name":"Warehouse operator","quantity_remaining":18,"expected_duration_minutes":37,"real_duration_minutes":12,"is_user_working":true}],"quality_checks":[{"id":7,"name":"Check package weight","state":"pending","control_type":"passfail","instructions":"Weigh one filled bag before packing."}]}"#
        var requests = 0
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            requests += 1
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = APIClient(baseURL: URL(string: "https://example.com")!, authStore: AuthStore(), session: URLSession(configuration: config), errorStore: nil)
        let view = NavigationStack { ManufacturingDetailView(orderId: 1, workOrdersFirst: true) }
            .environmentObject(APIClientProvider(client: client))
            .environmentObject(NetworkMonitor())
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertGreaterThan(requests, 0)
        host.view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("warehouse-manufacturing-screen.png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("WAREHOUSE_SCREEN \(url.path)")
    }
}

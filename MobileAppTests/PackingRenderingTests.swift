import XCTest
import SwiftUI
@testable import MobileOdoo

final class PackingRenderingTests: XCTestCase {
    @MainActor
    func testDiscountCardRendering() async throws {
        try await render(name: "discount-card-first", phase: .partial, customerCount: 1)
        try await render(name: "discount-card-repeat", phase: .partial, color: .dark, customerCount: 15)
        try await render(name: "discount-card-unknown", phase: .partial, size: .accessibility3)
    }

    private enum Phase: Equatable {
        case pick, partial, allPicked, boxPacked, orderReady, trackingPending, legacy, review, mapping, assignedElsewhere, preview
    }

    @MainActor
    func testPackingChecklistAndReviewRenderAtAccessibleSizes() async throws {
        for (name, size, color, phase) in [
            ("packing-checklist-light", DynamicTypeSize.large, ColorScheme.light, Phase.partial),
            ("packing-checklist-dark", .large, .dark, .partial),
            ("packing-review-accessibility", .accessibility3, .light, .review),
            ("packing-checklist-accessibility5", .accessibility5, .light, .partial),
            ("packing-high-contrast-dark", .large, .dark, .partial)
        ] {
            try await render(name: name, phase: phase, size: size, color: color)
        }
    }

    @MainActor
    func testPackingNextActionsRenderWithoutWrites() async throws {
        for (name, phase) in [
            ("packing-pick", Phase.pick),
            ("packing-all-picked", .allPicked),
            ("packing-box-packed", .boxPacked),
            ("packing-order-ready", .orderReady),
            ("packing-tracking-pending", .trackingPending),
            ("packing-previous-workflow", .legacy),
            ("packing-supervisor-review", .review),
            ("packing-mapping-review", .mapping),
            ("packing-assigned-elsewhere", .assignedElsewhere),
            ("packing-preview-only", .preview)
        ] {
            try await render(name: name, phase: phase)
        }
        try await render(name: "packing-all-picked-accessibility5", phase: .allPicked, size: .accessibility5)
    }

    func testPackingOutcomeCopySeparatesBoxOrderAndHistoricalLabel() throws {
        let box = try JSONDecoder().decode(PackingDetail.self, from: fixture(.boxPacked))
        XCTAssertEqual(box.statusTitle, "Box packed")
        XCTAssertTrue(box.statusExplanation.contains("1 of 2 boxes packed"))
        let ready = try JSONDecoder().decode(PackingDetail.self, from: fixture(.orderReady))
        XCTAssertEqual(ready.statusTitle, "Shipped")
        XCTAssertTrue(ready.statusExplanation.contains("order is shipped"))
        XCTAssertFalse(ready.statusExplanation.contains("remaining boxes"))
        let legacy = try JSONDecoder().decode(PackingDetail.self, from: fixture(.legacy))
        XCTAssertFalse(legacy.canEdit)
        XCTAssertFalse(legacy.canFinish)
        XCTAssertTrue(legacy.statusExplanation.contains("previous workflow"))
        XCTAssertFalse(legacy.statusExplanation.contains("activated"))
        let review = try JSONDecoder().decode(PackingDetail.self, from: fixture(.review))
        XCTAssertTrue(review.needsReview)
        XCTAssertFalse(review.canFinish)
        XCTAssertEqual(review.statusExplanation, "Delivery needs a lot number. Ask a supervisor before shipping.")
    }

    @MainActor
    private func render(name: String, phase: Phase, size: DynamicTypeSize = .large, color: ColorScheme = .light, customerCount: Int? = nil) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = APIClient(baseURL: URL(string: "https://example.com")!, authStore: AuthStore(), session: URLSession(configuration: configuration), errorStore: nil)
        defer { MockURLProtocol.requestHandler = nil }
        var detailJSON = try JSONSerialization.jsonObject(with: fixture(phase)) as! [String: Any]
        if let customerCount { detailJSON["customer_order_count"] = customerCount }
        let detailData = try JSONSerialization.data(withJSONObject: detailJSON)
        let capabilities = phase == .preview
            ? Data(#"{"enabled":true,"business_enabled":false,"can_pack":true,"can_supervise":false,"requires_online":true,"workflow_version":"packing_v1"}"#.utf8)
            : PackingWorkflowTests.capabilities
        var requests: [String] = []
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET", "Opening a packing screen must not confirm quantities or finish a box.")
            XCTAssertEqual(request.url?.host, "example.com")
            requests.append("\(request.httpMethod ?? "") \(request.url!.path)")
            let data = request.url!.path.hasSuffix("capabilities") ? capabilities : detailData
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let model = PackingViewModel(recoveryStore: PackingRecoveryStore(defaults: UserDefaults(suiteName: UUID().uuidString)!), deviceId: "render-test-device")
        let view = NavigationStack { PackingView(shipmentId: 42, model: model) }
            .environmentObject(APIClientProvider(client: client))
            .environmentObject(NetworkMonitor())
            .environmentObject(AuthStore())
            .environment(\.dynamicTypeSize, size)
            .environment(\.colorScheme, color)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: view)
        if name.contains("high-contrast") { host.traitOverrides.accessibilityContrast = .high }
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for _ in 0..<50 {
            if model.detail != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(model.detail?.shipmentId, 42)
        XCTAssertEqual(model.detail?.items.count, 3)
        XCTAssertEqual(model.canFinish, phase == .allPicked)
        if phase == .preview || phase == .legacy || phase == .assignedElsewhere || phase == .review || phase == .mapping {
            XCTAssertFalse(model.canEdit)
            XCTAssertFalse(model.canFinish)
        }
        host.view.layoutIfNeeded()
        func resetScroll(_ view: UIView) {
            if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height {
                scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
            }
            view.subviews.forEach(resetScroll)
        }
        resetScroll(host.view)
        try await Task.sleep(for: .milliseconds(100))
        try capture(window: window, name: name)
        if size == .accessibility5 {
            func scrollToProducts(_ view: UIView) {
                if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height {
                    let maximum = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                    let target = min(maximum, max(0, scroll.bounds.height * 0.85))
                    scroll.setContentOffset(CGPoint(x: 0, y: target), animated: false)
                }
                view.subviews.forEach(scrollToProducts)
            }
            scrollToProducts(host.view)
            try await Task.sleep(for: .milliseconds(100))
            try capture(window: window, name: name + "-products")
        }
        XCTAssertEqual(requests, ["GET /api/v1/shopify/packing/capabilities", "GET /api/v1/shopify/packing/42"])
    }

    @MainActor
    private func capture(window: UIWindow, name: String) throws {
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let data = try XCTUnwrap(image.pngData())
        XCTAssertGreaterThan(data.count, 1_000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
        try data.write(to: url)
        print("PACKING_SCREEN \(url.path)")
    }

    private func fixture(_ phase: Phase) throws -> Data {
        let allPicked = [Phase.allPicked, .boxPacked, .orderReady, .trackingPending, .review].contains(phase)
        let packed = [Phase.boxPacked, .orderReady, .trackingPending, .review].contains(phase)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: PackingWorkflowTests.fixture()) as? [String: Any])
        json["packing_state"] = packed ? "packed" : "in_progress"
        json["operational_state"] = phase == .review ? "review" : [Phase.orderReady, .trackingPending, .legacy].contains(phase) ? "complete" : "pending"
        json["order_state"] = phase == .orderReady ? "shipped" : "ready_to_ship"
        json["sync_state"] = [Phase.orderReady, .legacy].contains(phase) ? "synced" : phase == .trackingPending ? "pending" : "not_ready"
        json["workflow_version"] = phase == .legacy ? "legacy_print" : "packing_v1"
        let writable = !packed && phase != .legacy && phase != .assignedElsewhere && phase != .mapping
        json["allowed_actions"] = ["claim": false, "edit": writable, "complete": writable]
        if phase == .review { json["review_reason"] = "Delivery needs a lot number. Ask a supervisor before shipping." }
        if phase == .mapping {
            json["packing_state"] = "unstarted"
            json["review_reason"] = "SKU 276 does not have one valid physical product mapping."
        }
        json["items"] = [
            ["line_id": 12, "title": "Stoneground yellow cornmeal", "variant_title": "2 lb bag", "sku": "CORN-2", "required_quantity": 3.0,
             "confirmed_quantity": allPicked ? 3.0 : phase == .partial ? 1.0 : 0.0, "remaining_quantity": allPicked ? 0.0 : phase == .partial ? 2.0 : 3.0],
            ["line_id": 13, "title": "Whole wheat flour", "variant_title": "5 lb bag", "sku": "WHEAT-5", "required_quantity": 2.0,
             "confirmed_quantity": allPicked || phase == .partial ? 2.0 : 0.0, "remaining_quantity": allPicked || phase == .partial ? 0.0 : 2.0],
            ["line_id": 14, "title": "Pancake mix", "variant_title": "1 lb bag", "sku": "PANCAKE-1", "required_quantity": 1.0,
             "confirmed_quantity": allPicked ? 1.0 : 0.0, "remaining_quantity": allPicked ? 0.0 : 1.0]
        ]
        json["siblings"] = [
            ["shipment_id": 42, "box_number": 1, "packing_state": packed ? "packed" : "in_progress"],
            ["shipment_id": 43, "box_number": 2, "packing_state": [Phase.orderReady, .trackingPending].contains(phase) ? "packed" : "unstarted"]
        ]
        return try JSONSerialization.data(withJSONObject: json)
    }
}

import XCTest
import SwiftUI
@testable import MobileOdoo

final class WorkspaceUXRenderingTests: XCTestCase {
    @MainActor
    private func capture<V: View>(_ view: V, name: String, size: CGSize? = nil, scrollToBottom: Bool = false, increasedContrast: Bool = false) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        if let size { window.frame = CGRect(origin: .zero, size: size) }
        let host = UIHostingController(rootView: view)
        if increasedContrast { host.traitOverrides.accessibilityContrast = .high }
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(800))
        host.view.layoutIfNeeded()
        func resetScroll(_ view: UIView) {
            if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height {
                let offset = scrollToBottom ? scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom : -scroll.adjustedContentInset.top
                scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            }
            view.subviews.forEach(resetScroll)
        }
        resetScroll(host.view)
        try await Task.sleep(for: .milliseconds(200))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ux-\(name).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("UX_SCREEN \(url.path)")
    }

    @MainActor
    func testAdminWorkOverviewRenders() async throws {
        let auth = AuthStore()
        auth.setSession(accessToken: "fixture", refreshToken: "fixture", user: UserProfile(id: 2, name: "Admin", login: "admin", email: nil, companyId: 1, allowedCompanyIds: [1], groupIds: [], isAdmin: true), companies: [])
        defer { auth.clear(); MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, AdminWorkOverviewTests.fixture)
        }
        for (name, scheme, size) in [("admin-overview", ColorScheme.light, DynamicTypeSize.large), ("admin-overview-dark", .dark, .large), ("admin-overview-large", .light, .accessibility3)] {
            let view = NavigationStack { AdminWorkOverview() }.environmentObject(provider()).environmentObject(auth).environmentObject(NetworkMonitor()).environment(\.scenePhase, .active).environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
            try await capture(view, name: name)
        }
    }

    @MainActor
    private func provider() -> APIClientProvider {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return APIClientProvider(client: APIClient(baseURL: URL(string: "https://example.com")!, authStore: AuthStore(), session: URLSession(configuration: config), errorStore: nil))
    }

    @MainActor
    func testPackingStartRendersWithoutOpeningCameraOrWriting() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/shopify/packing/capabilities")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, PackingWorkflowTests.capabilities)
        }
        defer { MockURLProtocol.requestHandler = nil }
        let view = NavigationStack { PackingView() }.environmentObject(provider())
            .environmentObject(AuthStore()).environmentObject(NetworkMonitor())
        try await capture(view, name: "packing-start")
        try await capture(view.environment(\.dynamicTypeSize, .accessibility3), name: "packing-start-large")
    }

    @MainActor
    func testWorkspaceNavigationRenders() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let menu = #"{"items":[{"key":"inventory","label":"Inventory","native":true},{"key":"manufacturing","label":"Manufacturing","native":true},{"key":"packing","label":"Pack orders","native":true},{"key":"sales","label":"Sales","native":true}]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data((request.url?.path == "/api/v1/manufacturing/orders" ? #"[{"id":1,"name":"MO/00535","state":"progress","product_name":"Stoneground Whole Wheat Flour","quantity":24,"uom_name":"Bags","assigned_user_name":"You"},{"id":2,"name":"MO/00546","state":"confirmed","product_name":"Sorghum Maple Pecan Granola","quantity":3,"uom_name":"Batches","assigned_user_name":"You"},{"id":3,"name":"MO/00550","state":"draft","product_name":"Whole Rye Flour","quantity":48,"uom_name":"Bags","assigned_user_name":"You"}]"# : menu).utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }
        for tab in ["work", "warehouse", "more"] {
            let view = HomeView(initialTab: tab).environmentObject(provider()).environmentObject(AppState()).environmentObject(AuthStore()).environmentObject(SyncEngine()).environmentObject(NetworkMonitor())
            try await capture(view, name: tab)
        }
        for (name, scheme, size) in [("work-dark", ColorScheme.dark, DynamicTypeSize.large), ("work-large-text", .light, .accessibility3)] {
            let view = HomeView(initialTab: "work").environmentObject(provider()).environmentObject(AppState()).environmentObject(AuthStore()).environmentObject(SyncEngine()).environmentObject(NetworkMonitor())
                .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
            try await capture(view, name: name)
        }
        let accessibleWork = HomeView(initialTab: "work").environmentObject(provider()).environmentObject(AppState()).environmentObject(AuthStore()).environmentObject(SyncEngine()).environmentObject(NetworkMonitor())
            .environment(\.dynamicTypeSize, .accessibility5)
        try await capture(accessibleWork, name: "work-accessibility5", increasedContrast: true)
        let compactWork = HomeView(initialTab: "work").environmentObject(provider()).environmentObject(AppState()).environmentObject(AuthStore()).environmentObject(SyncEngine()).environmentObject(NetworkMonitor())
        try await capture(compactWork, name: "work-compact", size: CGSize(width: 320, height: 568))
    }

    @MainActor
    func testAccountAndSalesSurfacesRender() async throws {
        let api = provider()
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let json = #"[{"id":27,"name":"SO/02718","partner_name":"Prairie Farm Store","state":"sale","amount_total":428.50,"currency_id":1,"date_order":"2026-10-05T09:30:00Z"},{"id":28,"name":"SO/02719","partner_name":"Homestead Kitchen","state":"draft","amount_total":96,"currency_id":1,"date_order":"2026-10-05T10:15:00Z"}]"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }
        try await capture(NavigationStack { SalesView() }.environmentObject(api), name: "sales")
        try await capture(NavigationStack { SettingsView() }
            .environmentObject(AuthStore()).environmentObject(EnvironmentConfig()).environmentObject(SyncEngine()), name: "settings")
        try await capture(LoginView().environmentObject(AuthStore()).environmentObject(EnvironmentConfig()), name: "login")
        try await capture(LoginView().environmentObject(AuthStore()).environmentObject(EnvironmentConfig())
            .environment(\.colorScheme, .dark), name: "login-dark")
        try await capture(LoginView().environmentObject(AuthStore()).environmentObject(EnvironmentConfig())
            .environment(\.dynamicTypeSize, .accessibility5), name: "login-accessibility5")
    }

    @MainActor
    func testReceiptRendersInLightAndDark() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let json = #"{"id":42,"name":"WH/IN/0042","state":"assigned","picking_type_code":"incoming","partner_name":"Prairie Grain Supply","source_location":{"id":1,"name":"Vendor"},"dest_location":{"id":2,"name":"Main warehouse"},"record_version":"v2","lines":[{"id":3,"move_id":4,"product_id":5,"product_name":"Organic whole wheat","qty_done":6,"qty_reserved":0,"qty_demanded":10,"uom_name":"Bags","tracking":"none"}],"moves":[{"id":4,"product_id":5,"product_name":"Organic whole wheat","qty_done":6,"qty_demanded":10,"uom_name":"Bags","tracking":"none"}]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }
        for (name, scheme) in [("receipt-light", ColorScheme.light), ("receipt-dark", .dark)] {
            let view = NavigationStack { InventoryDetailView(pickingId: 42) }
                .environmentObject(provider()).environmentObject(SyncEngine()).environmentObject(NetworkMonitor()).environment(\.colorScheme, scheme)
            try await capture(view, name: name)
        }
    }

    @MainActor
    func testScannerControlsAdaptWithoutStartingTheCamera() async throws {
        for (name, size, type) in [("scanner-accessibility5", CGSize(width: 393, height: 852), DynamicTypeSize.accessibility5),
                                  ("scanner-landscape", CGSize(width: 844, height: 390), .large)] {
            let view = PackingLabelScanner(isFinishing: false,
                                           onScan: { _ in XCTFail("Rendering must not submit a tracking label"); return false }, message: { nil },
                                           previewCameraState: .unavailable,
                                           previewFailure: "This label could not be matched to the current box. Check the printed tracking number or ask a supervisor to review the order before trying again.")
                .environment(\.dynamicTypeSize, type)
            try await capture(view, name: name, size: size)
            try await capture(view, name: name + "-controls", size: size, scrollToBottom: true)
            let product = BarcodeScannerView(previewCameraState: .unavailable) { _ in
                XCTFail("Rendering must not submit a product scan"); return false
            }.environment(\.dynamicTypeSize, type)
            try await capture(product, name: "product-" + name, size: size)
        }
    }
}

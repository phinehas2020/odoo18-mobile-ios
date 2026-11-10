import XCTest
import SwiftUI
@testable import MobileOdoo

final class HomePulseTests: XCTestCase {
    static let fulfillment = Data(##"{"generated_at":"2026-11-10T18:55:00Z","total":18,"ready":12,"needs_review":2,"pickup":4,"orders":[{"id":1,"order_name":"#47012","customer_name":"Preview customer","created_at":"2026-11-09T14:30:00Z","state":"ready_to_ship","total_items":4,"requested_shipping_method":"Ground"}]}"##.utf8)
    static let production = Data(##"{"generated_at":"2026-11-10T18:55:00Z","total_orders":8,"truncated":false,"orders":[{"id":41,"name":"MO/00535","product":"Stoneground Whole Wheat Flour","quantity":24,"uom":"Bags","status":"running","responsible":"Milling team","overdue":false,"completed_steps":1,"total_steps":3,"operations":[{"id":81,"name":"Milling & bagging","status":"running","state":"progress","workcenter":"Mill","expected_minutes":40,"recorded_minutes":12,"operators":[]}]},{"id":42,"name":"MO/00546","product":"Sorghum Maple Pecan Granola","quantity":3,"uom":"Batches","status":"ready","responsible":"Production team","overdue":false,"completed_steps":0,"total_steps":2,"operations":[]},{"id":43,"name":"MO/00550","product":"Whole Rye Flour","quantity":48,"uom":"Bags","status":"blocked","responsible":"Milling team","overdue":true,"completed_steps":0,"total_steps":2,"operations":[]}]}"##.utf8)
    static let todos = Data(##"{"items":[{"id":1,"name":"Check packaging supplies","state":"01_in_progress","done":false},{"id":2,"name":"Review this week’s production plan","state":"01_in_progress","done":false},{"id":3,"name":"Count flour bags","state":"01_in_progress","done":false}],"stages":[],"truncated":false}"##.utf8)
    static let menu = Data(##"{"items":[{"key":"packing","label":"Pack orders","native":true},{"key":"shopify_fulfillment","label":"Fulfillment"},{"key":"manufacturing","label":"Manufacturing","native":true},{"key":"inventory","label":"Inventory","native":true},{"key":"project_todo","label":"To-do"}]}"##.utf8)

    @MainActor private func client() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return APIClient(baseURL: URL(string: "https://example.com")!, authStore: AuthStore(), session: URLSession(configuration: config), errorStore: nil)
    }
    private func stub(status: Int = 200) {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET", "Home must never perform a business mutation")
            let data: Data
            switch request.url?.path {
            case "/api/v1/shopify/orders/unfulfilled": data = Self.fulfillment
            case "/api/v1/manufacturing/overview": data = Self.production
            case "/api/v1/manufacturing/orders": data = Data("[]".utf8)
            case "/api/v1/todo/tasks": data = Self.todos
            case "/api/v1/menu": data = Self.menu
            default: data = Data("{}".utf8)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, data)
        }
    }
    override func tearDown() { MockURLProtocol.requestHandler = nil; super.tearDown() }

    @MainActor func testWholeQueueCountIsNotVisibleRowCount() async {
        stub()
        let model = HomePulseModel()
        await model.refresh(client: client(), fulfillment: true, manufacturing: true, todo: true, admin: true)
        XCTAssertEqual(model.fulfillment.value?.total, 18)
        XCTAssertEqual(model.fulfillment.value?.orders.count, 1)
        XCTAssertEqual(model.production.value?.total, 8)
        XCTAssertEqual(model.production.value?.running, 1)
        XCTAssertEqual(model.production.value?.attention, 1)
        XCTAssertEqual(model.todos.value?.items.count, 3)
    }

    @MainActor func testFailureRetainsLastValuesAndMarksThemStale() async {
        stub()
        let model = HomePulseModel(), api = client()
        await model.loadFulfillment(client: api)
        let receivedAt = model.fulfillment.updatedAt
        stub(status: 503)
        await model.loadFulfillment(client: api)
        XCTAssertEqual(model.fulfillment.value?.total, 18)
        XCTAssertEqual(model.fulfillment.updatedAt, receivedAt)
        XCTAssertNotNil(model.fulfillment.error)
        XCTAssertFalse(model.fulfillment.isLoading)
    }

    @MainActor func testPermissionLossClearsSensitiveSnapshot() async {
        stub()
        let model = HomePulseModel(), api = client()
        await model.loadFulfillment(client: api)
        stub(status: 403)
        await model.loadFulfillment(client: api)
        XCTAssertNil(model.fulfillment.value)
        XCTAssertNil(model.fulfillment.updatedAt)
        XCTAssertNotNil(model.fulfillment.error)
    }

    @MainActor func testMissingEndpointDoesNotBecomeZero() async {
        stub(status: 404)
        let model = HomePulseModel()
        await model.loadFulfillment(client: client())
        XCTAssertNil(model.fulfillment.value)
        XCTAssertTrue(model.fulfillment.error?.contains("server update") == true)
    }

    @MainActor func testHiddenModulesDoNotMakeRequests() async {
        MockURLProtocol.requestHandler = { _ in XCTFail("Hidden modules must not load"); throw URLError(.unsupportedURL) }
        await HomePulseModel().refresh(client: client(), fulfillment: false, manufacturing: false, todo: false, admin: false)
    }

    @MainActor func testStaffUseAssignedProductionRatherThanAdminOverview() async {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/manufacturing/orders")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("[]".utf8))
        }
        let model = HomePulseModel()
        await model.refresh(client: client(), fulfillment: false, manufacturing: true, todo: false, admin: false)
        XCTAssertEqual(model.production.value?.total, 0)
    }

    @MainActor func testIndependentSectionsSurviveFulfillmentFailure() async {
        MockURLProtocol.requestHandler = { request in
            let fulfillment = request.url?.path.contains("unfulfilled") == true
            return (HTTPURLResponse(url: request.url!, statusCode: fulfillment ? 503 : 200, httpVersion: nil, headerFields: nil)!, fulfillment ? Data() : Self.production)
        }
        let model = HomePulseModel()
        await model.refresh(client: client(), fulfillment: true, manufacturing: true, todo: false, admin: true)
        XCTAssertNotNil(model.fulfillment.error)
        XCTAssertNotNil(model.production.value)
        XCTAssertNil(model.production.error)
    }


    @MainActor func testRefreshRecoversAndClearsError() async {
        stub(status: 503)
        let model = HomePulseModel(), api = client()
        await model.loadFulfillment(client: api)
        stub()
        await model.loadFulfillment(client: api)
        XCTAssertEqual(model.fulfillment.value?.total, 18)
        XCTAssertNil(model.fulfillment.error)
        XCTAssertNotNil(model.fulfillment.updatedAt)
    }

    @MainActor func testQueuePaginationAdvancesByServerRowsDespiteOverlap() async {
        var offsets: [Int] = []
        MockURLProtocol.requestHandler = { request in
            let offset = Int(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "offset" }!.value!)!
            offsets.append(offset)
            let body = ##"{"generated_at":"2026-11-10T18:55:00Z","total":2,"ready":2,"needs_review":0,"pickup":0,"orders":[{"id":1,"order_name":"#47012","total_items":4}]}"##
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let model = UnfulfilledOrdersModel(), api = client()
        await model.load(client: api)
        XCTAssertTrue(model.hasMore)
        await model.load(client: api, nextPage: true)
        XCTAssertEqual(offsets, [0, 1])
        XCTAssertEqual(model.snapshot?.orders.count, 1)
        XCTAssertFalse(model.hasMore)
    }

    @MainActor func testZeroQueueRendersAsARealEmptyState() async throws {
        MockURLProtocol.requestHandler = { request in
            let data = Data(##"{"generated_at":"2026-11-10T18:55:00Z","total":0,"ready":0,"needs_review":0,"pickup":0,"orders":[]}"##.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let model = HomePulseModel()
        await model.loadFulfillment(client: client())
        XCTAssertEqual(model.fulfillment.value?.total, 0)
        XCTAssertNil(model.fulfillment.error)
        let view = NavigationStack { UnfulfilledOrdersView() }
            .environmentObject(APIClientProvider(client: client())).environmentObject(NetworkMonitor())
        try await capture(view, name: "queue-empty", width: 393)
    }

    @MainActor func testQueueAndUnavailableServerRender() async throws {
        stub()
        let view = NavigationStack { UnfulfilledOrdersView() }
            .environmentObject(APIClientProvider(client: client())).environmentObject(NetworkMonitor())
        try await capture(view, name: "queue-orders", width: 393)
        stub(status: 404)
        try await capture(view.id("missing-server"), name: "queue-unavailable", width: 393)
    }

    @MainActor func testHomeRendering() async throws {
        stub()
        let auth = AuthStore()
        auth.setSession(accessToken: "fixture", refreshToken: "fixture", user: UserProfile(id: 2, name: "Preview", login: "preview", email: nil, companyId: 1, allowedCompanyIds: [1], groupIds: [], isAdmin: true), companies: [])
        defer { auth.clear() }
        let provider = APIClientProvider(client: client())
        for (name, scheme, type, width) in [
            ("home-light", ColorScheme.light, DynamicTypeSize.large, 393.0),
            ("home-dark", .dark, .large, 393.0),
            ("home-accessibility", .light, .accessibility3, 393.0),
            ("home-compact", .light, .large, 320.0)
        ] {
            let view = HomeView().environmentObject(auth).environmentObject(provider).environmentObject(AppState())
                .environmentObject(SyncEngine()).environmentObject(NetworkMonitor())
                .environment(\.scenePhase, .active).environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, type)
            try await capture(view, name: name, width: width)
            if name == "home-light" || name == "home-accessibility" {
                try await capture(view, name: name + "-bottom", width: width, scrollToBottom: true)
            }
        }
    }

    @MainActor private func capture<V: View>(_ view: V, name: String, width: CGFloat, scrollToBottom: Bool = false) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 852)
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .seconds(2))
        host.view.layoutIfNeeded()
        if scrollToBottom {
            func scroll(_ view: UIView) {
                if let content = view as? UIScrollView, content.contentSize.height > content.bounds.height {
                    content.setContentOffset(CGPoint(x: 0, y: content.contentSize.height - content.bounds.height + content.adjustedContentInset.bottom), animated: false)
                }
                view.subviews.forEach(scroll)
            }
            scroll(host.view)
            try await Task.sleep(for: .milliseconds(200))
        }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("HOME_SCREEN \(url.path)")
        let attachment = XCTAttachment(image: image)
        attachment.name = name + " — sample data"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

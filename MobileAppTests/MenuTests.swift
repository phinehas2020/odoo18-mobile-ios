import XCTest
@testable import MobileOdoo

final class MenuTests: XCTestCase {
    @MainActor
    func testSavedConnectionIsReadyBeforeFirstScreenLoads() {
        let name = "startup-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("https://example.com", forKey: "server_url")
        let config = EnvironmentConfig(defaults: defaults)
        let provider = APIClientProvider(config: config, authStore: AuthStore())
        XCTAssertNotNil(provider.client, "Cold launch must not wait for another run-loop callback")
    }

    @MainActor
    func testConnectionChangesAreImmediateAndDuplicateValuesKeepClient() {
        let name = "startup-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let config = EnvironmentConfig(defaults: defaults)
        let provider = APIClientProvider(config: config, authStore: AuthStore())
        XCTAssertNil(provider.client)
        config.baseURL = URL(string: "https://example.com")!
        let first = provider.client
        XCTAssertNotNil(first)
        config.baseURL = URL(string: "https://example.com")!
        XCTAssertTrue(provider.client === first, "Repeated login settings must not replace an in-flight connection")
        config.baseURL = URL(string: "https://other.example.com")!
        XCTAssertNotNil(provider.client)
        XCTAssertFalse(provider.client === first)
        config.baseURL = nil
        XCTAssertNil(provider.client)
    }

    func testSharedModuleKeysHaveDistinctStableIdentities() throws {
        let data = Data(#"{"items":[{"key":"base","label":"Contacts","web_url":"https://example.com/web#action=1"},{"key":"base","label":"Settings","web_url":"https://example.com/web#action=2"}]}"#.utf8)
        let first = try JSONDecoder().decode(MenuResponse.self, from: data).items
        let second = try JSONDecoder().decode(MenuResponse.self, from: data).items
        XCTAssertNotEqual(first[0].id, first[1].id)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.map(\.key), ["base", "base"])
    }

    @MainActor
    func testMenuPreservesDistinctDestinationsAndRemovesExactDuplicates() async {
        defer { MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { request in
            let data = Data(#"{"items":[{"key":"base","label":"Contacts","web_url":"https://example.com/web#action=1"},{"key":"base","label":"Settings","web_url":"https://example.com/web#action=2"},{"key":"base","label":"Contacts","web_url":"https://example.com/web#action=1"},{"key":"hidden","label":"Hidden","enabled":false}]}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = APIClient(baseURL: URL(string: "https://example.com")!, authStore: AuthStore(), session: URLSession(configuration: configuration), errorStore: nil)
        let model = MenuViewModel()
        await model.load(apiClient: client)
        XCTAssertEqual(model.items.map(\.label), ["Contacts", "Settings"])
        XCTAssertEqual(Set(model.items.map(\.id)).count, model.items.count)
    }

    @MainActor
    private func feedbackClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return APIClient(baseURL: URL(string: "https://example.com")!, authStore: AuthStore(),
                         session: URLSession(configuration: configuration), errorStore: nil)
    }

    @MainActor
    func testFailedSalesNoteKeepsDraftAndReportsFailure() async {
        defer { MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.host, "example.com")
            XCTAssertEqual(request.url?.path, "/api/v1/sales/orders/27/note")
            let body = try PackingWorkflowTests.body(request)
            XCTAssertEqual(body["note"] as? String, "Keep this test order together.")
            XCTAssertEqual(body.count, 1)
            throw URLError(.timedOut)
        }
        let model = SalesOrderDetailViewModel()
        model.noteText = "Keep this test order together."
        await model.addNote(apiClient: feedbackClient(), orderId: 27)
        XCTAssertEqual(model.noteText, "Keep this test order together.")
        XCTAssertNotNil(model.noteErrorMessage)
        XCTAssertFalse(model.noteSaved)
        XCTAssertFalse(model.isSavingNote)
    }

    @MainActor
    func testSuccessfulSalesNoteClearsDraftAndReportsSaved() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/sales/orders/27/note")
            let body = try PackingWorkflowTests.body(request)
            XCTAssertEqual(body["note"] as? String, "  Test note with original spacing.  ")
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }
        let model = SalesOrderDetailViewModel()
        model.noteText = "  Test note with original spacing.  "
        await model.addNote(apiClient: feedbackClient(), orderId: 27)
        XCTAssertEqual(model.noteText, "")
        XCTAssertTrue(model.noteSaved)
        XCTAssertNil(model.noteErrorMessage)
        XCTAssertFalse(model.isSavingNote)
        model.updateNoteDraft("Another draft")
        XCTAssertFalse(model.noteSaved)
    }

    @MainActor
    func testConcurrentSalesNoteTapsSendOnlyOneRequest() async {
        defer { MockURLProtocol.requestHandler = nil }
        let requestStarted = expectation(description: "First note is waiting for the server")
        let releaseResponse = DispatchSemaphore(value: 0)
        var requests = 0
        MockURLProtocol.requestHandler = { request in
            requests += 1
            requestStarted.fulfill()
            _ = releaseResponse.wait(timeout: .now() + 3)
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }
        let model = SalesOrderDetailViewModel()
        model.noteText = "A single note for this test order."
        let client = feedbackClient()
        let firstSave = Task { await model.addNote(apiClient: client, orderId: 27) }
        await fulfillment(of: [requestStarted], timeout: 2)
        XCTAssertTrue(model.isSavingNote)
        await model.addNote(apiClient: client, orderId: 27)
        releaseResponse.signal()
        await firstSave.value
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(model.noteSaved)
        XCTAssertFalse(model.isSavingNote)
    }

    @MainActor
    func testCustomerLookupDistinguishesFailureFromEmptyAndRecovers() async {
        defer { MockURLProtocol.requestHandler = nil }
        let model = CustomerSearchViewModel()
        model.query = "Example Customer"
        let client = feedbackClient()
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/sales/customers")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(query?.first(where: { $0.name == "search" })?.value, "Example Customer")
            throw URLError(.notConnectedToInternet)
        }
        await model.search(apiClient: client)
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isSearching)

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("[]".utf8))
        }
        await model.search(apiClient: client)
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.resultsQuery, "Example Customer")
        XCTAssertFalse(model.isSearching)
    }

    @MainActor
    func testFailedCustomerRefreshKeepsPriorResultsAndTheirQuery() async {
        defer { MockURLProtocol.requestHandler = nil }
        let model = CustomerSearchViewModel()
        let client = feedbackClient()
        model.query = "Example"
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"[{"id":7,"name":"Example Customer","email":"test@example.com"}]"#.utf8))
        }
        await model.search(apiClient: client)
        XCTAssertEqual(model.results.map(\.id), [7])
        XCTAssertEqual(model.resultsQuery, "Example")

        model.query = "Another name"
        MockURLProtocol.requestHandler = { _ in throw URLError(.timedOut) }
        await model.search(apiClient: client)
        XCTAssertEqual(model.results.map(\.id), [7])
        XCTAssertEqual(model.resultsQuery, "Example")
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isSearching)
    }
}

final class AdminWorkOverviewTests: XCTestCase {
    static let fixture = Data(#"{"generated_at":"2026-10-09T12:00:00Z","total_orders":2,"truncated":false,"orders":[{"id":1,"name":"MO/00541","product":"Stoneground Whole Wheat Flour","quantity":24,"uom":"Bags","responsible":"Samuel Lancaster","status":"running","overdue":false,"completed_steps":1,"total_steps":3,"operations":[{"id":11,"name":"Mill wheat","status":"running","state":"progress","workcenter":"Stone mill","expected_minutes":40,"recorded_minutes":22,"operators":[{"id":"user-7","name":"Samuel Lancaster","recorded_minutes":22,"running_minutes":12,"running_since":"2026-10-09T11:48:00Z"}]}]},{"id":2,"name":"MO/00542","product":"Yellow Cornmeal","quantity":40,"uom":"Bags","responsible":"Joe Holifield","status":"paused","overdue":true,"completed_steps":0,"total_steps":2,"operations":[{"id":12,"name":"Pack cornmeal","status":"paused","state":"progress","workcenter":"Packing table","expected_minutes":25,"recorded_minutes":8,"operators":[{"id":"user-13","name":"Joe Holifield","recorded_minutes":8,"running_minutes":0,"running_since":null}]}]}]}"#.utf8)

    func testLiveSessionAdvancesButStaleAndPausedDoNot() throws {
        let value = try DateCoding.decoder.decode(AdminWorkSnapshot.self, from: Self.fixture)
        let received = Date()
        let active = value.orders[0].operations[0].operators[0]
        XCTAssertEqual(active.elapsedMinutes(since: received, now: received.addingTimeInterval(120), fresh: true), 14)
        XCTAssertEqual(active.elapsedMinutes(since: received, now: received.addingTimeInterval(120), fresh: false), 12)
        let paused = value.orders[1].operations[0].operators[0]
        XCTAssertEqual(paused.elapsedMinutes(since: received, now: received.addingTimeInterval(120), fresh: true), 0)
    }

    @MainActor
    func testNonAdminNeverRequestsOverview() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://example.com")!, authStore: AuthStore(), session: URLSession(configuration: configuration), errorStore: nil)
        MockURLProtocol.requestHandler = { _ in XCTFail("Employee must never request the admin overview"); throw URLError(.badURL) }
        defer { MockURLProtocol.requestHandler = nil }
        let model = AdminWorkOverviewModel()
        await model.load(client: api, isAdmin: false)
        XCTAssertNil(model.snapshot)
    }

    @MainActor
    func testRevokedAdminAccessClearsPreviouslyLoadedData() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://example.com")!, authStore: AuthStore(), session: URLSession(configuration: configuration), errorStore: nil)
        defer { MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/manufacturing/overview")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Self.fixture)
        }
        let model = AdminWorkOverviewModel()
        await model.load(client: api, isAdmin: true)
        XCTAssertEqual(model.snapshot?.orders.count, 2)
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, Data(#"{"detail":"Admin access required"}"#.utf8))
        }
        await model.load(client: api, isAdmin: true)
        XCTAssertNil(model.snapshot)
        XCTAssertNotNil(model.error)
    }
}

import XCTest
import GRDB
@testable import MobileOdoo

final class DiagnosticsTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    @MainActor
    private func setupClient() throws -> (APIClient, ApiErrorStore) {
        let db = try DatabaseQueue()
        try db.write { db in
            try db.execute(sql: "CREATE TABLE api_errors (id INTEGER PRIMARY KEY, endpoint TEXT, log_url TEXT, message TEXT, created_at DATETIME)")
        }
        let store = ApiErrorStore(dbQueue: db)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = APIClient(baseURL: URL(string: "https://example.com")!, authStore: AuthStore(), session: URLSession(configuration: config), errorStore: store)
        return (client, store)
    }

    @MainActor
    func testDecodingFailureRecordsFieldAndStatusWithoutResponseValues() async throws {
        let (client, store) = try setupClient()
        MockURLProtocol.requestHandler = { request in
            XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Mobile-Request-ID"))
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"[{"id":"PRIVATE_VALUE","name":"SECRET_CUSTOMER"}]"#.utf8))
        }
        do {
            let _: [PickingListItem] = try await client.send(Endpoint(path: "/api/v1/inventory/pickings", method: "GET", queryItems: [URLQueryItem(name: "token", value: "SECRET_QUERY")]))
            XCTFail("Expected decoding failure")
        } catch {
            XCTAssertTrue(APIClient.failureMessage(error).contains("$[0].id"))
        }
        let report = store.diagnosticReport()
        XCTAssertTrue(report.contains("HTTP=200"))
        XCTAssertTrue(report.contains("$[0].id"))
        XCTAssertTrue(report.contains("duration_ms="))
        XCTAssertFalse(report.contains("PRIVATE_VALUE"))
        XCTAssertFalse(report.contains("SECRET_CUSTOMER"))
        XCTAssertFalse(report.contains("SECRET_QUERY"))
    }

    @MainActor
    func testNoResponseHTTPFailureIsRecordedWithoutBody() async throws {
        let (client, store) = try setupClient()
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data("SECRET_SERVER_BODY".utf8))
        }
        do {
            try await client.sendNoResponse(Endpoint(path: "/api/v1/devices", method: "POST"))
            XCTFail("Expected HTTP error")
        } catch APIError.httpStatus(let code) { XCTAssertEqual(code, 503) }
        XCTAssertTrue(store.diagnosticReport().contains("HTTP=503"))
        XCTAssertFalse(store.diagnosticReport().contains("SECRET_SERVER_BODY"))
    }

    @MainActor
    func testConnectionFailureIsRecordedAndShownOnRefresh() async throws {
        let (client, store) = try setupClient()
        MockURLProtocol.requestHandler = { _ in throw URLError(.timedOut) }
        let model = InventoryViewModel()
        await model.load(apiClient: client)
        XCTAssertTrue(model.errorMessage?.contains("timed out") == true)
        XCTAssertTrue(store.diagnosticReport().contains("HTTP=none"))
        XCTAssertTrue(store.diagnosticReport().contains("-1001"))
    }
}

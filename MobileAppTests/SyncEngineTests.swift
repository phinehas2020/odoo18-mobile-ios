import XCTest
import GRDB
@testable import MobileOdoo

final class SyncEngineTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testRefreshUpdatesCursorAndMarksOutbox() async throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO outbox_actions (event_id, type, payload, created_at, status) VALUES (?, ?, ?, ?, ?)",
                arguments: ["event-1", "inventory.scan", "{}", Date(), "pending"]
            )
        }

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                throw NSError(domain: "MockURLProtocol", code: 0)
            }
            let responseData: Data
            let statusCode: Int
            switch url.path {
            case "/api/v1/sync/changes":
                responseData = #"{"cursor":5,"changes":[]}"#.data(using: .utf8) ?? Data()
                statusCode = 200
            case "/api/v1/sync/push":
                responseData = #"{"results":[{"event_id":"event-1","status":"success"}]}"#.data(using: .utf8) ?? Data()
                statusCode = 200
            default:
                responseData = Data()
                statusCode = 404
            }
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, responseData)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let authStore = AuthStore()
        authStore.clear()
        let client = APIClient(
            baseURL: URL(string: "https://example.com")!,
            authStore: authStore,
            session: session,
            errorStore: nil
        )
        let syncEngine = SyncEngine(apiClient: client, dbQueue: dbQueue)

        await syncEngine.refresh()

        let cursor = try dbQueue.read { db -> Int in
            try Int.fetchOne(db, sql: "SELECT cursor FROM sync_state WHERE id = 1") ?? 0
        }
        let pendingCount = try dbQueue.read { db -> Int in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outbox_actions WHERE status != 'success'") ?? 0
        }

        XCTAssertEqual(cursor, 5)
        XCTAssertEqual(pendingCount, 0)
        XCTAssertEqual(syncEngine.pendingOutboxCount, 0)
        XCTAssertNotNil(syncEngine.lastSync)
    }

    private func makeDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try db.create(table: "sync_state") { t in
                t.column("id", .integer).primaryKey()
                t.column("cursor", .integer).notNull().defaults(to: 0)
                t.column("last_sync_at", .datetime)
            }
            try db.create(table: "outbox_actions") { t in
                t.column("event_id", .text).primaryKey()
                t.column("type", .text).notNull()
                t.column("payload", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("status", .text).notNull().defaults(to: "pending")
            }
            try db.create(table: "api_errors") { t in
                t.column("id", .integer).primaryKey()
                t.column("endpoint", .text).notNull()
                t.column("log_url", .text)
                t.column("message", .text)
                t.column("created_at", .datetime).notNull()
            }
        }
        return dbQueue
    }
}

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockURLProtocol", code: 1))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

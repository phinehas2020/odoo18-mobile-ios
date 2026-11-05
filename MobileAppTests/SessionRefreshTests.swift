import XCTest
@testable import MobileOdoo

/// Production logs showed two refreshes racing with the same rotating refresh token,
/// followed by a failed refresh and a forced sign-in, whenever several screens loaded together.
final class SessionRefreshTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: Int] = [:]
        func bump(_ key: String) { lock.lock(); values[key, default: 0] += 1; lock.unlock() }
        func value(_ key: String) -> Int { lock.lock(); defer { lock.unlock() }; return values[key, default: 0] }
    }

    private static let tokens = Data(#"""
    {"access_token":"new-access","refresh_token":"new-refresh","expires_in":900,
     "user":{"id":7,"name":"Samuel","login":"samuel","email":null,"company_id":1,"allowed_company_ids":[1],"group_ids":[],"is_admin":false},
     "companies":[{"id":1,"name":"Homestead Gristmill","currency_id":2}]}
    """#.utf8)

    @MainActor
    private func signedIn() -> AuthStore {
        let auth = AuthStore()
        auth.setSession(accessToken: "old-access", refreshToken: "old-refresh",
                        user: UserProfile(id: 7, name: "Samuel", login: "samuel", email: nil, companyId: 1, allowedCompanyIds: [1], groupIds: [], isAdmin: false),
                        companies: [])
        return auth
    }

    @MainActor
    private func client(_ auth: AuthStore) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return APIClient(baseURL: URL(string: "https://example.com")!, authStore: auth, session: URLSession(configuration: config), errorStore: nil)
    }

    private func respond(_ status: Int, _ body: Data, _ request: URLRequest) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, body)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    @MainActor
    func testScreensLoadingTogetherShareOneRefresh() async throws {
        let auth = signedIn()
        defer { auth.clear() }
        let counter = Counter()
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/v1/auth/refresh" {
                counter.bump("refresh")
                Thread.sleep(forTimeInterval: 0.3)   // widen the race window
                return self.respond(200, Self.tokens, request)
            }
            let bearer = request.value(forHTTPHeaderField: "Authorization")
            if bearer == "Bearer new-access" { counter.bump("ok"); return self.respond(200, Data("[]".utf8), request) }
            return self.respond(401, Data(), request)
        }
        let api = client(auth)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for path in ["/api/v1/menu", "/api/v1/todo/tasks", "/api/v1/manufacturing/orders", "/api/v1/sales/orders"] {
                group.addTask { try await api.sendNoResponse(Endpoint(path: path, method: "GET")) }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(counter.value("refresh"), 1, "Only one refresh may use the rotating refresh token")
        XCTAssertEqual(counter.value("ok"), 4, "Every screen retries with the new token")
        XCTAssertEqual(auth.accessToken, "new-access")
        XCTAssertEqual(auth.refreshToken, "new-refresh")
    }

    @MainActor
    func testRequestAfterAnotherRefreshRetriesWithoutRefreshingAgain() async throws {
        let auth = signedIn()
        defer { auth.clear() }
        let counter = Counter()
        let user = try XCTUnwrap(auth.user)
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/v1/auth/refresh" { counter.bump("refresh"); return self.respond(200, Self.tokens, request) }
            let bearer = request.value(forHTTPHeaderField: "Authorization")
            if bearer == "Bearer new-access" { return self.respond(200, Data("[]".utf8), request) }
            // Simulates a response that arrives after another request already refreshed.
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    auth.setSession(accessToken: "new-access", refreshToken: "new-refresh", user: user, companies: [])
                }
            }
            return self.respond(401, Data(), request)
        }
        try await client(auth).sendNoResponse(Endpoint(path: "/api/v1/menu", method: "GET"))
        XCTAssertEqual(counter.value("refresh"), 0, "A token that was already replaced must not trigger another rotation")
    }

    @MainActor
    func testDroppedConnectionDuringRefreshKeepsTheSession() async {
        let auth = signedIn()
        defer { auth.clear() }
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/v1/auth/refresh" { throw URLError(.networkConnectionLost) }
            return self.respond(401, Data(), request)
        }
        do {
            try await client(auth).sendNoResponse(Endpoint(path: "/api/v1/menu", method: "GET"))
            XCTFail("Expected the request to fail")
        } catch {}
        XCTAssertEqual(auth.accessToken, "old-access", "Bad Wi-Fi must not sign employees out")
        XCTAssertEqual(auth.refreshToken, "old-refresh")
    }

    @MainActor
    func testServerErrorDuringRefreshKeepsTheSession() async {
        let auth = signedIn()
        defer { auth.clear() }
        MockURLProtocol.requestHandler = { request in
            self.respond(request.url?.path == "/api/v1/auth/refresh" ? 502 : 401, Data(), request)
        }
        do { try await client(auth).sendNoResponse(Endpoint(path: "/api/v1/menu", method: "GET")); XCTFail("Expected failure") } catch {}
        XCTAssertNotNil(auth.refreshToken)
    }

    @MainActor
    func testRevokedRefreshTokenSignsOut() async {
        let auth = signedIn()
        defer { auth.clear() }
        MockURLProtocol.requestHandler = { request in self.respond(401, Data(), request) }
        do { try await client(auth).sendNoResponse(Endpoint(path: "/api/v1/menu", method: "GET")); XCTFail("Expected failure") } catch {}
        XCTAssertNil(auth.accessToken, "A refresh token the server rejects means the session is really over")
    }

    @MainActor
    func testSessionSurvivesRelaunch() {
        let auth = signedIn()
        defer { auth.clear() }
        let relaunched = AuthStore()
        XCTAssertEqual(relaunched.refreshToken, "old-refresh")
        XCTAssertEqual(relaunched.user?.id, 7)
    }
}

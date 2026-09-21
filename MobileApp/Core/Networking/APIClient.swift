import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case rejected(Int, String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response (not HTTP)"
        case .httpStatus(let code): return "Server error (HTTP \(code))"
        case .rejected(_, let message): return message
        }
    }
}

final class APIClient {
    private let baseURL: URL
    private let authStore: AuthStore
    private let deviceStore = DeviceStore.shared
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let errorStore: ApiErrorStore?

    private var refreshTask: Task<String, Error>?

    init(baseURL: URL, authStore: AuthStore, session: URLSession = .shared, errorStore: ApiErrorStore? = ApiErrorStore.shared) {
        self.baseURL = baseURL
        self.authStore = authStore
        self.session = session
        self.decoder = DateCoding.decoder
        self.encoder = DateCoding.encoder
        self.errorStore = errorStore
    }

    func send<T: Decodable>(_ endpoint: Endpoint, retryOnAuth: Bool = true) async throws -> T {
        try await execute(endpoint, retryOnAuth: retryOnAuth) { data in
            try self.decoder.decode(T.self, from: data)
        }
    }

    func sendNoResponse(_ endpoint: Endpoint, retryOnAuth: Bool = true) async throws {
        let _: Bool = try await execute(endpoint, retryOnAuth: retryOnAuth) { _ in true }
    }

    private func execute<T>(_ endpoint: Endpoint, retryOnAuth: Bool,
                            decode: (Data) throws -> T) async throws -> T {
        let requestID = UUID().uuidString
        let started = Date()
        var status: Int?
        var byteCount = 0
        var request = URLRequest(url: endpoint.url(baseURL: baseURL))
        request.httpMethod = endpoint.method
        request.httpBody = endpoint.body
        request.setValue(requestID, forHTTPHeaderField: "X-Mobile-Request-ID")
        if endpoint.body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let token = await MainActor.run { authStore.accessToken }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let context = "[mobile-api] id=\(requestID) \(endpoint.method) \(endpoint.path)"
        // Never log query values, headers, payloads, tokens, or raw response bodies.
        print("\(context) started")
        do {
            let (data, response) = try await session.data(for: request)
            byteCount = data.count
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            status = http.statusCode
            print("\(context) response HTTP=\(http.statusCode) bytes=\(byteCount)")
            if http.statusCode == 401, retryOnAuth {
                print("\(context) refreshing authentication; one retry allowed")
                try await refreshAccessToken()
                return try await execute(endpoint, retryOnAuth: false, decode: decode)
            }
            guard (200..<300).contains(http.statusCode) else {
                if [400, 403, 422].contains(http.statusCode),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = object["detail"] as? String, !message.isEmpty {
                    // Business validation belongs in the operator UI, not raw logs.
                    throw APIError.rejected(http.statusCode, String(message.prefix(1000)))
                }
                throw APIError.httpStatus(http.statusCode)
            }
            let result = try decode(data)
            print("\(context) success duration_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
            return result
        } catch {
            let message = "\(context) failed HTTP=\(status.map(String.init) ?? "none") bytes=\(byteCount) duration_ms=\(Int(Date().timeIntervalSince(started) * 1000)) \(Self.diagnosticFailureMessage(error))"
            print(message)
            errorStore?.record(endpoint: endpoint.path, logURL: nil, message: message)
            throw error
        }
    }

    static func diagnosticFailureMessage(_ error: Error) -> String {
        if case APIError.rejected(let code, _) = error { return "Server rejected operation (HTTP \(code)); operator message available." }
        return failureMessage(error)
    }

    static func failureMessage(_ error: Error) -> String {
        func path(_ context: DecodingError.Context, missing: CodingKey? = nil) -> String {
            let keys = context.codingPath + (missing.map { [$0] } ?? [])
            return keys.reduce("$") { result, key in
                if let index = key.intValue { return result + "[\(index)]" }
                return result + "." + key.stringValue
            }
        }
        switch error {
        case DecodingError.keyNotFound(let key, let context):
            return "Response missing field at \(path(context, missing: key))."
        case DecodingError.typeMismatch(let type, let context):
            return "Response has wrong type at \(path(context)); expected \(type)."
        case DecodingError.valueNotFound(let type, let context):
            return "Response has null at \(path(context)); expected \(type)."
        case DecodingError.dataCorrupted(let context):
            return "Response has invalid data at \(path(context))."
        case let error as APIError:
            return error.localizedDescription
        case let error as URLError:
            switch error.code {
            case .notConnectedToInternet: return "No internet connection (URL error \(error.code.rawValue))."
            case .timedOut: return "Request timed out (URL error \(error.code.rawValue))."
            case .cancelled: return "Request cancelled (URL error \(error.code.rawValue))."
            default: return "Connection failed (URL error \(error.code.rawValue))."
            }
        default:
            return "Request failed (error code \((error as NSError).code))."
        }
    }

    func recordWorkflowFailure(endpoint: String, message: String) {
        let diagnostic = "[mobile-api] workflow \(endpoint): \(message)"
        print(diagnostic)
        errorStore?.record(endpoint: endpoint, logURL: nil, message: diagnostic)
    }

    private func refreshAccessToken() async throws {
        if let refreshTask {
            _ = try await refreshTask.value
            return
        }
        let storedRefreshToken: String? = await MainActor.run { authStore.refreshToken }
        guard let refreshToken = storedRefreshToken else {
            await MainActor.run { authStore.clear() }
            throw APIError.httpStatus(401)
        }
        let task = Task<String, Error> {
            defer { self.refreshTask = nil }
            let companyId: Int? = await MainActor.run { authStore.activeCompanyId ?? authStore.user?.companyId }
            let payload = RefreshRequest(
                refreshToken: refreshToken,
                deviceId: deviceStore.deviceId,
                companyId: companyId
            )
            let body = try encoder.encode(payload)
            let endpoint = Endpoint(path: "/api/v1/auth/refresh", method: "POST", body: body)
            let response: AuthTokensResponse = try await send(endpoint, retryOnAuth: false)
            await MainActor.run {
                authStore.setSession(
                    accessToken: response.accessToken,
                    refreshToken: response.refreshToken,
                    user: response.user,
                    companies: response.companies,
                    activeCompanyId: response.user.companyId
                )
            }
            return response.accessToken
        }
        refreshTask = task
        do {
            _ = try await task.value
        } catch {
            await MainActor.run { authStore.clear() }
            throw error
        }
    }

}

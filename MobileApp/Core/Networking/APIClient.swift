import Foundation

enum APIError: Error {
    case invalidResponse
    case httpStatus(Int)
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
        var request = URLRequest(url: endpoint.url(baseURL: baseURL))
        request.httpMethod = endpoint.method
        request.httpBody = endpoint.body
        if endpoint.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token = authStore.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if httpResponse.statusCode == 401, retryOnAuth {
            try await refreshAccessToken()
            return try await send(endpoint, retryOnAuth: false)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            recordError(endpoint: endpoint.path, response: httpResponse, data: data)
            throw APIError.httpStatus(httpResponse.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }

    func sendNoResponse(_ endpoint: Endpoint, retryOnAuth: Bool = true) async throws {
        var request = URLRequest(url: endpoint.url(baseURL: baseURL))
        request.httpMethod = endpoint.method
        request.httpBody = endpoint.body
        if endpoint.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token = authStore.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if httpResponse.statusCode == 401, retryOnAuth {
            try await refreshAccessToken()
            try await sendNoResponse(endpoint, retryOnAuth: false)
            return
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            recordError(endpoint: endpoint.path, response: httpResponse, data: data)
            throw APIError.httpStatus(httpResponse.statusCode)
        }
    }

    private func refreshAccessToken() async throws {
        if let refreshTask {
            _ = try await refreshTask.value
            return
        }
        guard let refreshToken = authStore.refreshToken else {
            authStore.clear()
            throw APIError.httpStatus(401)
        }
        let task = Task<String, Error> {
            defer { self.refreshTask = nil }
            let companyId = authStore.activeCompanyId ?? authStore.user?.companyId
            let payload = RefreshRequest(
                refreshToken: refreshToken,
                deviceId: deviceStore.deviceId,
                companyId: companyId
            )
            let body = try encoder.encode(payload)
            let endpoint = Endpoint(path: "/api/v1/auth/refresh", method: "POST", body: body)
            let response: AuthTokensResponse = try await send(endpoint, retryOnAuth: false)
            authStore.setSession(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                user: response.user,
                companies: response.companies,
                activeCompanyId: response.user.companyId
            )
            return response.accessToken
        }
        refreshTask = task
        do {
            _ = try await task.value
        } catch {
            authStore.clear()
            throw error
        }
    }

    private func recordError(endpoint: String, response: HTTPURLResponse, data: Data) {
        let logURL = response.value(forHTTPHeaderField: "X-Rest-Log-Url")
        let message = String(data: data, encoding: .utf8)
        errorStore?.record(endpoint: endpoint, logURL: logURL, message: message ?? "HTTP \\(response.statusCode)")
    }
}

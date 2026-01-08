import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var login: String = ""
    @Published var password: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pendingCompanies: [CompanyInfo] = []
    @Published var showCompanyPicker = false

    private var pendingResponse: AuthTokensResponse?

    func submit(
        serverURL: URL?,
        database: String,
        authStore: AuthStore
    ) async {
        guard let serverURL else {
            errorMessage = "Server URL required"
            return
        }
        if database.isEmpty {
            errorMessage = "Database required"
            return
        }
        isLoading = true
        defer { isLoading = false }
        pendingResponse = nil
        pendingCompanies = []
        showCompanyPicker = false

        let client = APIClient(baseURL: serverURL, authStore: authStore)
        let payload = LoginRequest(
            db: database,
            login: login,
            password: password,
            deviceId: DeviceStore.shared.deviceId,
            deviceName: DeviceStore.shared.deviceName,
            companyId: authStore.activeCompanyId
        )
        do {
            let body = try DateCoding.encoder.encode(payload)
            let endpoint = Endpoint(path: "/api/v1/auth/login", method: "POST", body: body)
            let response: AuthTokensResponse = try await client.send(endpoint)
            if response.companies.count > 1 {
                pendingResponse = response
                pendingCompanies = response.companies
                showCompanyPicker = true
            } else {
                authStore.setSession(
                    accessToken: response.accessToken,
                    refreshToken: response.refreshToken,
                    user: response.user,
                    companies: response.companies,
                    activeCompanyId: response.user.companyId
                )
            }
        } catch {
            errorMessage = "Login failed"
        }
    }

    func selectCompany(
        companyId: Int,
        serverURL: URL?,
        authStore: AuthStore
    ) async {
        guard let serverURL, let pendingResponse else { return }
        isLoading = true
        defer { isLoading = false }
        if companyId == pendingResponse.user.companyId {
            authStore.setSession(
                accessToken: pendingResponse.accessToken,
                refreshToken: pendingResponse.refreshToken,
                user: pendingResponse.user,
                companies: pendingResponse.companies,
                activeCompanyId: pendingResponse.user.companyId
            )
            self.pendingResponse = nil
            pendingCompanies = []
            showCompanyPicker = false
            return
        }
        do {
            let client = APIClient(baseURL: serverURL, authStore: authStore)
            let payload = RefreshRequest(
                refreshToken: pendingResponse.refreshToken,
                deviceId: DeviceStore.shared.deviceId,
                companyId: companyId
            )
            let body = try DateCoding.encoder.encode(payload)
            let endpoint = Endpoint(path: "/api/v1/auth/refresh", method: "POST", body: body)
            let response: AuthTokensResponse = try await client.send(endpoint)
            authStore.setSession(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                user: response.user,
                companies: response.companies,
                activeCompanyId: response.user.companyId
            )
            self.pendingResponse = nil
            pendingCompanies = []
            showCompanyPicker = false
        } catch {
            errorMessage = "Company selection failed"
        }
    }
}

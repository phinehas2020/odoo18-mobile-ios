import Foundation

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var accessToken: String?
    @Published private(set) var refreshToken: String?
    @Published private(set) var user: UserProfile?
    @Published private(set) var companies: [CompanyInfo] = []
    @Published private(set) var activeCompanyId: Int?

    private let tokenStore = TokenStore()

    init() {
        accessToken = tokenStore.get("access_token")
        refreshToken = tokenStore.get("refresh_token")
        if let userData = tokenStore.get("user_profile"),
           let data = userData.data(using: .utf8),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            user = profile
        }
        if let companiesData = tokenStore.get("companies"),
           let data = companiesData.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([CompanyInfo].self, from: data) {
            companies = decoded
        }
        if let companyValue = tokenStore.get("active_company_id"),
           let companyId = Int(companyValue) {
            activeCompanyId = companyId
        }
        if activeCompanyId == nil {
            activeCompanyId = user?.companyId
        }
    }

    func setSession(
        accessToken: String,
        refreshToken: String,
        user: UserProfile,
        companies: [CompanyInfo],
        activeCompanyId: Int? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.user = user
        self.companies = companies
        let resolvedCompanyId = activeCompanyId ?? user.companyId
        self.activeCompanyId = resolvedCompanyId
        tokenStore.set(accessToken, for: "access_token")
        tokenStore.set(refreshToken, for: "refresh_token")
        if let data = try? JSONEncoder().encode(user),
           let json = String(data: data, encoding: .utf8) {
            tokenStore.set(json, for: "user_profile")
        }
        if let data = try? JSONEncoder().encode(companies),
           let json = String(data: data, encoding: .utf8) {
            tokenStore.set(json, for: "companies")
        }
        if let resolvedCompanyId {
            tokenStore.set(String(resolvedCompanyId), for: "active_company_id")
        } else {
            tokenStore.delete("active_company_id")
        }
    }

    func clear() {
        accessToken = nil
        refreshToken = nil
        user = nil
        companies = []
        activeCompanyId = nil
        tokenStore.delete("access_token")
        tokenStore.delete("refresh_token")
        tokenStore.delete("user_profile")
        tokenStore.delete("companies")
        tokenStore.delete("active_company_id")
    }
}

import Foundation

struct CompanyInfo: Codable, Identifiable {
    let id: Int
    let name: String
    let currencyId: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case currencyId = "currency_id"
    }
}

struct AuthTokensResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: UserProfile
    let companies: [CompanyInfo]

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user, companies
    }
}

struct LoginRequest: Codable {
    let db: String
    let login: String
    let password: String
    let deviceId: String
    let deviceName: String?
    let companyId: Int?

    enum CodingKeys: String, CodingKey {
        case db, login, password
        case deviceId = "device_id"
        case deviceName = "device_name"
        case companyId = "company_id"
    }
}

struct RefreshRequest: Codable {
    let refreshToken: String
    let deviceId: String
    let companyId: Int?

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
        case deviceId = "device_id"
        case companyId = "company_id"
    }
}

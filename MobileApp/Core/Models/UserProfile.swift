import Foundation

struct UserProfile: Codable {
    let id: Int
    let name: String
    let login: String
    let email: String?
    let companyId: Int?
    let allowedCompanyIds: [Int]
    let groupIds: [Int]
    let isAdmin: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, login, email
        case companyId = "company_id"
        case allowedCompanyIds = "allowed_company_ids"
        case groupIds = "group_ids"
        case isAdmin = "is_admin"
    }
}

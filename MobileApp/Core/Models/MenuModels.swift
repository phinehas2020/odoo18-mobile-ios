import Foundation

struct MenuItem: Codable, Identifiable {
    let key: String
    let label: String
    let enabled: Bool
    let deepLink: String?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, enabled
        case deepLink = "deep_link"
    }
}

struct MenuResponse: Codable {
    let items: [MenuItem]
}

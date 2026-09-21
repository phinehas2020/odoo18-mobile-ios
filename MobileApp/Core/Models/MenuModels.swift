import Foundation

struct MenuItem: Codable, Identifiable {
    let key: String
    let label: String
    let enabled: Bool
    let deepLink: String?
    let icon: String?
    let webURL: String?
    let native: Bool

    // Odoo module keys (for example "base") are shared by multiple root menus.
    // Include the destination and label; length prefixes avoid delimiter collisions.
    var id: String {
        [key, webURL ?? "", deepLink ?? "", label, native ? "native" : "web"]
            .map { "\($0.utf8.count):\($0)" }.joined()
    }

    enum CodingKeys: String, CodingKey {
        case key, label, enabled, icon, native
        case deepLink = "deep_link"
        case webURL = "web_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        label = try container.decode(String.self, forKey: .label)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        deepLink = try container.decodeIfPresent(String.self, forKey: .deepLink)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        webURL = try container.decodeIfPresent(String.self, forKey: .webURL)
        native = try container.decodeIfPresent(Bool.self, forKey: .native) ?? false
    }
}

struct MenuResponse: Codable {
    let items: [MenuItem]
}

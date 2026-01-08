import Foundation

struct DeepLinkParser {
    static func parse(userInfo: [AnyHashable: Any]) -> DeepLink? {
        if let deeplink = userInfo["deeplink"] as? [String: Any],
           let module = deeplink["module"] as? String {
            let id = deeplink["id"] as? Int
            switch module {
            case "inventory":
                if let id { return .picking(id: id) }
                return .inventoryHome
            case "sales":
                if let id { return .salesOrder(id: id) }
                return .salesHome
            case "settings":
                return .settings
            default:
                return nil
            }
        }
        return nil
    }
}

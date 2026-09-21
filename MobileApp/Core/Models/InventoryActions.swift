import Foundation

struct ScanRequest: Codable {
    let eventId: String
    let code: String
    let qty: Double?
    let timestamp: Date?
    let deviceId: String
    let recordVersion: String?

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case code, qty, timestamp
        case deviceId = "device_id"
        case recordVersion = "record_version"
    }
}

struct ValidateRequest: Codable {
    let eventId: String
    let deviceId: String
    let recordVersion: String?
    let backorderPolicy: BackorderPolicy

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case deviceId = "device_id"
        case recordVersion = "record_version"
        case backorderPolicy = "backorder_policy"
    }
}

enum BackorderPolicy: String, Codable {
    case ask
    case create
    case cancel
}

struct PickingLineUpdateRequest: Codable {
    let eventId: String
    let deviceId: String
    let qtyDone: Double
    let recordVersion: String?
    let lotId: Int?
    let lotName: String?

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case deviceId = "device_id"
        case qtyDone = "qty_done"
        case recordVersion = "record_version"
        case lotId = "lot_id"
        case lotName = "lot_name"
    }
}

struct PickingLineCreateRequest: Codable {
    let eventId: String
    let deviceId: String
    let moveId: Int
    let qtyDone: Double
    let recordVersion: String?
    let lotId: Int?
    let lotName: String?

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case deviceId = "device_id"
        case moveId = "move_id"
        case qtyDone = "qty_done"
        case recordVersion = "record_version"
        case lotId = "lot_id"
        case lotName = "lot_name"
    }
}

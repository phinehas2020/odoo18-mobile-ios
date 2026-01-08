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

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case deviceId = "device_id"
        case recordVersion = "record_version"
    }
}

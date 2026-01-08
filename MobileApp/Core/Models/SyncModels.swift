import Foundation

struct SyncChange: Codable {
    let seq: Int
    let model: String
    let resId: Int
    let operation: String
    let writeDate: Date?
    let payloadHint: String?

    enum CodingKeys: String, CodingKey {
        case seq, model, operation
        case resId = "res_id"
        case writeDate = "write_date"
        case payloadHint = "payload_hint"
    }
}

struct SyncChangesResponse: Codable {
    let cursor: Int
    let changes: [SyncChange]
}

struct OutboxAction: Codable {
    let eventId: String
    let type: String
    let payload: [String: AnyCodable]
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case type
        case payload
        case createdAt = "created_at"
    }
}

struct SyncPushRequest: Codable {
    let deviceId: String
    let actions: [OutboxAction]

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case actions
    }
}

struct SyncActionResult: Codable {
    let eventId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case status
    }
}

struct SyncPushResponse: Codable {
    let results: [SyncActionResult]
}

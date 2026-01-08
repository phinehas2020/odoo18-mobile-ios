import Foundation
import GRDB

final class OutboxStore {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    func enqueue(type: String, payload: [String: AnyCodable]) throws -> OutboxAction {
        let eventId = UUID().uuidString
        let action = OutboxAction(
            eventId: eventId,
            type: type,
            payload: payload,
            createdAt: Date()
        )
        let data = try DateCoding.encoder.encode(payload)
        let payloadString = String(decoding: data, as: UTF8.self)
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO outbox_actions (event_id, type, payload, created_at, status) VALUES (?, ?, ?, ?, ?)",
                arguments: [action.eventId, action.type, payloadString, action.createdAt ?? Date(), "pending"]
            )
        }
        return action
    }

    func pendingActions() throws -> [OutboxAction] {
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT event_id, type, payload, created_at FROM outbox_actions WHERE status != 'success' ORDER BY created_at ASC"
            )
            return rows.compactMap { row in
                guard let payloadString: String = row["payload"],
                      let data = payloadString.data(using: .utf8),
                      let payload = try? DateCoding.decoder.decode([String: AnyCodable].self, from: data) else {
                    return nil
                }
                return OutboxAction(
                    eventId: row["event_id"],
                    type: row["type"],
                    payload: payload,
                    createdAt: row["created_at"]
                )
            }
        }
    }

    func mark(eventId: String, status: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE outbox_actions SET status = ? WHERE event_id = ?",
                arguments: [status, eventId]
            )
        }
    }

    func pendingCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outbox_actions WHERE status != 'success'") ?? 0
        }
    }
}

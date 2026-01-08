import XCTest
import GRDB
@testable import MobileOdoo

final class OutboxStoreTests: XCTestCase {
    private func makeDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try db.create(table: "outbox_actions") { t in
                t.column("event_id", .text).primaryKey()
                t.column("type", .text).notNull()
                t.column("payload", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("status", .text).notNull().defaults(to: "pending")
            }
        }
        return dbQueue
    }

    func testEnqueueAndMark() throws {
        let dbQueue = try makeDatabase()
        let store = OutboxStore(dbQueue: dbQueue)
        let payload: [String: AnyCodable] = ["key": AnyCodable("value")]
        let action = try store.enqueue(type: "inventory.scan", payload: payload)

        var pending = try store.pendingActions()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.eventId, action.eventId)

        try store.mark(eventId: action.eventId, status: "success")
        pending = try store.pendingActions()
        XCTAssertEqual(pending.count, 0)
    }
}

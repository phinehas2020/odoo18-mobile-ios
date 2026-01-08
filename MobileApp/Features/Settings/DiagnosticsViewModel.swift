import Foundation
import GRDB

@MainActor
final class DiagnosticsViewModel: ObservableObject {
    @Published var lastSync: Date?
    @Published var cursor: Int = 0
    @Published var outboxCount: Int = 0
    @Published var lastError: ApiErrorEntry?

    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        self.dbQueue = dbQueue
        refresh()
    }

    func refresh() {
        do {
            try dbQueue.read { db in
                if let row = try Row.fetchOne(db, sql: "SELECT cursor, last_sync_at FROM sync_state WHERE id = 1") {
                    cursor = row["cursor"]
                    lastSync = row["last_sync_at"]
                }
                outboxCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outbox_actions WHERE status != 'success'") ?? 0
            }
        } catch {
            cursor = 0
            outboxCount = 0
        }
        lastError = ApiErrorStore.shared.latest()
    }
}

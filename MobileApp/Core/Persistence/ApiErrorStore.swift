import Foundation
import GRDB

final class ApiErrorStore {
    static let shared = ApiErrorStore()

    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    func record(endpoint: String, logURL: String?, message: String) {
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "INSERT INTO api_errors (endpoint, log_url, message, created_at) VALUES (?, ?, ?, ?)",
                    arguments: [endpoint, logURL, message, Date()]
                )
            }
        } catch {
            // ignore logging errors
        }
    }

    func diagnosticReport() -> String {
        do {
            return try dbQueue.read { db in
                let rows = try Row.fetchAll(db, sql: "SELECT message, created_at FROM api_errors WHERE message LIKE '[mobile-api]%' ORDER BY id DESC LIMIT 50")
                return rows.map { row in
                    let date: Date = row["created_at"]
                    let message: String = row["message"]
                    return "\(date.ISO8601Format()) \(message)"
                }.joined(separator: "\n\n")
            }
        } catch { return "Unable to read diagnostic history." }
    }

    func latest() -> ApiErrorEntry? {
        do {
            return try dbQueue.read { db in
                guard let row = try Row.fetchOne(db, sql: "SELECT endpoint, log_url, message, created_at FROM api_errors ORDER BY id DESC LIMIT 1") else {
                    return nil
                }
                return ApiErrorEntry(
                    endpoint: row["endpoint"],
                    logURL: row["log_url"],
                    message: row["message"],
                    createdAt: row["created_at"]
                )
            }
        } catch {
            return nil
        }
    }
}

struct ApiErrorEntry {
    let endpoint: String
    let logURL: String?
    let message: String?
    let createdAt: Date
}

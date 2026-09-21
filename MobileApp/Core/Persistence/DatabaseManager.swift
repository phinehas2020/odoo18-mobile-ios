import Foundation
import GRDB

final class DatabaseManager {
    static let shared = DatabaseManager()

    let dbQueue: DatabaseQueue

    private init() {
        let folder = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        // Ensure the directory exists
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        
        let dbURL = folder.appendingPathComponent("mobile.sqlite")
        dbQueue = try! DatabaseQueue(path: dbURL.path)
        try! Self.migrator.migrate(dbQueue)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "pickings") { t in
                t.column("id", .integer).primaryKey()
                t.column("name", .text).notNull()
                t.column("state", .text)
                t.column("partner_name", .text)
                t.column("picking_type", .text)
                t.column("priority", .text)
                t.column("source_location_name", .text)
                t.column("dest_location_name", .text)
                t.column("scheduled_date", .datetime)
                t.column("record_version", .text)
            }
            try db.create(table: "picking_lines") { t in
                t.column("id", .integer).primaryKey()
                t.column("picking_id", .integer).notNull().indexed()
                t.column("product_name", .text).notNull()
                t.column("barcode", .text)
                t.column("qty_done", .double).notNull().defaults(to: 0)
                t.column("qty_reserved", .double).notNull().defaults(to: 0)
                t.column("qty_demanded", .double).notNull().defaults(to: 0)
            }
            try db.create(table: "sync_state") { t in
                t.column("id", .integer).primaryKey()
                t.column("cursor", .integer).notNull().defaults(to: 0)
                t.column("last_sync_at", .datetime)
            }
            try db.create(table: "outbox_actions") { t in
                t.column("event_id", .text).primaryKey()
                t.column("type", .text).notNull()
                t.column("payload", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("status", .text).notNull().defaults(to: "pending")
            }
            try db.create(table: "api_errors") { t in
                t.column("id", .integer).primaryKey()
                t.column("endpoint", .text).notNull()
                t.column("log_url", .text)
                t.column("message", .text)
                t.column("created_at", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2-inventory-tracking") { db in
            try db.alter(table: "pickings") { t in
                t.add(column: "picking_type_code", .text)
            }
            try db.alter(table: "picking_lines") { t in
                t.add(column: "move_id", .integer)
                t.add(column: "product_id", .integer)
                t.add(column: "uom_name", .text)
                t.add(column: "lot_id", .integer)
                t.add(column: "lot_name", .text)
                t.add(column: "tracking", .text)
            }
            try db.create(table: "picking_moves") { t in
                t.column("id", .integer).primaryKey()
                t.column("picking_id", .integer).notNull().indexed()
                t.column("product_id", .integer).notNull()
                t.column("product_name", .text).notNull()
                t.column("barcode", .text)
                t.column("qty_demanded", .double).notNull().defaults(to: 0)
                t.column("qty_done", .double).notNull().defaults(to: 0)
                t.column("uom_name", .text)
                t.column("tracking", .text)
            }
        }
        migrator.registerMigration("v3-inventory-demand-cache") { db in
            let columns = try db.columns(in: "picking_lines").map(\.name)
            if !columns.contains("move_id") {
                try db.alter(table: "picking_lines") { $0.add(column: "move_id", .integer) }
            }
            if try !db.tableExists("picking_moves") {
                try db.create(table: "picking_moves") { t in
                    t.column("id", .integer).primaryKey()
                    t.column("picking_id", .integer).notNull().indexed()
                    t.column("product_id", .integer).notNull()
                    t.column("product_name", .text).notNull()
                    t.column("barcode", .text)
                    t.column("qty_demanded", .double).notNull().defaults(to: 0)
                    t.column("qty_done", .double).notNull().defaults(to: 0)
                    t.column("uom_name", .text)
                    t.column("tracking", .text)
                }
            }
        }
        return migrator
    }
}

import Foundation
import GRDB

final class InventoryStore {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    func save(detail: PickingDetail) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO pickings (
                    id, name, state, partner_name, picking_type, priority,
                    source_location_name, dest_location_name, scheduled_date, record_version
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    detail.id,
                    detail.name,
                    detail.state,
                    detail.partnerName,
                    detail.pickingType,
                    detail.priority,
                    detail.sourceLocation.name,
                    detail.destLocation.name,
                    detail.scheduledDate,
                    detail.recordVersion
                ]
            )
            try db.execute(sql: "DELETE FROM picking_lines WHERE picking_id = ?", arguments: [detail.id])
            for line in detail.lines {
                try db.execute(
                    sql: "INSERT INTO picking_lines (id, picking_id, product_name, barcode, qty_done, qty_reserved, qty_demanded) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    arguments: [line.id, detail.id, line.productName, line.barcode, line.qtyDone, line.qtyReserved, line.qtyDemanded]
                )
            }
        }
    }

    func fetch(pickingId: Int) throws -> PickingDetail? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT id, name, state, partner_name, picking_type, priority,
                       source_location_name, dest_location_name, scheduled_date, record_version
                FROM pickings WHERE id = ?
                """, arguments: [pickingId]) else {
                return nil
            }
            let linesRows = try Row.fetchAll(db, sql: "SELECT id, product_name, barcode, qty_done, qty_reserved, qty_demanded FROM picking_lines WHERE picking_id = ?", arguments: [pickingId])
            let lines = linesRows.map { row -> PickingLine in
                PickingLine(
                    id: row["id"],
                    productId: 0,
                    productName: row["product_name"],
                    barcode: row["barcode"],
                    qtyDone: row["qty_done"],
                    qtyReserved: row["qty_reserved"],
                    qtyDemanded: row["qty_demanded"],
                    uomName: nil,
                    lotName: nil,
                    tracking: nil
                )
            }
            return PickingDetail(
                id: row["id"],
                name: row["name"],
                state: row["state"],
                pickingType: row["picking_type"],
                scheduledDate: row["scheduled_date"],
                priority: row["priority"],
                partnerName: row["partner_name"],
                sourceLocation: LocationInfo(id: 0, name: row["source_location_name"] ?? "", barcode: nil),
                destLocation: LocationInfo(id: 0, name: row["dest_location_name"] ?? "", barcode: nil),
                recordVersion: row["record_version"],
                lines: lines
            )
        }
    }
}

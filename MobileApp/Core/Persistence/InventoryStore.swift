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
                    id, name, state, partner_name, picking_type, picking_type_code, priority,
                    source_location_name, dest_location_name, scheduled_date, record_version
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    detail.id,
                    detail.name,
                    detail.state,
                    detail.partnerName,
                    detail.pickingType,
                    detail.pickingTypeCode,
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
                    sql: "INSERT INTO picking_lines (id, picking_id, move_id, product_id, product_name, barcode, qty_done, qty_reserved, qty_demanded, uom_name, lot_id, lot_name, tracking) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    arguments: [line.id, detail.id, line.moveId, line.productId, line.productName, line.barcode, line.qtyDone, line.qtyReserved, line.qtyDemanded, line.uomName, line.lotId, line.lotName, line.tracking]
                )
            }
            try db.execute(sql: "DELETE FROM picking_moves WHERE picking_id = ?", arguments: [detail.id])
            for move in detail.moves ?? [] {
                try db.execute(
                    sql: "INSERT INTO picking_moves (id, picking_id, product_id, product_name, barcode, qty_demanded, qty_done, uom_name, tracking) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    arguments: [move.id, detail.id, move.productId, move.productName, move.barcode, move.qtyDemanded, move.qtyDone, move.uomName, move.tracking]
                )
            }
        }
    }

    func fetch(pickingId: Int) throws -> PickingDetail? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT id, name, state, partner_name, picking_type, picking_type_code, priority,
                       source_location_name, dest_location_name, scheduled_date, record_version
                FROM pickings WHERE id = ?
                """, arguments: [pickingId]) else {
                return nil
            }
            let linesRows = try Row.fetchAll(db, sql: "SELECT id, move_id, product_id, product_name, barcode, qty_done, qty_reserved, qty_demanded, uom_name, lot_id, lot_name, tracking FROM picking_lines WHERE picking_id = ?", arguments: [pickingId])
            let lines = linesRows.map { row -> PickingLine in
                PickingLine(
                    id: row["id"],
                    moveId: row["move_id"],
                    productId: row["product_id"] ?? 0,
                    productName: row["product_name"],
                    barcode: row["barcode"],
                    qtyDone: row["qty_done"],
                    qtyReserved: row["qty_reserved"],
                    qtyDemanded: row["qty_demanded"],
                    uomName: row["uom_name"],
                    lotId: row["lot_id"],
                    lotName: row["lot_name"],
                    tracking: row["tracking"]
                )
            }
            let moveRows = try Row.fetchAll(db, sql: "SELECT id, product_id, product_name, barcode, qty_demanded, qty_done, uom_name, tracking FROM picking_moves WHERE picking_id = ?", arguments: [pickingId])
            let moves = moveRows.map { move -> PickingMove in
                PickingMove(
                    id: move["id"], productId: move["product_id"], productName: move["product_name"],
                    barcode: move["barcode"], qtyDemanded: move["qty_demanded"], qtyDone: move["qty_done"],
                    uomName: move["uom_name"], tracking: move["tracking"]
                )
            }
            return PickingDetail(
                id: row["id"],
                name: row["name"],
                state: row["state"],
                pickingType: row["picking_type"],
                pickingTypeCode: row["picking_type_code"],
                scheduledDate: row["scheduled_date"],
                priority: row["priority"],
                partnerName: row["partner_name"],
                sourceLocation: LocationInfo(id: 0, name: row["source_location_name"] ?? "", barcode: nil),
                destLocation: LocationInfo(id: 0, name: row["dest_location_name"] ?? "", barcode: nil),
                recordVersion: row["record_version"],
                lines: lines,
                moves: moves
            )
        }
    }
}

import Foundation

enum InventoryScope: String, CaseIterable, Identifiable {
    case myReady
    case receipts
    case deliveries
    case internalTransfers
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myReady: return "My Ready Transfers"
        case .receipts: return "Receipts"
        case .deliveries: return "Deliveries"
        case .internalTransfers: return "Internal Transfers"
        case .history: return "Transfer History"
        }
    }

    var sectionTitle: String {
        switch self {
        case .myReady: return "Ready transfers assigned to you"
        case .receipts: return "Open receipts · all assignees"
        case .deliveries: return "Open deliveries · all assignees"
        case .internalTransfers: return "Open internal transfers · all assignees"
        case .history: return "Completed transfers"
        }
    }

    var pickingTypeCode: String? {
        switch self {
        case .myReady: return nil
        case .receipts: return "incoming"
        case .deliveries: return "outgoing"
        case .internalTransfers: return "internal"
        case .history: return nil
        }
    }

    var states: String {
        switch self {
        case .myReady: return "assigned"
        case .history: return "done"
        case .receipts, .deliveries, .internalTransfers: return "confirmed,waiting,assigned"
        }
    }
}

struct PickingProgress: Codable {
    let done: Double
    let total: Double
}

struct PickingListItem: Codable, Identifiable {
    let id: Int
    let name: String
    let pickingType: String?
    var pickingTypeCode: String? = nil
    let scheduledDate: Date?
    let priority: String?
    let partnerName: String?
    let progress: PickingProgress

    enum CodingKeys: String, CodingKey {
        case id, name, priority, progress
        case pickingType = "picking_type"
        case pickingTypeCode = "picking_type_code"
        case scheduledDate = "scheduled_date"
        case partnerName = "partner_name"
    }
}

struct PickingLine: Codable, Identifiable {
    let id: Int
    var moveId: Int? = nil
    let productId: Int
    let productName: String
    let barcode: String?
    let qtyDone: Double
    let qtyReserved: Double
    let qtyDemanded: Double
    let uomName: String?
    let lotId: Int?
    let lotName: String?
    let tracking: String?

    enum CodingKeys: String, CodingKey {
        case id
        case moveId = "move_id"
        case productId = "product_id"
        case productName = "product_name"
        case barcode
        case qtyDone = "qty_done"
        case qtyReserved = "qty_reserved"
        case qtyDemanded = "qty_demanded"
        case uomName = "uom_name"
        case lotId = "lot_id"
        case lotName = "lot_name"
        case tracking
    }
}

struct LocationInfo: Codable {
    let id: Int
    let name: String
    let barcode: String?
}

struct PickingDetail: Codable {
    let id: Int
    let name: String
    let state: String
    let pickingType: String?
    let pickingTypeCode: String?
    let scheduledDate: Date?
    let priority: String?
    let partnerName: String?
    let sourceLocation: LocationInfo
    let destLocation: LocationInfo
    let recordVersion: String?
    let lines: [PickingLine]
    var moves: [PickingMove]? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, state, priority, lines, moves
        case pickingType = "picking_type"
        case pickingTypeCode = "picking_type_code"
        case scheduledDate = "scheduled_date"
        case partnerName = "partner_name"
        case sourceLocation = "source_location"
        case destLocation = "dest_location"
        case recordVersion = "record_version"
    }
}

struct PickingMove: Codable, Identifiable {
    let id: Int
    let productId: Int
    let productName: String
    let barcode: String?
    let qtyDemanded: Double
    let qtyDone: Double
    let uomName: String?
    let tracking: String?

    enum CodingKeys: String, CodingKey {
        case id, barcode, tracking
        case productId = "product_id"
        case productName = "product_name"
        case qtyDemanded = "qty_demanded"
        case qtyDone = "qty_done"
        case uomName = "uom_name"
    }
}

extension PickingDetail {
    func replacingLine(_ line: PickingLine, recordVersion: String?) -> PickingDetail {
        let updatedLines = lines.contains(where: { $0.id == line.id })
            ? lines.map { $0.id == line.id ? line : $0 }
            : lines + [line]
        return PickingDetail(
            id: id,
            name: name,
            state: state,
            pickingType: pickingType,
            pickingTypeCode: pickingTypeCode,
            scheduledDate: scheduledDate,
            priority: priority,
            partnerName: partnerName,
            sourceLocation: sourceLocation,
            destLocation: destLocation,
            recordVersion: recordVersion ?? self.recordVersion,
            lines: updatedLines,
            moves: moves
        )
    }

    func withRecordVersion(_ recordVersion: String?) -> PickingDetail {
        PickingDetail(
            id: id, name: name, state: state, pickingType: pickingType,
            pickingTypeCode: pickingTypeCode, scheduledDate: scheduledDate,
            priority: priority, partnerName: partnerName,
            sourceLocation: sourceLocation, destLocation: destLocation,
            recordVersion: recordVersion ?? self.recordVersion, lines: lines, moves: moves
        )
    }

    func withUpdatedLines(_ updatedLines: [PickingLine], recordVersion: String? = nil) -> PickingDetail {
        var newLines = self.lines
        for updated in updatedLines {
            if let index = newLines.firstIndex(where: { $0.id == updated.id }) {
                newLines[index] = updated
            } else {
                newLines.append(updated)
            }
        }
        return PickingDetail(
            id: id,
            name: name,
            state: state,
            pickingType: pickingType,
            pickingTypeCode: pickingTypeCode,
            scheduledDate: scheduledDate,
            priority: priority,
            partnerName: partnerName,
            sourceLocation: sourceLocation,
            destLocation: destLocation,
            recordVersion: recordVersion ?? self.recordVersion,
            lines: newLines,
            moves: moves
        )
    }

    func applyLocalScan(code: String) -> PickingDetail? {
        // Simple mock for offline mode: find line by barcode and increment qtyDone
        var newLines = self.lines
        guard let index = newLines.firstIndex(where: { $0.barcode == code }) else { return nil }
        
        let oldLine = newLines[index]
        newLines[index] = PickingLine(
            id: oldLine.id,
            moveId: oldLine.moveId,
            productId: oldLine.productId,
            productName: oldLine.productName,
            barcode: oldLine.barcode,
            qtyDone: oldLine.qtyDone + 1,
            qtyReserved: oldLine.qtyReserved,
            qtyDemanded: oldLine.qtyDemanded,
            uomName: oldLine.uomName,
            lotId: oldLine.lotId,
            lotName: oldLine.lotName,
            tracking: oldLine.tracking
        )
        
        return PickingDetail(
            id: id,
            name: name,
            state: state,
            pickingType: pickingType,
            pickingTypeCode: pickingTypeCode,
            scheduledDate: scheduledDate,
            priority: priority,
            partnerName: partnerName,
            sourceLocation: sourceLocation,
            destLocation: destLocation,
            recordVersion: recordVersion,
            lines: newLines,
            moves: moves
        )
    }
}

struct ScanResponse: Codable {
    let status: String
    let updatedLines: [PickingLine]
    let warnings: [String]?
    let nextExpected: String?
    let recordVersion: String?

    enum CodingKeys: String, CodingKey {
        case status
        case updatedLines = "updated_lines"
        case warnings
        case nextExpected = "next_expected"
        case recordVersion = "record_version"
    }
}

struct ValidateResponse: Codable {
    let status: String
    let pickingState: String?
    let recordVersion: String?
    let backorderRequired: Bool?
    let backorderPickingId: Int?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status, message
        case pickingState = "picking_state"
        case recordVersion = "record_version"
        case backorderRequired = "backorder_required"
        case backorderPickingId = "backorder_picking_id"
    }
}

struct PickingLineUpdateResponse: Codable {
    let status: String
    let line: PickingLine
    let recordVersion: String?
    let warnings: [String]?

    enum CodingKeys: String, CodingKey {
        case status, line, warnings
        case recordVersion = "record_version"
    }
}

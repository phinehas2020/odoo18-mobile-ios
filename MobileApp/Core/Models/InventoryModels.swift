import Foundation

struct PickingProgress: Codable {
    let done: Double
    let total: Double
}

struct PickingListItem: Codable, Identifiable {
    let id: Int
    let name: String
    let pickingType: String?
    let scheduledDate: Date?
    let priority: String?
    let partnerName: String?
    let progress: PickingProgress

    enum CodingKeys: String, CodingKey {
        case id, name, priority, progress
        case pickingType = "picking_type"
        case scheduledDate = "scheduled_date"
        case partnerName = "partner_name"
    }
}

struct PickingLine: Codable, Identifiable {
    let id: Int
    let productId: Int
    let productName: String
    let barcode: String?
    let qtyDone: Double
    let qtyReserved: Double
    let qtyDemanded: Double
    let uomName: String?
    let lotName: String?
    let tracking: String?

    enum CodingKeys: String, CodingKey {
        case id
        case productId = "product_id"
        case productName = "product_name"
        case barcode
        case qtyDone = "qty_done"
        case qtyReserved = "qty_reserved"
        case qtyDemanded = "qty_demanded"
        case uomName = "uom_name"
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
    let scheduledDate: Date?
    let priority: String?
    let partnerName: String?
    let sourceLocation: LocationInfo
    let destLocation: LocationInfo
    let recordVersion: String?
    let lines: [PickingLine]

    enum CodingKeys: String, CodingKey {
        case id, name, state, priority, lines
        case pickingType = "picking_type"
        case scheduledDate = "scheduled_date"
        case partnerName = "partner_name"
        case sourceLocation = "source_location"
        case destLocation = "dest_location"
        case recordVersion = "record_version"
    }
}

extension PickingDetail {
    func withUpdatedLines(_ updatedLines: [PickingLine]) -> PickingDetail {
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
            scheduledDate: scheduledDate,
            priority: priority,
            partnerName: partnerName,
            sourceLocation: sourceLocation,
            destLocation: destLocation,
            recordVersion: recordVersion,
            lines: newLines
        )
    }

    func applyLocalScan(code: String) -> PickingDetail? {
        // Simple mock for offline mode: find line by barcode and increment qtyDone
        var newLines = self.lines
        guard let index = newLines.firstIndex(where: { $0.barcode == code }) else { return nil }
        
        let oldLine = newLines[index]
        newLines[index] = PickingLine(
            id: oldLine.id,
            productId: oldLine.productId,
            productName: oldLine.productName,
            barcode: oldLine.barcode,
            qtyDone: oldLine.qtyDone + 1,
            qtyReserved: oldLine.qtyReserved,
            qtyDemanded: oldLine.qtyDemanded,
            uomName: oldLine.uomName,
            lotName: oldLine.lotName,
            tracking: oldLine.tracking
        )
        
        return PickingDetail(
            id: id,
            name: name,
            state: state,
            pickingType: pickingType,
            scheduledDate: scheduledDate,
            priority: priority,
            partnerName: partnerName,
            sourceLocation: sourceLocation,
            destLocation: destLocation,
            recordVersion: recordVersion,
            lines: newLines
        )
    }
}

struct ScanResponse: Codable {
    let status: String
    let updatedLines: [PickingLine]
    let warnings: [String]?
    let nextExpected: String?

    enum CodingKeys: String, CodingKey {
        case status
        case updatedLines = "updated_lines"
        case warnings
        case nextExpected = "next_expected"
    }
}

struct ValidateResponse: Codable {
    let status: String
}

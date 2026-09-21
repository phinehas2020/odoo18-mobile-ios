import Foundation

struct ManufacturingOrder: Decodable, Identifiable {
    let id: Int
    let name: String
    let state: String
    let productName: String?
    let quantity: Double?
    let uomName: String?
    let assignedUserName: String?
    let attentionReason: String?
    let isPlanned: Bool?
    enum CodingKeys: String, CodingKey {
        case id, name, state, quantity
        case productName = "product_name", uomName = "uom_name"
        case assignedUserName = "assigned_user_name", attentionReason = "attention_reason"
        case isPlanned = "is_planned"
    }
}

struct ManufacturingDetail: Decodable {
    let id: Int
    let name: String
    let state: String
    let productName: String?
    let quantity: Double?
    let uomName: String?
    let productTracking: String?
    let finishedLotName: String?
    let qualityChecks: [ManufacturingQualityCheck]?
    let isPlanned: Bool?
    let components: [ManufacturingComponent]
    let workorders: [ManufacturingWorkOrder]
    enum CodingKeys: String, CodingKey {
        case id, name, state, quantity, components, workorders
        case productTracking = "product_tracking", finishedLotName = "finished_lot_name"
        case qualityChecks = "quality_checks", isPlanned = "is_planned"
        case productName = "product_name", uomName = "uom_name"
    }
}

struct ManufacturingComponent: Decodable, Identifiable {
    let id: Int
    let productName: String
    let productId: Int?
    let tracking: String?
    let picked: Bool?
    let reservedQuantity: Double?
    let lotQuantities: [ManufacturingLotQuantity]?
    let quantity: Double
    let doneQuantity: Double?
    let uomName: String?
    enum CodingKeys: String, CodingKey {
        case id, quantity, tracking, picked
        case reservedQuantity = "reserved_quantity", lotQuantities = "lot_quantities"
        case productId = "product_id"
        case productName = "product_name", doneQuantity = "done_quantity", uomName = "uom_name"
    }
}

struct ManufacturingWorkOrder: Decodable, Identifiable {
    let id: Int
    let name: String
    let state: String
    let workcenterName: String?
    let productName: String?
    let employeeName: String?
    let expectedDurationMinutes: Double?
    let realDurationMinutes: Double?
    let quantityRemaining: Double?
    let isUserWorking: Bool
    enum CodingKeys: String, CodingKey {
        case id, name, state
        case workcenterName = "workcenter_name", quantityRemaining = "quantity_remaining"
        case productName = "product_name", employeeName = "employee_name"
        case expectedDurationMinutes = "expected_duration_minutes", realDurationMinutes = "real_duration_minutes"
        case isUserWorking = "is_user_working"
    }
    var canStart: Bool { ["ready", "progress"].contains(state) && !isUserWorking }
    var canPause: Bool { state == "progress" && isUserWorking }
    var canFinish: Bool { state == "progress" }
}

func warehouseStateLabel(_ state: String) -> String {
    switch state {
    case "draft": return "Draft"
    case "confirmed": return "Confirmed"
    case "ready", "assigned": return "Ready"
    case "progress": return "In progress"
    case "pending": return "Waiting for another operation"
    case "waiting": return "Waiting for materials"
    case "to_close": return "Ready to close"
    case "done": return "Completed"
    case "cancel": return "Cancelled"
    default: return state.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

func workDurationLabel(_ minutes: Double?) -> String {
    guard let minutes, minutes.isFinite, minutes >= 0, minutes < Double(Int.max / 2) else { return "Not available" }
    let rounded = Int(minutes.rounded())
    return String(format: "%02d:%02d", rounded / 60, rounded % 60)
}

struct ManufacturingQualityCheck: Decodable, Identifiable {
    let id: Int
    let name: String
    let state: String
    let controlType: String?
    let failureAction: String?
    let notes: String?
    let instructions: String?
    let completedByName: String?
    enum CodingKeys: String, CodingKey {
        case id, name, state, notes, instructions
        case controlType = "control_type", failureAction = "failure_action"
        case completedByName = "completed_by_name"
    }
}

struct ManufacturingCompletionReview: Decodable {
    let orderId: Int
    let canComplete: Bool
    let blockers: [String]
    let warnings: [String]
    let suggestedQuantity: Double?
    let quantityRemaining: Double
    let requiresFinishedLot: Bool
    let openWorkorderIds: [Int]
    let pendingQualityCheckIds: [Int]
    enum CodingKeys: String, CodingKey {
        case blockers, warnings
        case orderId = "order_id", canComplete = "can_complete"
        case suggestedQuantity = "suggested_quantity", quantityRemaining = "quantity_remaining"
        case requiresFinishedLot = "requires_finished_lot"
        case openWorkorderIds = "open_workorder_ids", pendingQualityCheckIds = "pending_quality_check_ids"
    }
}

struct ManufacturingLot: Decodable, Identifiable {
    let id: Int
    let name: String
}

struct ManufacturingProduct: Decodable, Identifiable {
    let id: Int
    let name: String
    let tracking: String?
    let uomName: String?
    enum CodingKeys: String, CodingKey { case id, name, tracking; case uomName = "uom_name" }
}

struct ManufacturingAssignee: Decodable, Identifiable {
    let id: Int
    let name: String
}

struct ManufacturingCompletionPayload: Encodable {
    let reviewed = true
    let quantity: Double
    let disposition: String
    let finishedLotName: String?
    let components: [Component]
    struct Component: Encodable {
        let moveId: Int
        let quantity: Double
        let lotId: Int?
        enum CodingKeys: String, CodingKey { case quantity; case moveId = "move_id", lotId = "lot_id" }
    }
    enum CodingKeys: String, CodingKey {
        case reviewed, quantity, disposition, components
        case finishedLotName = "finished_lot_name"
    }
}

func warehouseQuantity(_ text: String) -> Double? {
    let formatter = NumberFormatter()
    formatter.locale = .current
    formatter.numberStyle = .decimal
    formatter.isLenient = false
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    // Reject trailing text rather than accepting NumberFormatter's partial parse.
    let separator = Locale.current.decimalSeparator ?? "."
    let pattern = "^[0-9]+(?:" + NSRegularExpression.escapedPattern(for: separator) + "[0-9]+)?$"
    guard trimmed.range(of: pattern, options: .regularExpression) != nil,
          let value = formatter.number(from: trimmed)?.doubleValue, value.isFinite else { return nil }
    return value
}

struct ManufacturingLotQuantity: Decodable {
    let lotId: Int?
    let lotName: String?
    let quantity: Double
    enum CodingKeys: String, CodingKey { case quantity; case lotId = "lot_id", lotName = "lot_name" }
}

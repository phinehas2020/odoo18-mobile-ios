import Foundation

struct PackingCapabilities: Decodable {
    let enabled: Bool
    let businessEnabled: Bool?
    let canPack: Bool
    let canSupervise: Bool
    let requiresOnline: Bool
    let workflowVersion: String

    enum CodingKeys: String, CodingKey {
        case enabled
        case businessEnabled = "business_enabled"
        case canPack = "can_pack"
        case canSupervise = "can_supervise"
        case requiresOnline = "requires_online"
        case workflowVersion = "workflow_version"
    }
}

struct PackingDetail: Decodable, Identifiable {
    let shipmentId: Int
    let orderId: Int
    let orderName: String
    let customerName: String?
    var customerOrderCount: Int? = nil
    let trackingNumber: String
    let carrier: String?
    let boxNumber: Int
    let boxCount: Int
    let packingState: String
    let operationalState: String
    let orderState: String?
    let syncState: String
    let version: Int
    let workflowVersion: String
    let owner: PackingOwner?
    let completedAt: String?
    let items: [PackingItem]
    let siblings: [PackingSibling]
    let allowedActions: PackingAllowedActions
    let reviewReason: String?
    let resolvedBarcode: String?
    let resolvedSymbology: String?

    var customerHistoryTitle: String {
        guard let count = customerOrderCount, count > 0 else { return "Customer history unavailable" }
        return count > 1 ? "Repeat customer" : "First-time customer"
    }
    var discountCardInstruction: String {
        guard let count = customerOrderCount, count > 0 else { return "Check customer history before adding a discount card." }
        if count > 1 { return "Do not add discount card" }
        return boxCount > 1 ? (boxNumber == 1 ? "Add discount card — one card for this order" : "Add discount card to box 1 only") : "Add discount card"
    }

    var id: Int { shipmentId }
    var isPacked: Bool { packingState == "packed" }
    private var blockingReason: String? {
        guard let reason = reviewReason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty else { return nil }
        return reason
    }
    var needsReview: Bool {
        blockingReason != nil || !["packing_v1", "legacy_print"].contains(workflowVersion) || !["unstarted", "in_progress", "packed", "review", "void"].contains(packingState) ||
        !["pending", "complete", "review"].contains(operationalState) || !["not_ready", "pending", "submitting", "synced", "review"].contains(syncState) ||
        packingState == "review" || operationalState == "review" || syncState == "review" || packingState == "void"
    }
    var allItemsConfirmed: Bool {
        !items.isEmpty && items.allSatisfy {
            $0.requiredQuantity.isFinite && $0.requiredQuantity > 0 && $0.requiredQuantity.rounded() == $0.requiredQuantity &&
            $0.confirmedQuantity.isFinite && $0.confirmedQuantity.rounded() == $0.confirmedQuantity && abs($0.confirmedQuantity - $0.requiredQuantity) < 0.000001
        }
    }
    var canEdit: Bool { workflowVersion == "packing_v1" && allowedActions.edit && !isPacked && !needsReview }
    var canFinish: Bool { workflowVersion == "packing_v1" && allowedActions.complete && allItemsConfirmed && !isPacked && !needsReview }
    var packedBoxCount: Int { siblings.filter { $0.packingState == "packed" }.count }
    var statusTitle: String {
        if needsReview { return isPacked ? "Packed — review needed" : "Supervisor review needed" }
        if workflowVersion == "legacy_print" { return "Previous workflow label" }
        if operationalState == "complete", isPacked {
            return syncState == "synced" && orderState == "shipped" ? "Shipped" : "Packed — tracking update pending"
        }
        if isPacked { return boxCount > 1 ? "Box packed" : "Packed — finishing order" }
        return "Pick this box"
    }
    var statusExplanation: String {
        if let reason = blockingReason { return reason }
        if packingState == "void" { return "This label is no longer active. Ask a supervisor for the current label." }
        if needsReview { return "Ask a supervisor to check this box before shipping. Refresh after the issue is resolved." }
        if workflowVersion == "legacy_print" {
            return "This label follows the previous workflow. View its products here and finish it through the existing order process."
        }
        if operationalState == "complete", isPacked {
            return syncState == "synced" && orderState == "shipped"
                ? "Packing and fulfillment are complete. This order is shipped."
                : "Packing and Odoo are complete. Store tracking is still being confirmed."
        }
        if isPacked, boxCount > 1 {
            return packedBoxCount >= boxCount
                ? "All boxes are packed. Refresh to check the order’s completion."
                : "\(packedBoxCount) of \(boxCount) boxes packed. Scan the remaining boxes to finish the order."
        }
        if isPacked { return "This box is packed. Refresh to check the order’s completion." }
        return "Confirm every item, then scan this label again to finish."
    }

    enum CodingKeys: String, CodingKey {
        case items, siblings, version, owner, carrier
        case shipmentId = "shipment_id"
        case orderId = "order_id"
        case orderName = "order_name"
        case customerName = "customer_name"
        case customerOrderCount = "customer_order_count"
        case trackingNumber = "tracking_number"
        case boxNumber = "box_number"
        case boxCount = "box_count"
        case packingState = "packing_state"
        case operationalState = "operational_state"
        case orderState = "order_state"
        case syncState = "sync_state"
        case workflowVersion = "workflow_version"
        case completedAt = "completed_at"
        case allowedActions = "allowed_actions"
        case reviewReason = "review_reason"
        case resolvedBarcode = "resolved_barcode"
        case resolvedSymbology = "resolved_symbology"
    }
}

struct PackingOwner: Decodable { let id: Int; let name: String }
struct PackingAllowedActions: Decodable { let claim: Bool; let edit: Bool; let complete: Bool }

struct PackingItem: Decodable, Identifiable {
    let lineId: Int
    let title: String
    let variantTitle: String?
    let sku: String?
    let barcode: String?
    let productId: Int?
    let requiredQuantity: Double
    let confirmedQuantity: Double
    let remainingQuantity: Double
    var id: Int { lineId }
    var isConfirmed: Bool { abs(requiredQuantity - confirmedQuantity) < 0.000001 }
    var displayTitle: String {
        guard let variantTitle, !variantTitle.isEmpty, variantTitle != "Default Title" else { return title }
        return "\(title) · \(variantTitle)"
    }
    enum CodingKeys: String, CodingKey {
        case title, sku, barcode
        case lineId = "line_id"
        case variantTitle = "variant_title"
        case productId = "product_id"
        case requiredQuantity = "required_quantity"
        case confirmedQuantity = "confirmed_quantity"
        case remainingQuantity = "remaining_quantity"
    }
}

struct PackingSibling: Decodable, Identifiable {
    let shipmentId: Int
    let boxNumber: Int
    let packingState: String
    var id: Int { shipmentId }
    enum CodingKeys: String, CodingKey {
        case shipmentId = "shipment_id"
        case boxNumber = "box_number"
        case packingState = "packing_state"
    }
}

struct BarcodeCandidate: Codable, Hashable, Identifiable {
    let barcode: String
    let symbology: String
    var id: String { "\(symbology):\(barcode)" }
}

struct PackingResolveRequest: Encodable {
    let candidates: [BarcodeCandidate]
    let deviceId: String
    enum CodingKeys: String, CodingKey { case candidates; case deviceId = "device_id" }
}

struct PackingQuantityRequest: Encodable {
    let quantity: Double
    let version: Int
    let eventId: String
    let deviceId: String
    enum CodingKeys: String, CodingKey {
        case quantity, version
        case eventId = "event_id"
        case deviceId = "device_id"
    }
}

struct PackingCompleteRequest: Encodable {
    let barcode: String
    let symbology: String
    let version: Int
    let eventId: String
    let deviceId: String
    enum CodingKeys: String, CodingKey {
        case barcode, symbology, version
        case eventId = "event_id"
        case deviceId = "device_id"
    }
}

// A marker survives an interrupted request. Recovery always reads server state;
// this store never queues or retries stock, accounting, or completion writes.
struct PendingPackingCompletion: Codable {
    let shipmentId: Int
    let eventId: String
    let deviceId: String
    let userId: Int
    let companyId: Int?
}

final class PackingRecoveryStore {
    private let defaults: UserDefaults
    private let key = "packing_pending_completion_v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func read() -> PendingPackingCompletion? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PendingPackingCompletion.self, from: data)
    }
    func save(_ value: PendingPackingCompletion) { defaults.set(try? JSONEncoder().encode(value), forKey: key) }
    func clear() { defaults.removeObject(forKey: key) }
}

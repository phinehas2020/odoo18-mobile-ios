import Foundation

@MainActor
final class InventoryDetailViewModel: ObservableObject {
    @Published var detail: PickingDetail?
    @Published var isLoading = false
    @Published var lastWarning: String?
    @Published var lastScanStatus: String?
    @Published var needsRefresh = false

    private let outboxStore = OutboxStore()
    private let inventoryStore = InventoryStore()

    func load(apiClient: APIClient?, pickingId: Int) async {
        isLoading = true
        defer { isLoading = false }
        if let apiClient {
            do {
                let endpoint = Endpoint(path: "/api/v1/inventory/pickings/\(pickingId)", method: "GET")
                let detail: PickingDetail = try await apiClient.send(endpoint)
                self.detail = detail
                needsRefresh = false
                try? inventoryStore.save(detail: detail)
                return
            } catch {
                self.detail = try? inventoryStore.fetch(pickingId: pickingId)
                return
            }
        }
        self.detail = try? inventoryStore.fetch(pickingId: pickingId)
    }

    func scan(apiClient: APIClient?, pickingId: Int, code: String, isOnline: Bool) async {
        guard let detail else { return }
        let request = ScanRequest(
            eventId: UUID().uuidString,
            code: code,
            qty: nil,
            timestamp: Date(),
            deviceId: DeviceStore.shared.deviceId,
            recordVersion: detail.recordVersion
        )
        if isOnline, let apiClient {
            do {
                let body = try DateCoding.encoder.encode(request)
                let endpoint = Endpoint(path: "/api/v1/inventory/pickings/\(pickingId)/scan", method: "POST", body: body)
                let response: ScanResponse = try await apiClient.send(endpoint)
                self.detail = detail.withUpdatedLines(response.updatedLines)
                lastScanStatus = response.status
                if let warning = response.warnings?.first {
                    lastWarning = warning
                }
                if let updated = self.detail {
                    try? inventoryStore.save(detail: updated)
                }
                return
            } catch {
                if let apiError = error as? APIError, case .httpStatus(409) = apiError {
                    lastWarning = "Picking updated on server. Refresh required."
                    lastScanStatus = "conflict"
                    needsRefresh = true
                    return
                }
                lastWarning = "Scan queued (offline)"
                lastScanStatus = "queued"
            }
        }

        if let updated = detail.applyLocalScan(code: code) {
            self.detail = updated
            lastScanStatus = "queued"
            try? inventoryStore.save(detail: updated)
            
            do {
                let payload: [String: AnyCodable] = [
                    "picking_id": AnyCodable(pickingId),
                    "code": AnyCodable(code),
                    "device_id": AnyCodable(DeviceStore.shared.deviceId),
                    "record_version": AnyCodable(detail.recordVersion ?? "")
                ]
                _ = try outboxStore.enqueue(type: "inventory.scan", payload: payload)
            } catch {
                lastWarning = "Failed to queue scan"
            }
        } else {
            lastWarning = "Barcode not found"
            lastScanStatus = "failed"
        }
    }

    func validate(apiClient: APIClient?, pickingId: Int, isOnline: Bool) async {
        guard let detail else { return }
        let request = ValidateRequest(
            eventId: UUID().uuidString,
            deviceId: DeviceStore.shared.deviceId,
            recordVersion: detail.recordVersion
        )
        if isOnline, let apiClient {
            do {
                let body = try DateCoding.encoder.encode(request)
                let endpoint = Endpoint(path: "/api/v1/inventory/pickings/\(pickingId)/validate", method: "POST", body: body)
                _ = try await apiClient.send(endpoint) as ValidateResponse
                lastScanStatus = "validated"
                return
            } catch {
                if let apiError = error as? APIError, case .httpStatus(409) = apiError {
                    lastWarning = "Picking updated on server. Refresh required."
                    lastScanStatus = "conflict"
                    needsRefresh = true
                    return
                }
                lastWarning = "Validation queued (offline)"
                lastScanStatus = "queued"
            }
        }

        do {
            let payload: [String: AnyCodable] = [
                "picking_id": AnyCodable(pickingId),
                "device_id": AnyCodable(DeviceStore.shared.deviceId),
                "record_version": AnyCodable(detail.recordVersion ?? "")
            ]
            _ = try outboxStore.enqueue(type: "inventory.validate", payload: payload)
            lastScanStatus = "queued"
        } catch {
            lastWarning = "Validation failed"
            lastScanStatus = "failed"
        }
    }
}


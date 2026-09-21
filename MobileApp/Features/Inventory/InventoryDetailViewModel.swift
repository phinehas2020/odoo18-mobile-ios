import Foundation

@MainActor
final class InventoryDetailViewModel: ObservableObject {
    @Published var detail: PickingDetail?
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var lastWarning: String?
    @Published var lastScanStatus: String?
    @Published var needsRefresh = false
    @Published var needsBackorderDecision = false
    @Published var backorderMessage: String?

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
                needsRefresh = true
                lastWarning = "Live inventory could not be loaded. Cached details are read-only until you refresh."
                return
            }
        }
        self.detail = try? inventoryStore.fetch(pickingId: pickingId)
        needsRefresh = true
    }

    func scan(apiClient: APIClient?, pickingId: Int, code: String, isOnline: Bool) async -> Bool {
        guard isOnline, let apiClient else {
            lastWarning = "Connect before adding a scan. Offline scans are not queued because stock may have changed."
            lastScanStatus = "failed"
            return false
        }
        guard !isSubmitting, !isLoading, !needsRefresh, let detail, !["done", "cancel"].contains(detail.state) else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        let request = ScanRequest(
            eventId: UUID().uuidString,
            code: code,
            qty: nil,
            timestamp: Date(),
            deviceId: DeviceStore.shared.deviceId,
            recordVersion: detail.recordVersion
        )
        do {
            let body = try DateCoding.encoder.encode(request)
            let endpoint = Endpoint(path: "/api/v1/inventory/pickings/\(pickingId)/scan", method: "POST", body: body)
            let response: ScanResponse = try await apiClient.send(endpoint, retryOnAuth: false)
            self.detail = detail.withUpdatedLines(response.updatedLines, recordVersion: response.recordVersion)
            lastScanStatus = response.status
            if let warning = response.warnings?.first { lastWarning = warning }
            if let updated = self.detail { try? inventoryStore.save(detail: updated) }
            return response.status == "success"
        } catch {
            if let apiError = error as? APIError, case .httpStatus(409) = apiError {
                lastWarning = "Picking updated on server. Refresh required."
                lastScanStatus = "conflict"
                needsRefresh = true
            } else {
                lastWarning = "Couldn’t confirm this scan. Refresh before trying another inventory action."
                lastScanStatus = "failed"
                needsRefresh = true
            }
            return false
        }
    }

    func updateLine(
        apiClient: APIClient?,
        pickingId: Int,
        lineId: Int,
        quantity: Double,
        lotId: Int?,
        lotName: String?,
        isOnline: Bool
    ) async -> Bool {
        guard isOnline, let apiClient else {
            lastWarning = "Connect to update receipt quantities. Offline absolute quantity edits are not queued."
            return false
        }
        guard !isSubmitting, !isLoading, !needsRefresh, let detail,
              !["done", "cancel"].contains(detail.state), quantity >= 0 else { return false }

        isSubmitting = true
        defer { isSubmitting = false }
        let request = PickingLineUpdateRequest(
            eventId: UUID().uuidString,
            deviceId: DeviceStore.shared.deviceId,
            qtyDone: quantity,
            recordVersion: detail.recordVersion,
            lotId: lotId,
            lotName: lotName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        do {
            let body = try DateCoding.encoder.encode(request)
            let endpoint = Endpoint(
                path: "/api/v1/inventory/pickings/\(pickingId)/lines/\(lineId)",
                method: "PATCH",
                body: body
            )
            let response: PickingLineUpdateResponse = try await apiClient.send(endpoint, retryOnAuth: false)
            guard response.status == "success" else {
                lastWarning = response.warnings?.first ?? "The receipt line was not updated."
                return false
            }
            self.detail = detail.replacingLine(response.line, recordVersion: response.recordVersion)
            if let updated = self.detail { try? inventoryStore.save(detail: updated) }
            lastScanStatus = "success"
            lastWarning = response.warnings?.first
            return true
        } catch {
            if let apiError = error as? APIError, case .httpStatus(409) = apiError {
                lastWarning = "This receipt changed on the server. Refresh before editing it."
                needsRefresh = true
            } else {
                lastWarning = "Couldn’t confirm this receipt edit. Refresh before trying another inventory action."
                needsRefresh = true
            }
            lastScanStatus = "failed"
            return false
        }
    }

    func createLine(
        apiClient: APIClient?,
        pickingId: Int,
        moveId: Int,
        quantity: Double,
        lotId: Int?,
        lotName: String?,
        isOnline: Bool
    ) async -> Bool {
        guard isOnline, let apiClient else {
            lastWarning = "Connect to receive this product. Offline absolute quantity edits are not queued."
            return false
        }
        guard !isSubmitting, !isLoading, !needsRefresh, let detail,
              !["done", "cancel"].contains(detail.state), quantity > 0 else { return false }

        isSubmitting = true
        defer { isSubmitting = false }
        let request = PickingLineCreateRequest(
            eventId: UUID().uuidString,
            deviceId: DeviceStore.shared.deviceId,
            moveId: moveId,
            qtyDone: quantity,
            recordVersion: detail.recordVersion,
            lotId: lotId,
            lotName: lotName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        do {
            let body = try DateCoding.encoder.encode(request)
            let endpoint = Endpoint(
                path: "/api/v1/inventory/pickings/\(pickingId)/lines",
                method: "POST",
                body: body
            )
            let response: PickingLineUpdateResponse = try await apiClient.send(endpoint, retryOnAuth: false)
            guard response.status == "success" else {
                lastWarning = response.warnings?.first ?? "The receipt line was not created."
                return false
            }
            self.detail = detail.replacingLine(response.line, recordVersion: response.recordVersion)
            if let updated = self.detail { try? inventoryStore.save(detail: updated) }
            lastScanStatus = "success"
            lastWarning = response.warnings?.first
            return true
        } catch {
            if let apiError = error as? APIError, case .httpStatus(409) = apiError {
                lastWarning = "This receipt changed on the server. Refresh before editing it."
                needsRefresh = true
            } else {
                lastWarning = "Couldn’t confirm this receipt. Refresh before trying another inventory action."
                needsRefresh = true
            }
            lastScanStatus = "failed"
            return false
        }
    }

    func validate(
        apiClient: APIClient?,
        pickingId: Int,
        isOnline: Bool,
        backorderPolicy: BackorderPolicy = .ask
    ) async {
        guard !isSubmitting, !isLoading, !needsRefresh, let detail, !["done", "cancel"].contains(detail.state) else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let request = ValidateRequest(
            eventId: UUID().uuidString,
            deviceId: DeviceStore.shared.deviceId,
            recordVersion: detail.recordVersion,
            backorderPolicy: backorderPolicy
        )
        if isOnline, let apiClient {
            do {
                let body = try DateCoding.encoder.encode(request)
                let endpoint = Endpoint(path: "/api/v1/inventory/pickings/\(pickingId)/validate", method: "POST", body: body)
                let response: ValidateResponse = try await apiClient.send(endpoint, retryOnAuth: false)
                if response.status == "needs_backorder" || response.backorderRequired == true {
                    self.detail = detail.withRecordVersion(response.recordVersion)
                    if let updated = self.detail { try? inventoryStore.save(detail: updated) }
                    needsBackorderDecision = true
                    backorderMessage = response.message
                    return
                }
                guard response.status == "success" else {
                    lastWarning = response.message ?? "Transfer was not completed. Refresh and review it in Odoo."
                    lastScanStatus = "failed"
                    needsRefresh = true
                    return
                }
                await load(apiClient: apiClient, pickingId: pickingId)
                needsBackorderDecision = false
                backorderMessage = nil
                if self.detail?.state == "done" {
                    lastScanStatus = "validated"
                    lastWarning = "Transfer completed."
                } else {
                    needsRefresh = true
                    lastWarning = "This transfer still needs attention. Check quantities, lots or backorders in Odoo."
                }
                return
            } catch {
                if let apiError = error as? APIError, case .httpStatus(409) = apiError {
                    lastWarning = "Picking updated on server. Refresh required."
                    lastScanStatus = "conflict"
                    needsRefresh = true
                    return
                }
                lastWarning = "Couldn’t confirm completion. Refresh before trying again."
                lastScanStatus = "failed"
                needsRefresh = true
                return
            }
        }

        lastWarning = "Connect before completing this transfer so Odoo can verify lots, quantities and backorders."
        lastScanStatus = "failed"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

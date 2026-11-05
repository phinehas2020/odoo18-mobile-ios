import Foundation

@MainActor
final class PackingViewModel: ObservableObject {
    @Published private(set) var detail: PackingDetail?
    @Published private(set) var capabilities: PackingCapabilities?
    @Published private(set) var isBusy = false
    @Published private(set) var requiresRefresh = false
    @Published var errorMessage: String?

    private let recoveryStore: PackingRecoveryStore
    private let deviceId: String
    private var finishVersion: Int?
    private var finishShipmentId: Int?
    private let root = "/api/v1/shopify/packing"

    init(recoveryStore: PackingRecoveryStore = PackingRecoveryStore(), deviceId: String = DeviceStore.shared.deviceId) {
        self.recoveryStore = recoveryStore
        self.deviceId = deviceId
    }

    var canUsePacking: Bool { capabilities?.enabled == true && capabilities?.canPack == true }
    var canWritePacking: Bool { canUsePacking && capabilities?.businessEnabled == true }
    var canEdit: Bool { canWritePacking && detail?.canEdit == true && !isBusy && !requiresRefresh }
    var canFinish: Bool { canWritePacking && detail?.canFinish == true && !isBusy && !requiresRefresh }

    func prepare(client: APIClient?, online: Bool, userId: Int, companyId: Int?, shipmentId: Int? = nil) async {
        guard !isBusy else { return }
        guard online, let client else { errorMessage = "Connect to open a shipping label."; return }
        isBusy = true
        defer { isBusy = false }
        do {
            capabilities = try await client.send(Endpoint(path: root + "/capabilities", method: "GET", headers: deviceHeaders))
            guard canUsePacking else { errorMessage = "Label picking is unavailable for this account. Ask a supervisor."; return }
            if let shipmentId {
                try await fetch(client: client, shipmentId: shipmentId)
            } else if let pending = recoveryStore.read(), pending.userId == userId,
                      pending.companyId == companyId, pending.deviceId == deviceId {
                requiresRefresh = true
                errorMessage = "Checking the last finish scan…"
                try await fetch(client: client, shipmentId: pending.shipmentId)
            }
        } catch { errorMessage = "Couldn’t open label picking. " + APIClient.failureMessage(error) }
    }

    func resolve(candidates: [BarcodeCandidate], client: APIClient?, online: Bool) async -> Bool {
        guard !isBusy, !requiresRefresh, canUsePacking else { return false }
        guard online, let client else { errorMessage = "Connect to look up this label."; return false }
        guard !candidates.isEmpty else { return false }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response = try await resolveLabel(candidates, client: client)
            detail = response
            cancelFinish()
            return true
        } catch {
            errorMessage = lookupMessage(error)
            return false
        }
    }

    func refresh(client: APIClient?, online: Bool) async {
        guard !isBusy, let detail else { return }
        guard online, let client else { errorMessage = "Connect to check the latest packing status."; return }
        isBusy = true
        defer { isBusy = false }
        // Fail closed while reloading the server switch and employee permissions.
        // A refresh must observe both activation and an emergency shutoff.
        capabilities = nil
        do {
            capabilities = try await client.send(Endpoint(path: root + "/capabilities", method: "GET", headers: deviceHeaders))
            guard canUsePacking else {
                cancelFinish()
                requiresRefresh = true
                errorMessage = "Label picking is unavailable for this account. Ask a supervisor."
                return
            }
            try await fetch(client: client, shipmentId: detail.shipmentId)
        }
        catch { requiresRefresh = true; errorMessage = "Couldn’t confirm the current status. " + APIClient.failureMessage(error) }
    }

    func setQuantity(lineId: Int, quantity: Double, client: APIClient?, online: Bool) async {
        guard canEdit, let detail, let item = detail.items.first(where: { $0.lineId == lineId }),
              quantity.isFinite, quantity.rounded() == quantity, quantity >= 0, quantity <= item.requiredQuantity else { return }
        guard online, let client else { errorMessage = "Connect before confirming picked items."; return }
        isBusy = true
        errorMessage = nil
        cancelFinish()
        defer { isBusy = false }
        do {
            let request = PackingQuantityRequest(quantity: quantity, version: detail.version, eventId: UUID().uuidString, deviceId: deviceId)
            let response: PackingDetail = try await client.send(
                Endpoint(path: root + "/\(detail.shipmentId)/items/\(lineId)", method: "PATCH", body: try DateCoding.encoder.encode(request)),
                retryOnAuth: false
            )
            guard response.shipmentId == detail.shipmentId else { throw APIError.invalidResponse }
            self.detail = response
        } catch {
            requiresRefresh = true
            errorMessage = "Couldn’t confirm this item. Refresh before picking more. " + operationMessage(error)
        }
    }

    // Only the explicit finish button arms a scan. Camera callbacks cannot arm it.
    @discardableResult
    func beginFinish() -> Bool {
        guard canFinish, let detail else { return false }
        finishVersion = detail.version
        finishShipmentId = detail.shipmentId
        errorMessage = nil
        return true
    }

    func cancelFinish() { finishVersion = nil; finishShipmentId = nil }

    func finish(candidates: [BarcodeCandidate], client: APIClient?, online: Bool, userId: Int, companyId: Int?) async -> Bool {
        guard canFinish, let detail, finishVersion == detail.version, finishShipmentId == detail.shipmentId else { return false }
        guard online, let client else { errorMessage = "Connect before finishing this box."; return false }
        guard !candidates.isEmpty else { return false }
        isBusy = true
        errorMessage = nil
        var completionWasSent = false
        defer { isBusy = false }
        do {
            // Resolve every camera candidate before selecting the same-label confirmation.
            let resolved = try await resolveLabel(candidates, client: client)
            guard resolved.shipmentId == detail.shipmentId else {
                errorMessage = "That label belongs to another box. Scan the label attached to this box."
                return false
            }
            guard resolved.version == detail.version, resolved.canFinish else {
                self.detail = resolved
                requiresRefresh = true
                cancelFinish()
                errorMessage = "This box changed. Refresh and review the items before finishing."
                return false
            }
            let scan: BarcodeCandidate
            if let barcode = resolved.resolvedBarcode, let symbology = resolved.resolvedSymbology {
                scan = BarcodeCandidate(barcode: barcode, symbology: symbology)
            } else if candidates.count == 1 {
                scan = candidates[0]
            } else {
                errorMessage = "Place only this label's tracking barcode in the frame and try again."
                return false
            }
            let eventId = UUID().uuidString
            let request = PackingCompleteRequest(barcode: scan.barcode, symbology: scan.symbology, version: detail.version, eventId: eventId, deviceId: deviceId)
            let body = try DateCoding.encoder.encode(request)
            recoveryStore.save(PendingPackingCompletion(shipmentId: detail.shipmentId, eventId: eventId, deviceId: deviceId, userId: userId, companyId: companyId))
            cancelFinish()
            completionWasSent = true
            let response: PackingDetail = try await client.send(
                Endpoint(path: root + "/\(detail.shipmentId)/complete", method: "POST", body: body), retryOnAuth: false
            )
            guard response.shipmentId == detail.shipmentId else { throw APIError.invalidResponse }
            self.detail = response
            if response.isPacked || response.needsReview {
                recoveryStore.clear()
                return true
            }
            requiresRefresh = true
            errorMessage = "The server hasn’t confirmed this box packed. Refresh to check its status."
            return false
        } catch {
            if completionWasSent {
                requiresRefresh = true
                errorMessage = "Finish status is uncertain. Refresh to check the server before trying again. " + operationMessage(error)
            } else { errorMessage = lookupMessage(error) }
            return false
        }
    }

    func resetForAnotherLabel() {
        guard !isBusy, !requiresRefresh else { return }
        detail = nil
        errorMessage = nil
        cancelFinish()
    }

    private var deviceHeaders: [String: String] { ["X-Device-ID": deviceId] }

    private func resolveLabel(_ candidates: [BarcodeCandidate], client: APIClient) async throws -> PackingDetail {
        guard Set(candidates).count <= 8 else {
            throw APIError.rejected(422, "Too many barcodes are visible. Place one shipping label inside the frame.")
        }
        let request = PackingResolveRequest(candidates: Array(Set(candidates)).sorted { $0.id < $1.id }, deviceId: deviceId)
        return try await client.send(Endpoint(path: root + "/resolve", method: "POST", body: try DateCoding.encoder.encode(request)))
    }

    private func fetch(client: APIClient, shipmentId: Int) async throws {
        let response: PackingDetail = try await client.send(Endpoint(path: root + "/\(shipmentId)", method: "GET", headers: deviceHeaders))
        guard response.shipmentId == shipmentId else { throw APIError.invalidResponse }
        detail = response
        requiresRefresh = false
        errorMessage = nil
        cancelFinish()
        if recoveryStore.read()?.shipmentId == shipmentId {
            recoveryStore.clear()
            if !response.isPacked && !response.needsReview {
                errorMessage = "The server shows this box still needs finishing. Review the items, then scan to finish."
            }
        }
    }

    private func lookupMessage(_ error: Error) -> String {
        if case APIError.httpStatus(409) = error { return "More than one label matches, or this label needs review. Keep one tracking barcode in the frame or ask a supervisor." }
        if case APIError.httpStatus(404) = error { return "No active shipment matches this label. Check the tracking number or ask a supervisor." }
        return "Couldn’t open this label. " + APIClient.failureMessage(error)
    }
    private func operationMessage(_ error: Error) -> String {
        if case APIError.httpStatus(409) = error { return "The box or its assigned employee changed on the server." }
        return APIClient.failureMessage(error)
    }
}

import Foundation

@MainActor
final class InventoryViewModel: ObservableObject {
    @Published var pickings: [PickingListItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(apiClient: APIClient, receiptsOnly: Bool = false) async {
        await load(apiClient: apiClient, scope: receiptsOnly ? .receipts : .myReady)
    }

    func load(apiClient: APIClient, scope: InventoryScope) async {
        guard !isLoading else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let endpoint = Endpoint(
                path: "/api/v1/inventory/pickings",
                method: "GET",
                queryItems: [
                    URLQueryItem(name: "state", value: scope.states),
                    URLQueryItem(name: "mine", value: scope == .myReady ? "1" : "0"),
                ]
            )
            let items: [PickingListItem] = try await apiClient.send(endpoint)
            if scope.pickingTypeCode != nil && items.contains(where: { $0.pickingTypeCode == nil }) {
                apiClient.recordWorkflowFailure(endpoint: "/api/v1/inventory/pickings", message: "Receipt classification unavailable: picking_type_code missing. Server API update required.")
                errorMessage = "Warehouse views need an updated Mobile Inventory API. Ask your administrator to install the transfer-type update."
                return
            }
            if let typeCode = scope.pickingTypeCode {
                pickings = items.filter { $0.pickingTypeCode == typeCode }
            } else {
                pickings = items
            }
        } catch {
            errorMessage = "Couldn’t refresh. " + APIClient.failureMessage(error)
        }
    }
}

import Foundation

@MainActor
final class InventoryViewModel: ObservableObject {
    @Published var pickings: [PickingListItem] = []
    @Published var isLoading = false

    func load(apiClient: APIClient) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let endpoint = Endpoint(
                path: "/api/v1/inventory/pickings",
                method: "GET",
                queryItems: [
                    URLQueryItem(name: "state", value: "assigned"),
                    URLQueryItem(name: "mine", value: "1"),
                ]
            )
            let items: [PickingListItem] = try await apiClient.send(endpoint)
            pickings = items
        } catch {
            pickings = []
        }
    }
}

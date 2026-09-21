import Foundation

@MainActor
final class SalesViewModel: ObservableObject {
    @Published var orders: [SaleOrderItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(apiClient: APIClient) async {
        guard !isLoading else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let endpoint = Endpoint(path: "/api/v1/sales/orders", method: "GET")
            let orders: [SaleOrderItem] = try await apiClient.send(endpoint)
            self.orders = orders
        } catch {
            errorMessage = "Couldn’t refresh. " + APIClient.failureMessage(error)
        }
    }
}

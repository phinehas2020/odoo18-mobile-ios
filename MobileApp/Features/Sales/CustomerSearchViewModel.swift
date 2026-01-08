import Foundation

@MainActor
final class CustomerSearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [CustomerItem] = []

    func search(apiClient: APIClient) async {
        guard !query.isEmpty else {
            results = []
            return
        }
        do {
            let endpoint = Endpoint(
                path: "/api/v1/sales/customers",
                method: "GET",
                queryItems: [URLQueryItem(name: "search", value: query)]
            )
            let items: [CustomerItem] = try await apiClient.send(endpoint)
            results = items
        } catch {
            results = []
        }
    }
}

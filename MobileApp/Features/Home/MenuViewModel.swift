import Foundation

@MainActor
final class MenuViewModel: ObservableObject {
    @Published var items: [MenuItem] = []
    @Published var isLoading = false

    func load(apiClient: APIClient) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let endpoint = Endpoint(path: "/api/v1/menu", method: "GET")
            let response: MenuResponse = try await apiClient.send(endpoint)
            items = response.items.filter { $0.enabled }
        } catch {
            items = []
        }
    }
}

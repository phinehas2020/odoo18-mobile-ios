import Foundation

@MainActor
final class MenuViewModel: ObservableObject {
    @Published var items: [MenuItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(apiClient: APIClient) async {
        guard !isLoading else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let endpoint = Endpoint(path: "/api/v1/menu", method: "GET")
            let response: MenuResponse = try await apiClient.send(endpoint)
            var seen = Set<String>()
            items = response.items.filter { $0.enabled && seen.insert($0.id).inserted }
        } catch {
            errorMessage = "Couldn’t refresh. " + APIClient.failureMessage(error)
        }
    }
}

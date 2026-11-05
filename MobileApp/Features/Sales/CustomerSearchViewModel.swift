import Foundation

@MainActor
final class CustomerSearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [CustomerItem] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var resultsQuery: String?

    func search(apiClient: APIClient) async {
        guard !isSearching else { return }
        guard !query.isEmpty else {
            results = []
            resultsQuery = nil
            errorMessage = nil
            return
        }
        let submittedQuery = query
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            let endpoint = Endpoint(
                path: "/api/v1/sales/customers",
                method: "GET",
                queryItems: [URLQueryItem(name: "search", value: submittedQuery)]
            )
            let items: [CustomerItem] = try await apiClient.send(endpoint)
            results = items
            resultsQuery = submittedQuery
        } catch {
            errorMessage = "Couldn’t search customers. " + APIClient.failureMessage(error)
        }
    }
}

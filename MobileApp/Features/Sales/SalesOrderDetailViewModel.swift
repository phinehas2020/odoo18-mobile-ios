import Foundation

@MainActor
final class SalesOrderDetailViewModel: ObservableObject {
    @Published var detail: SaleOrderDetail?
    @Published var noteText: String = ""
    @Published var isLoading = false

    func load(apiClient: APIClient, orderId: Int) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let endpoint = Endpoint(path: "/api/v1/sales/orders/\(orderId)", method: "GET")
            let detail: SaleOrderDetail = try await apiClient.send(endpoint)
            self.detail = detail
        } catch {
            self.detail = nil
        }
    }

    func addNote(apiClient: APIClient, orderId: Int) async {
        guard !noteText.isEmpty else { return }
        do {
            let payload = SalesNoteRequest(note: noteText)
            let body = try DateCoding.encoder.encode(payload)
            let endpoint = Endpoint(path: "/api/v1/sales/orders/\(orderId)/note", method: "POST", body: body)
            try await apiClient.sendNoResponse(endpoint)
            noteText = ""
        } catch {
            // ignore for now
        }
    }
}

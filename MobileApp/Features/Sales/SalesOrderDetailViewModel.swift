import Foundation

@MainActor
final class SalesOrderDetailViewModel: ObservableObject {
    @Published var detail: SaleOrderDetail?
    @Published var noteText: String = ""
    @Published var isLoading = false
    @Published private(set) var loadErrorMessage: String?
    @Published private(set) var isSavingNote = false
    @Published private(set) var noteErrorMessage: String?
    @Published private(set) var noteSaved = false

    func load(apiClient: APIClient, orderId: Int) async {
        guard !isLoading else { return }
        isLoading = true
        loadErrorMessage = nil
        defer { isLoading = false }
        do {
            let endpoint = Endpoint(path: "/api/v1/sales/orders/\(orderId)", method: "GET")
            let detail: SaleOrderDetail = try await apiClient.send(endpoint)
            self.detail = detail
        } catch {
            self.detail = nil
            loadErrorMessage = "Couldn’t load this order. " + APIClient.failureMessage(error)
        }
    }

    func updateNoteDraft(_ value: String) {
        noteText = value
        noteSaved = false
        noteErrorMessage = nil
    }

    func addNote(apiClient: APIClient, orderId: Int) async {
        guard !isSavingNote, !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let submittedNote = noteText
        isSavingNote = true
        noteSaved = false
        noteErrorMessage = nil
        defer { isSavingNote = false }
        do {
            let payload = SalesNoteRequest(note: submittedNote)
            let body = try DateCoding.encoder.encode(payload)
            let endpoint = Endpoint(path: "/api/v1/sales/orders/\(orderId)/note", method: "POST", body: body)
            try await apiClient.sendNoResponse(endpoint)
            if noteText == submittedNote { noteText = "" }
            noteSaved = true
        } catch {
            noteErrorMessage = "The note wasn’t confirmed saved. Your draft is kept. Check the order before trying again. " + APIClient.failureMessage(error)
        }
    }
}

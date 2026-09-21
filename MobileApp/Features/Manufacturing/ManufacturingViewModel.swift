import Foundation

@MainActor
final class ManufacturingViewModel: ObservableObject {
    @Published var orders: [ManufacturingOrder] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(client: APIClient?, dueOnly: Bool) async {
        guard !isLoading else { return }
        guard let client else { errorMessage = "Sign in to load manufacturing orders."; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            orders = try await client.send(Endpoint(path: "/api/v1/manufacturing/orders", method: "GET", queryItems: [
                URLQueryItem(name: "attention", value: dueOnly ? "due_or_late" : "all"),
                URLQueryItem(name: "limit", value: "200")
            ]))
        } catch {
            errorMessage = "Couldn’t load manufacturing orders. " + APIClient.failureMessage(error)
        }
    }
}

@MainActor
final class ManufacturingDetailViewModel: ObservableObject {
    @Published var detail: ManufacturingDetail?
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var requiresRefresh = false

    func load(client: APIClient?, id: Int) async {
        guard !isBusy else { return }
        guard let client else { errorMessage = "Sign in to load this order."; return }
        isBusy = true
        defer { isBusy = false }
        do {
            detail = try await client.send(Endpoint(path: "/api/v1/manufacturing/orders/\(id)", method: "GET"))
            errorMessage = nil
            requiresRefresh = false
        } catch {
            errorMessage = "Couldn’t refresh this order. " + APIClient.failureMessage(error)
            requiresRefresh = true
        }
    }

    func perform(client: APIClient?, workOrderId: Int, action: String) async {
        guard !isBusy, !requiresRefresh, let client, let work = detail?.workorders.first(where: { $0.id == workOrderId }) else { return }
        guard (action == "start" && work.canStart) || (action == "stop" && work.canPause) || (action == "finish" && work.canFinish) else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            // Never replay work-order actions automatically: a lost response may follow a successful write.
            detail = try await client.send(Endpoint(path: "/api/v1/manufacturing/workorders/\(workOrderId)/\(action)", method: "POST"), retryOnAuth: false)
        } catch {
            requiresRefresh = true
            errorMessage = "Couldn’t confirm the result. " + APIClient.failureMessage(error) + " Refresh before taking another action."
        }
    }
    func plan(client: APIClient?, id: Int) async {
        await update(client: client, path: "/api/v1/manufacturing/orders/\(id)/plan")
    }

    func recordQuality(client: APIClient?, check: ManufacturingQualityCheck, passed: Bool, notes: String, photo: Data? = nil) async {
        if check.controlType == "picture" {
            guard let photo else { errorMessage = "A photo is required."; return }
            struct PhotoPayload: Encodable {
                let image_base64: String
                let filename = "quality-check.jpg"
                let notes: String
            }
            guard let data = try? JSONEncoder().encode(PhotoPayload(image_base64: photo.base64EncodedString(), notes: notes)) else { return }
            await update(client: client, path: "/api/v1/manufacturing/quality-checks/\(check.id)/photo", body: data)
            return
        }
        struct QualityPayload: Encodable { let notes: String }
        guard let data = try? JSONEncoder().encode(QualityPayload(notes: notes)) else { return }
        await update(client: client, path: "/api/v1/manufacturing/quality-checks/\(check.id)/\(passed ? "pass" : "fail")", body: data)
    }

    func complete(client: APIClient?, id: Int, payload: ManufacturingCompletionPayload) async {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        await update(client: client, path: "/api/v1/manufacturing/orders/\(id)/complete", body: data)
    }

    private func update(client: APIClient?, path: String, body: Data? = nil) async {
        guard !isBusy, !requiresRefresh, let client else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            detail = try await client.send(Endpoint(path: path, method: "POST", body: body), retryOnAuth: false)
        } catch {
            requiresRefresh = true
            errorMessage = "Couldn’t confirm the result. " + APIClient.failureMessage(error) + " Refresh before trying again."
        }
    }

}

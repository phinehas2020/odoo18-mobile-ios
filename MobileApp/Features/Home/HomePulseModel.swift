import Foundation

struct FulfillmentOrder: Decodable, Identifiable {
    let id: Int
    let orderName: String?
    let customerName: String?
    let createdAt: Date?
    let state: String?
    let totalItems: Int
    let requestedShippingMethod: String?

    enum CodingKeys: String, CodingKey {
        case id, state
        case orderName = "order_name", customerName = "customer_name", createdAt = "created_at"
        case totalItems = "total_items", requestedShippingMethod = "requested_shipping_method"
    }
    var status: String {
        switch state {
        case "ready_to_ship": return "Ready to ship"
        case "pickup_pending": return "Awaiting pickup"
        case "processing": return "Processing"
        case "error", "manual_required": return "Needs review"
        default: return "Awaiting fulfillment"
        }
    }
}

struct FulfillmentPulse: Decodable {
    let generatedAt: Date
    let total, ready, needsReview, pickup: Int
    var orders: [FulfillmentOrder]
    enum CodingKeys: String, CodingKey {
        case total, ready, pickup, orders
        case generatedAt = "generated_at", needsReview = "needs_review"
    }
}

struct PulseSection<Value> {
    var value: Value?
    var updatedAt: Date?
    var error: String?
    var isLoading = false
}

struct ProductionPulse {
    let total: Int
    let running: Int
    let attention: Int
    let limited: Bool
    let rows: [ProductionPulseRow]

    init(overview: AdminWorkSnapshot) {
        total = overview.totalOrders
        running = overview.orders.filter { $0.status == "running" }.count
        attention = overview.orders.filter { $0.overdue || ["blocked", "paused", "to_close"].contains($0.status) }.count
        limited = overview.truncated
        rows = overview.orders.prefix(3).map {
            ProductionPulseRow(id: $0.id, title: $0.product, reference: $0.name,
                               detail: $0.operations.first { $0.status == "running" }?.name ?? $0.responsible,
                               status: $0.status, overdue: $0.overdue)
        }
    }

    init(orders: [ManufacturingOrder]) {
        total = orders.count
        running = orders.filter { $0.state == "progress" }.count
        attention = orders.filter { $0.attentionReason != nil || $0.state == "to_close" }.count
        limited = orders.count >= 200
        rows = orders.prefix(3).map {
            ProductionPulseRow(id: $0.id, title: $0.productName ?? $0.name, reference: $0.name,
                               detail: $0.assignedUserName,
                               status: $0.state == "progress" ? "running" : $0.state,
                               overdue: $0.attentionReason == "overdue")
        }
    }
}

struct ProductionPulseRow: Identifiable {
    let id: Int
    let title, reference: String
    let detail: String?
    let status: String
    let overdue: Bool
    var statusLabel: String {
        switch status {
        case "running": return "In progress"
        case "blocked": return "Blocked"
        case "paused": return "Paused"
        case "to_close": return "Ready to close"
        case "ready": return "Ready"
        case "draft": return "Draft"
        default: return "Waiting"
        }
    }
}

@MainActor
final class HomePulseModel: ObservableObject {
    @Published var fulfillment = PulseSection<FulfillmentPulse>()
    @Published var production = PulseSection<ProductionPulse>()
    @Published var todos = PulseSection<TodoListResponse>()

    func refresh(client: APIClient, fulfillment: Bool, manufacturing: Bool, todo: Bool, admin: Bool) async {
        async let shipping: () = fulfillment ? loadFulfillment(client: client) : clearFulfillment()
        async let work: () = manufacturing ? loadProduction(client: client, admin: admin) : clearProduction()
        async let tasks: () = todo ? loadTodos(client: client) : clearTodos()
        _ = await (shipping, work, tasks)
    }

    private func clearFulfillment() { fulfillment = .init() }
    private func clearProduction() { production = .init() }
    private func clearTodos() { todos = .init() }

    func loadFulfillment(client: APIClient) async {
        guard !fulfillment.isLoading else { return }
        fulfillment.isLoading = true
        defer { fulfillment.isLoading = false }
        do {
            let value: FulfillmentPulse = try await client.send(Endpoint(path: "/api/v1/shopify/orders/unfulfilled", method: "GET"))
            try Task.checkCancellation()
            fulfillment = PulseSection(value: value, updatedAt: Date())
        } catch {
            guard !Task.isCancelled else { return }
            if Self.isForbidden(error) { fulfillment = .init() }
            fulfillment.error = Self.message(error, feature: "Fulfillment")
        }
    }

    private func loadProduction(client: APIClient, admin: Bool) async {
        guard !production.isLoading else { return }
        production.isLoading = true
        defer { production.isLoading = false }
        do {
            let value: ProductionPulse
            if admin {
                let snapshot: AdminWorkSnapshot = try await client.send(Endpoint(path: "/api/v1/manufacturing/overview", method: "GET"))
                value = ProductionPulse(overview: snapshot)
            } else {
                let orders: [ManufacturingOrder] = try await client.send(Endpoint(path: "/api/v1/manufacturing/orders", method: "GET", queryItems: [URLQueryItem(name: "attention", value: "all"), URLQueryItem(name: "limit", value: "200")]))
                value = ProductionPulse(orders: orders)
            }
            try Task.checkCancellation()
            production = PulseSection(value: value, updatedAt: Date())
        } catch {
            guard !Task.isCancelled else { return }
            if Self.isForbidden(error) { production = .init() }
            production.error = Self.message(error, feature: "Production")
        }
    }

    private func loadTodos(client: APIClient) async {
        guard !todos.isLoading else { return }
        todos.isLoading = true
        defer { todos.isLoading = false }
        do {
            let value: TodoListResponse = try await client.send(Endpoint(path: TodoAPI.tasks, method: "GET", queryItems: [URLQueryItem(name: "status", value: "open")]))
            try Task.checkCancellation()
            todos = PulseSection(value: value, updatedAt: Date())
        } catch {
            guard !Task.isCancelled else { return }
            if Self.isForbidden(error) { todos = .init() }
            todos.error = Self.message(error, feature: "To-do")
        }
    }

    static func isForbidden(_ error: Error) -> Bool {
        if case APIError.httpStatus(403) = error { return true }
        if case APIError.rejected(403, _) = error { return true }
        return false
    }

    static func message(_ error: Error, feature: String) -> String {
        if case APIError.httpStatus(404) = error { return "\(feature) needs a server update. Your other work is still available." }
        return "Couldn’t update \(feature.lowercased()). " + APIClient.failureMessage(error)
    }
}

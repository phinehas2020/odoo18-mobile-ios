import SwiftUI

@MainActor
final class UnfulfilledOrdersModel: ObservableObject {
    @Published var snapshot: FulfillmentPulse?
    @Published var isLoading = false
    @Published var error: String?
    @Published var updatedAt: Date?
    @Published private(set) var nextOffset = 0
    var hasMore: Bool { nextOffset < (snapshot?.total ?? 0) }

    func load(client: APIClient, nextPage: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let offset = nextPage ? nextOffset : 0
            var value: FulfillmentPulse = try await client.send(Endpoint(path: "/api/v1/shopify/orders/unfulfilled", method: "GET", queryItems: [URLQueryItem(name: "offset", value: String(offset))]))
            try Task.checkCancellation()
            nextOffset = offset + value.orders.count
            if nextPage, let previous = snapshot {
                var seen = Set<Int>()
                value.orders = (previous.orders + value.orders).filter { seen.insert($0.id).inserted }
            }
            snapshot = value
            error = nil
            updatedAt = Date()
        } catch {
            guard !Task.isCancelled else { return }
            if HomePulseModel.isForbidden(error) { snapshot = nil; updatedAt = nil; nextOffset = 0 }
            self.error = HomePulseModel.message(error, feature: "Fulfillment")
        }
    }
}

struct UnfulfilledOrdersView: View {
    @EnvironmentObject private var api: APIClientProvider
    @EnvironmentObject private var network: NetworkMonitor
    @StateObject private var model = UnfulfilledOrdersModel()
    @State private var search = ""
    private var visible: [FulfillmentOrder] {
        (model.snapshot?.orders ?? []).filter { search.isEmpty || [$0.orderName, $0.customerName].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(search) } }
    }

    var body: some View {
        List {
            Section {
                if let value = model.snapshot {
                    Text("\(value.total.formatted()) unfulfilled orders").font(.title2.weight(.semibold))
                    Text("\(value.ready) ready to ship · \(value.needsReview) need review · \(value.pickup) pickups")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let due = model.snapshot?.dueToday, let overdue = model.snapshot?.overdue {
                    Text("\(overdue) overdue · \(due) due today")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(overdue > 0 ? WorkplaceTheme.attention : .secondary)
                }
                Text("Ship by noon Central on the next business day. Weekends are skipped. Earliest deadlines first; pickups follow shipping orders.")
                    .font(.caption).foregroundStyle(.secondary)
                if let date = model.updatedAt {
                    Text("Updated \(date.formatted(date: .omitted, time: .shortened))\(model.error != nil || !network.isOnline ? " · may be out of date" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.listRowBackground(Color.clear)
            if !network.isOnline { Label("Offline · showing the last update", systemImage: "wifi.slash").foregroundStyle(WorkplaceTheme.attention) }
            if let error = model.error { LoadFailureView(message: error) { Task { await reload() } } }
            if model.isLoading && model.snapshot == nil { ProgressView("Loading orders…") }
            if model.snapshot != nil && visible.isEmpty {
                ContentUnavailableView(search.isEmpty ? "All caught up" : "No matching orders", systemImage: "shippingbox", description: Text(search.isEmpty ? "There are no unfulfilled orders in the synced queue." : "Search covers the orders loaded below."))
            }
            ForEach(visible) { order in
                NavigationLink {
                    OdooWebView(title: order.orderName ?? "Order", targetURL: "/web#model=shopify.order&id=\(order.id)&view_type=form")
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(order.orderName ?? "Order \(order.id)").font(.headline)
                        if let customer = order.customerName { Text(customer).font(.subheadline) }
                        Text("\(order.totalItems) items\(order.requestedShippingMethod.map { " · " + $0 } ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(order.status).font(.caption.weight(.semibold))
                            .foregroundStyle(["error", "manual_required"].contains(order.state ?? "") ? WorkplaceTheme.attention : WorkplaceTheme.success)
                        ShippingDeadlineLabel(order: order)
                        if let date = order.createdAt { Text("Ordered " + date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 6)
                }
            }
            if let value = model.snapshot, model.hasMore {
                Section {
                    Button(model.isLoading ? "Loading…" : "Load more orders") { Task { await reload(nextPage: true) } }
                        .disabled(model.isLoading || !network.isOnline).frame(minHeight: 44)
                } footer: { Text("Showing \(value.orders.count) of \(value.total). Search covers loaded orders.") }
            }
        }
        .listStyle(.insetGrouped)
        .workplaceScreen()
        .navigationTitle("Unfulfilled orders")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Order or customer")
        .refreshable { await reload() }
        .task { await reload() }
    }
    private func reload(nextPage: Bool = false) async {
        guard let client = api.client, network.isOnline else { return }
        await model.load(client: client, nextPage: nextPage)
    }
}

/// Always format dispatch deadlines in the mill's timezone, including on traveling phones.
struct ShippingDeadlineLabel: View {
    let order: FulfillmentOrder
    var body: some View {
        if order.deadlineStatus == "pickup" {
            Label("Pickup · no shipping deadline", systemImage: "bag")
                .font(.caption).foregroundStyle(.secondary)
        } else if let date = order.shipBy {
            VStack(alignment: .leading, spacing: 3) {
                if let urgency {
                    Label(urgency, systemImage: "clock.badge.exclamationmark")
                        .font(.caption.weight(.semibold)).foregroundStyle(WorkplaceTheme.attention)
                }
                Label("Ship by " + Self.formatted(date), systemImage: "calendar")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Label("Ship-by date unavailable", systemImage: "questionmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var urgency: String? {
        switch order.deadlineStatus {
        case "overdue": return "Overdue"
        case "due_soon": return order.deadlineBasis == "amazon" ? "Due soon" : "Due soon · by noon Central"
        case "due_today": return order.deadlineBasis == "amazon" ? "Due today" : "Due today · by noon Central"
        default: return nil
        }
    }
    static func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(identifier: "America/Chicago")
        formatter.dateFormat = "EEE, MMM d 'at' h:mm a 'Central'"
        return formatter.string(from: date)
    }
}

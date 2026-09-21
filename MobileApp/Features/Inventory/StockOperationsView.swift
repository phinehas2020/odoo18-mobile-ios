import SwiftUI

struct WarehouseStockItem: Decodable, Identifiable {
    let id: Int
    let product_id: Int
    let product_name: String
    let location_id: Int
    let location_name: String
    let lot_id: Int?
    let lot_name: String?
    let quantity: Double
    let reserved_quantity: Double
    let uom_name: String?
}
private struct WarehouseStockResponse: Decodable {
    let items: [WarehouseStockItem]
    let can_adjust: Bool?
    let can_scrap: Bool?
}
private struct StockReview: Decodable {
    let record_version: String
    let current_quantity: Double?
    let counted_quantity: Double?
    let difference: Double?
    let available_quantity: Double?
    let scrap_quantity: Double?
    let scrap_location_name: String?
}

struct StockOperationsView: View {
    @EnvironmentObject private var provider: APIClientProvider
    @State private var items: [WarehouseStockItem] = []
    @State private var search = ""
    @State private var busy = false
    @State private var canAdjust = false
    @State private var canScrap = false
    @State private var errorMessage: String?
    @State private var selection: StockActionSelection?
    var body: some View {
        List {
            Section {
                Text("Search stock by product. Each row is one product, location and lot.").foregroundStyle(.secondary)
            }
            if busy { ProgressView("Checking stock…") }
            if let errorMessage { LoadFailureView(message: errorMessage) { Task { await load() } } }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.product_name).font(.headline)
                    Label(item.location_name, systemImage: "mappin.and.ellipse")
                    if let lot = item.lot_name { Label(lot, systemImage: "tag") }
                    WorkDetailRow(title: "On hand", value: "\(item.quantity.formatted()) \(item.uom_name ?? "")")
                    WorkDetailRow(title: "Reserved", value: item.reserved_quantity.formatted())
                    WorkDetailRow(title: "Available", value: (item.quantity - item.reserved_quantity).formatted())
                    if canAdjust {
                        Button { selection = .init(item: item, scrap: false) } label: { Label("Enter counted quantity", systemImage: "number").frame(minHeight: 48) }.buttonStyle(.bordered)
                    }
                    if canScrap {
                        Button { selection = .init(item: item, scrap: true) } label: { Label("Record scrap", systemImage: "trash").frame(minHeight: 48) }.buttonStyle(.bordered)
                    }
                }.padding(.vertical, 8)
            }
            if !busy && errorMessage == nil && items.isEmpty { ContentUnavailableView.search(text: search) }
            if items.count >= 50 { Text("Showing 50 stock rows. Narrow your search to find another product.").font(.footnote) }
        }
        .navigationTitle("Stock on hand")
        .searchable(text: $search, prompt: "Product or barcode")
        .task(id: search) {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            await load()
        }
        .refreshable { await load() }
        .sheet(item: $selection, onDismiss: { Task { await load() } }) { selection in
            StockActionSheet(item: selection.item, scrap: selection.scrap)
        }
    }
    private func load() async {
        guard let client = provider.client else { return }
        busy = true
        defer { busy = false }
        do {
            let response: WarehouseStockResponse = try await client.send(Endpoint(path: "/api/v1/inventory/stock", method: "GET", queryItems: [URLQueryItem(name: "query", value: search), URLQueryItem(name: "limit", value: "50")]))
            guard !Task.isCancelled else { return }
            items = response.items; canAdjust = response.can_adjust ?? false; canScrap = response.can_scrap ?? false; errorMessage = nil
        } catch { if !Task.isCancelled { errorMessage = APIClient.failureMessage(error) } }
    }
}
private struct StockActionSelection: Identifiable {
    let id = UUID()
    let item: WarehouseStockItem
    let scrap: Bool
}
private struct StockActionSheet: View {
    let item: WarehouseStockItem
    let scrap: Bool
    @EnvironmentObject private var provider: APIClientProvider
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = ""
    @State private var review: StockReview?
    @State private var busy = false
    @State private var attempted = false
    @State private var confirmed = false
    @State private var errorMessage: String?
    private var path: String { scrap ? "scraps" : "adjustments" }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.product_name).font(.headline)
                    Text(item.location_name)
                    if let lot = item.lot_name { Text("Lot: \(lot)") }
                    TextField(scrap ? "Quantity to scrap" : "Actual counted quantity", text: $quantity).keyboardType(.decimalPad)
                        .disabled(review != nil)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                if let review {
                    Section("Review stock change") {
                        if let current = review.current_quantity { WorkDetailRow(title: "Recorded quantity", value: current.formatted()) }
                        if let counted = review.counted_quantity { WorkDetailRow(title: "Counted quantity", value: counted.formatted()) }
                        if let difference = review.difference { WorkDetailRow(title: "Adjustment", value: difference.formatted()) }
                        if let available = review.available_quantity { WorkDetailRow(title: "Available", value: available.formatted()) }
                        if let quantity = review.scrap_quantity { WorkDetailRow(title: "Scrap quantity", value: quantity.formatted()) }
                        if let destination = review.scrap_location_name { WorkDetailRow(title: "Scrap location", value: destination) }
                        Toggle("I verified this physical quantity", isOn: $confirmed)
                        Button(scrap ? "Confirm scrap" : "Apply counted quantity", role: scrap ? .destructive : nil) { Task { await apply() } }
                            .buttonStyle(.borderedProminent).frame(minHeight: 52)
                            .disabled(!confirmed || attempted)
                        if !attempted { Button("Edit quantity") { self.review = nil; confirmed = false } }
                    }
                } else {
                    Button("Review change") { Task { await loadReview() } }
                        .buttonStyle(.borderedProminent).frame(minHeight: 52)
                        .disabled(warehouseQuantity(quantity) == nil || (scrap && (warehouseQuantity(quantity) ?? 0) <= 0))
                }
                if busy { ProgressView("Checking stock change…") }
            }
            .disabled(busy)
            .navigationTitle(scrap ? "Record scrap" : "Count stock")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
        }
    }
    private func body(apply: Bool) throws -> Data {
        var payload: [String: Any] = ["quant_id": item.id, scrap ? "quantity" : "counted_quantity": warehouseQuantity(quantity) ?? 0]
        if apply {
            payload["record_version"] = review?.record_version
            payload["reviewed"] = true
            payload["event_id"] = UUID().uuidString
            payload["device_id"] = DeviceStore.shared.deviceId
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }
    private func loadReview() async {
        guard let client = provider.client else { return }
        busy = true; errorMessage = nil
        defer { busy = false }
        do { review = try await client.send(Endpoint(path: "/api/v1/inventory/\(path)/review", method: "POST", body: try body(apply: false))) }
        catch { errorMessage = APIClient.failureMessage(error) }
    }
    private func apply() async {
        guard let client = provider.client, review != nil, !attempted else { return }
        busy = true; attempted = true; errorMessage = nil
        defer { busy = false }
        struct Result: Decodable { let status: String }
        do {
            let result: Result = try await client.send(Endpoint(path: "/api/v1/inventory/\(path)/apply", method: "POST", body: try body(apply: true)), retryOnAuth: false)
            if result.status == "success" { dismiss() }
            else { errorMessage = "Odoo did not confirm this change. Close and refresh stock before trying again." }
        } catch { errorMessage = APIClient.failureMessage(error) + " Close and refresh stock before another attempt." }
    }
}

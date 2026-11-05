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
    @Environment(\.dynamicTypeSize) private var textSize
    private var productHeaderLayout: AnyLayout {
        textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }
    var body: some View {
        List {
            if busy { ProgressView("Checking stock…").frame(maxWidth: .infinity, minHeight: 60) }
            if let errorMessage { LoadFailureView(message: errorMessage) { Task { await load() } } }
            Section("Products and locations") {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 14) {
                        productHeaderLayout {
                            Text(item.product_name).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityAddTraits(.isHeader)
                            if canAdjust || canScrap {
                                Menu {
                                    if canAdjust {
                                        Button("Count stock", systemImage: "number") { selection = .init(item: item, scrap: false) }
                                            .accessibilityLabel("Count \(item.product_name) at \(item.location_name)")
                                    }
                                    if canScrap {
                                        Button("Record scrap", systemImage: "trash", role: .destructive) { selection = .init(item: item, scrap: true) }
                                            .accessibilityLabel("Record scrap for \(item.product_name) at \(item.location_name)")
                                    }
                                } label: {
                                    Label("Actions", systemImage: "ellipsis.circle")
                                        .font(.subheadline).frame(minWidth: 44, minHeight: 44)
                                }
                                .accessibilityLabel("Actions for \(item.product_name)")
                                .accessibilityValue("\(item.location_name)\(item.lot_name.map { ", lot " + $0 } ?? "")")
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Label(item.location_name, systemImage: "mappin.and.ellipse")
                            if let lot = item.lot_name { Label("Lot: \(lot)", systemImage: "tag") }
                        }.font(.subheadline).foregroundStyle(.secondary)
                        WorkplaceMetric(title: "Available", value: "\((item.quantity - item.reserved_quantity).formatted()) \(item.uom_name ?? "")",
                            symbol: "shippingbox", tint: item.quantity - item.reserved_quantity < 0 ? WorkplaceTheme.attention : WorkplaceTheme.accent)
                        VStack(spacing: 6) {
                            WorkDetailRow(title: "On hand", value: "\(item.quantity.formatted()) \(item.uom_name ?? "")")
                            WorkDetailRow(title: "Reserved", value: item.reserved_quantity.formatted())
                        }
                    }
                    .controlSize(.large)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .contain)
                }
            }
            if !busy && errorMessage == nil && items.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView("No stock to show", systemImage: "shippingbox",
                        description: Text("Pull down to check the latest stock, or search for a product."))
                } else { ContentUnavailableView.search(text: search) }
            }
            if items.count >= 50 {
                Text("Showing 50 stock rows. Narrow your search to find another product.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.vertical, 6)
            }
        }
        .listStyle(.insetGrouped)
        .workplaceScreen()
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
    @State private var confirmDiscard = false
    @FocusState private var quantityFocused: Bool
    private var hasUnsavedChanges: Bool { !attempted && (!quantity.isEmpty || confirmed) }
    private var path: String { scrap ? "scraps" : "adjustments" }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.product_name).font(.headline).accessibilityAddTraits(.isHeader)
                    Label(item.location_name, systemImage: "mappin.and.ellipse")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let lot = item.lot_name {
                        Label("Lot: \(lot)", systemImage: "tag").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section(scrap ? "Quantity to scrap" : "Physical count") {
                    TextField(scrap ? "Quantity to scrap" : "Actual counted quantity", text: $quantity).keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold)).monospacedDigit().frame(minHeight: 44)
                        .disabled(review != nil)
                        .focused($quantityFocused)
                        .accessibilityLabel("\(scrap ? "Quantity to scrap" : "Physically counted quantity") for \(item.product_name)")
                        .accessibilityValue("\(quantity) \(item.uom_name ?? "")")
                    Text(item.uom_name.map { "Quantity in \($0)." } ?? "Enter the quantity you physically verified.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Section {
                        WorkplaceNotice(title: "Stock change needs attention", message: errorMessage,
                            symbol: "exclamationmark.circle", tint: WorkplaceTheme.danger)
                    }
                }
                if let review {
                    Section("Review stock change") {
                        if let current = review.current_quantity { WorkDetailRow(title: "Recorded quantity", value: current.formatted()) }
                        if let counted = review.counted_quantity { WorkDetailRow(title: "Counted quantity", value: counted.formatted()) }
                        if let difference = review.difference { WorkDetailRow(title: "Adjustment", value: difference.formatted()) }
                        if let available = review.available_quantity { WorkDetailRow(title: "Available", value: available.formatted()) }
                        if let quantity = review.scrap_quantity { WorkDetailRow(title: "Scrap quantity", value: quantity.formatted()) }
                        if let destination = review.scrap_location_name { WorkDetailRow(title: "Scrap location", value: destination) }
                    }
                    Section {
                        Toggle("I verified this physical quantity", isOn: $confirmed).frame(minHeight: 44)
                            .accessibilityLabel("I verified the physical quantity of \(item.product_name)")
                        Button(role: scrap ? .destructive : nil) { Task { await apply() } } label: {
                            Label(scrap ? "Confirm scrap" : "Apply counted quantity", systemImage: scrap ? "trash" : "checkmark.circle")
                                .fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 28)
                        }
                            .buttonStyle(.borderedProminent).tint(scrap ? WorkplaceTheme.dangerFill : WorkplaceTheme.buttonFill)
                            .controlSize(.large)
                            .disabled(!confirmed || attempted)
                            .accessibilityLabel("\(scrap ? "Confirm scrap for" : "Apply counted quantity for") \(item.product_name)")
                        if !attempted {
                            Button("Edit quantity") { self.review = nil; confirmed = false; quantityFocused = true }
                                .frame(minHeight: 44)
                                .accessibilityLabel("Edit \(scrap ? "scrap" : "counted") quantity for \(item.product_name)")
                        }
                    }
                } else {
                    Section {
                        Button { quantityFocused = false; Task { await loadReview() } } label: {
                            Label(scrap ? "Review scrap" : "Review count", systemImage: "checklist")
                                .fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 28)
                        }
                            .buttonStyle(.borderedProminent).tint(scrap ? WorkplaceTheme.dangerFill : WorkplaceTheme.buttonFill)
                            .controlSize(.large)
                            .disabled(warehouseQuantity(quantity) == nil || (scrap && (warehouseQuantity(quantity) ?? 0) <= 0))
                            .accessibilityLabel("Review \(scrap ? "scrap" : "count") for \(item.product_name)")
                    } footer: {
                        Text("Review the change before applying it to inventory.")
                    }
                }
                if busy { ProgressView("Checking stock change…").frame(maxWidth: .infinity, minHeight: 44) }
            }
            .disabled(busy)
            .scrollDismissesKeyboard(.interactively)
            .workplaceScreen()
            .navigationTitle(scrap ? "Record scrap" : "Count stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(attempted ? "Close" : "Cancel") { cancel() }.disabled(busy)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { quantityFocused = false }
                }
            }
            .confirmationDialog("Discard stock draft?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: { Text("The \(scrap ? "scrap quantity" : "physical count") for \(item.product_name) hasn’t been applied.") }
            .interactiveDismissDisabled(busy || hasUnsavedChanges)
        }
    }
    private func cancel() {
        quantityFocused = false
        if hasUnsavedChanges { confirmDiscard = true } else { dismiss() }
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

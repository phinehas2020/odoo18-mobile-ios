import SwiftUI

struct ManufacturingCreateSheet: View {
    let onCreated: () -> Void
    @EnvironmentObject private var provider: APIClientProvider
    @Environment(\.dismiss) private var dismiss
    @State private var product: ManufacturingProduct?
    @State private var quantity = ""
    @State private var assignees: [ManufacturingAssignee] = []
    @State private var assigneeId: Int?
    @State private var hasDeadline = false
    @State private var deadline = Date()
    @State private var notes = ""
    @State private var busy = false
    @State private var attempted = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("What needs to be made?") {
                    NavigationLink {
                        ManufacturingProductPicker(selected: $product)
                    } label: { LabeledContent("Product", value: product?.name ?? "Choose a product") }
                    TextField("Quantity to produce", text: $quantity).keyboardType(.decimalPad)
                    if let unit = product?.uomName { Text("Unit: \(unit)").foregroundStyle(.secondary) }
                }
                Section("Responsibility and timing") {
                    Picker("Assign to", selection: $assigneeId) {
                        Text("Me").tag(nil as Int?)
                        ForEach(assignees) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Toggle("Set a deadline", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("Deadline", selection: $deadline) }
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...6)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                Section {
                    Text("Review the product, quantity and responsible person. This creates a manufacturing order in Odoo.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button { create() } label: {
                        Label("Create manufacturing order", systemImage: "plus.circle.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    }.buttonStyle(.borderedProminent)
                    .disabled(product == nil || (warehouseQuantity(quantity) ?? 0) <= 0 || busy || attempted || notes.count > 2000)
                }
                if busy { ProgressView("Creating order…") }
            }
            .disabled(busy)
            .navigationTitle("New production")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .task {
                guard let client = provider.client else { return }
                do { assignees = try await client.send(Endpoint(path: "/api/v1/manufacturing/assignees", method: "GET")) }
                catch { errorMessage = "Couldn’t load assignees. " + APIClient.failureMessage(error) }
            }
        }
    }
    private func create() {
        guard let product, let quantity = warehouseQuantity(quantity), quantity > 0, let client = provider.client, !attempted else { return }
        struct Payload: Encodable {
            let product_id: Int
            let quantity: Double
            let assigned_user_id: Int?
            let deadline: Date?
            let notes: String
        }
        struct Response: Decodable { let order: ManufacturingOrder }
        busy = true; attempted = true; errorMessage = nil
        Task {
            defer { busy = false }
            do {
                let body = try DateCoding.encoder.encode(Payload(product_id: product.id, quantity: quantity, assigned_user_id: assigneeId, deadline: hasDeadline ? deadline : nil, notes: notes))
                let _: Response = try await client.send(Endpoint(path: "/api/v1/manufacturing/orders", method: "POST", body: body), retryOnAuth: false)
                onCreated(); dismiss()
            } catch {
                errorMessage = "Couldn’t confirm creation. " + APIClient.failureMessage(error) + " Close and refresh the order list before trying again."
            }
        }
    }
}

struct ManufacturingProductPicker: View {
    @Binding var selected: ManufacturingProduct?
    @EnvironmentObject private var provider: APIClientProvider
    @Environment(\.dismiss) private var dismiss
    @State private var products: [ManufacturingProduct] = []
    @State private var search = ""
    @State private var errorMessage: String?
    @State private var busy = false
    var body: some View {
        List {
            if busy { ProgressView("Finding products…") }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            ForEach(products) { product in
                Button { selected = product; dismiss() } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(product.name).font(.headline)
                        if let unit = product.uomName { Text(unit).foregroundStyle(.secondary) }
                    }.frame(minHeight: 48)
                }
            }
            if !busy && errorMessage == nil && products.isEmpty { Text("No matching products.") }
        }
        .navigationTitle("Choose product")
        .searchable(text: $search)
        .task(id: search) {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let client = provider.client else { return }
            busy = true
            defer { busy = false }
            do {
                let result: [ManufacturingProduct] = try await client.send(Endpoint(path: "/api/v1/manufacturing/products", method: "GET", queryItems: [URLQueryItem(name: "search", value: search)]))
                guard !Task.isCancelled else { return }
                products = result; errorMessage = nil
            } catch { if !Task.isCancelled { errorMessage = APIClient.failureMessage(error) } }
        }
    }
}

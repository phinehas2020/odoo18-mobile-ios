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
    @State private var showDiscardConfirmation = false
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case quantity, notes }

    private var hasUnsavedChanges: Bool {
        !attempted && (product != nil || !quantity.isEmpty || assigneeId != nil || hasDeadline || !notes.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    WorkplaceHeader(title: "Plan a production run", subtitle: "Choose what to make, then set its quantity and owner.", symbol: "gearshape.2")
                }
                Section("Product and Quantity") {
                    NavigationLink {
                        ManufacturingProductPicker(selected: $product)
                    } label: {
                        WorkplaceActionLabel(title: product?.name ?? "Choose a product", subtitle: "Product", symbol: "shippingbox", emphasized: product != nil)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quantity").font(.subheadline.weight(.medium))
                        TextField("Quantity to produce", text: $quantity).keyboardType(.decimalPad).font(.title3.weight(.semibold)).monospacedDigit()
                            .focused($focusedField, equals: .quantity)
                            .accessibilityLabel("Quantity to produce for \(product?.name ?? "the selected product")")
                            .accessibilityHint((product?.uomName).map { "Enter the amount in \($0)." } ?? "Choose a product to see its unit.")
                        if let unit = product?.uomName { Text("Unit: \(unit)").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 6)
                }
                Section("Responsibility and Timing") {
                    Picker("Assign to", selection: $assigneeId) {
                        Text("Me").tag(nil as Int?)
                        ForEach(assignees) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Toggle("Set a deadline", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("Deadline", selection: $deadline) }
                }
                Section("Production Notes") {
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...6).padding(.vertical, 6)
                        .focused($focusedField, equals: .notes).accessibilityLabel("Production notes")
                }
                if let errorMessage {
                    WorkplaceNotice(title: "Order needs attention", message: errorMessage, symbol: "exclamationmark.triangle", tint: WorkplaceTheme.danger)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)).listRowBackground(Color.clear)
                }
                Section {
                    Button { create() } label: {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? "Creating Order…" : "Create Order")
                        }.frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(WorkplaceTheme.buttonFill)
                    .controlSize(.large)
                    .disabled(product == nil || (warehouseQuantity(quantity) ?? 0) <= 0 || busy || attempted || notes.count > 2000)
                }
            }
            .workplaceScreen()
            .disabled(busy)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Production")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if attempted {
                        if #available(iOS 26, *) {
                            Button(role: .close) { dismiss() }.disabled(busy)
                        } else {
                            Button { dismiss() } label: { Label("Close", systemImage: "xmark") }.labelStyle(.iconOnly).disabled(busy)
                        }
                    } else {
                        Button("Cancel", role: .cancel) { requestDismiss() }.disabled(busy)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .interactiveDismissDisabled(busy || hasUnsavedChanges)
            .confirmationDialog("Discard Production Draft?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard Draft", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("The product, quantity, and notes you entered will be lost.")
            }
            .task {
                guard let client = provider.client else { return }
                do { assignees = try await client.send(Endpoint(path: "/api/v1/manufacturing/assignees", method: "GET")) }
                catch { errorMessage = "Couldn’t load assignees. " + APIClient.failureMessage(error) }
            }
        }
    }
    private func requestDismiss() {
        focusedField = nil
        if hasUnsavedChanges { showDiscardConfirmation = true }
        else { dismiss() }
    }
    private func create() {
        guard let product, let quantity = warehouseQuantity(quantity), quantity > 0, let client = provider.client, !attempted else { return }
        focusedField = nil
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
            if busy { ProgressView("Finding products…").frame(maxWidth: .infinity).padding(.vertical, 12) }
            if let errorMessage {
                WorkplaceNotice(title: "Couldn’t load products", message: errorMessage, symbol: "exclamationmark.triangle", tint: WorkplaceTheme.danger)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)).listRowBackground(Color.clear)
            }
            ForEach(products) { product in
                Button { selected = product; dismiss() } label: {
                    HStack(alignment: .top, spacing: 14) {
                        WorkplaceIcon(symbol: "shippingbox")
                        VStack(alignment: .leading, spacing: 6) {
                            Text(product.name).font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                            if let unit = product.uomName { Text(unit).font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if selected?.id == product.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(WorkplaceTheme.accent) }
                    }.frame(minHeight: 48).padding(.vertical, 6)
                }.accessibilityLabel("\(product.name)\(product.uomName.map { ", \($0)" } ?? "")")
                    .accessibilityValue(selected?.id == product.id ? "Selected" : "")
            }
            if !busy && errorMessage == nil && products.isEmpty {
                ContentUnavailableView("No matching products", systemImage: "shippingbox", description: Text("Try another product name."))
            }
        }
        .workplaceScreen()
        .navigationTitle("Choose Product")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Product name")
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

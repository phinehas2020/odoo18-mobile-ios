import SwiftUI

private struct ReturnReview: Decodable {
    let picking_id: Int
    let picking_name: String
    let record_version: String
    let lines: [Line]
    struct Line: Decodable, Identifiable {
        let move_id: Int
        let product_name: String
        let quantity: Double
        let uom_name: String?
        var id: Int { move_id }
    }
}
private struct ReturnResult: Decodable {
    let status: String
    let new_picking_id: Int
    let new_picking_name: String
}

struct TransferReturnSheet: View {
    let pickingId: Int
    @EnvironmentObject private var provider: APIClientProvider
    @Environment(\.dismiss) private var dismiss
    @State private var review: ReturnReview?
    @State private var quantities: [Int: String] = [:]
    @State private var result: ReturnResult?
    @State private var confirmed = false
    @State private var busy = false
    @State private var attempted = false
    @State private var errorMessage: String?
    @State private var confirmDiscard = false
    @FocusState private var focusedLine: Int?
    private var hasUnsavedChanges: Bool {
        result == nil && !attempted && (confirmed || quantities.values.contains { !$0.isEmpty })
    }
    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    Section {
                        WorkplaceHeader(title: "Return transfer created", subtitle: result.new_picking_name, symbol: "checkmark.circle.fill")
                    }
                    Section {
                        NavigationLink { InventoryDetailView(pickingId: result.new_picking_id) } label: {
                            WorkplaceActionLabel(title: "Open return and process goods", subtitle: "Record the products received back into stock.", symbol: "arrow.uturn.backward", emphasized: true)
                        }
                        Text("The return still needs to be physically processed and completed.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if let review {
                    Section {
                        Text(review.picking_name).font(.headline).accessibilityAddTraits(.isHeader)
                        Text("Leave products you’re keeping at zero.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Section("Return quantities") {
                        ForEach(review.lines) { line in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(line.product_name).font(.headline)
                                Text("Up to \(line.quantity.formatted()) \(line.uom_name ?? "")")
                                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                                TextField("Quantity to return", text: Binding(get: { quantities[line.id] ?? "" }, set: { quantities[line.id] = $0 }))
                                    .keyboardType(.decimalPad)
                                    .font(.title2.weight(.semibold)).monospacedDigit().frame(minHeight: 44)
                                    .focused($focusedLine, equals: line.id)
                                    .accessibilityLabel("Quantity to return for \(line.product_name)")
                                    .accessibilityValue("\(quantities[line.id] ?? "0") \(line.uom_name ?? "")")
                                    .accessibilityHint("Maximum \(line.quantity.formatted()) \(line.uom_name ?? "")")
                            }.padding(.vertical, 8)
                        }
                    }
                    Section {
                        Toggle("I verified the return quantities", isOn: $confirmed).frame(minHeight: 44)
                            .accessibilityLabel("I verified return quantities for \(review.picking_name)")
                        Button { focusedLine = nil; Task { await create() } } label: {
                            Label("Create return", systemImage: "arrow.uturn.backward")
                                .fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 28)
                        }
                            .buttonStyle(.borderedProminent).tint(WorkplaceTheme.buttonFill)
                            .controlSize(.large)
                            .disabled(!confirmed || selectedLines == nil || attempted)
                            .accessibilityLabel("Create return for \(review.picking_name)")
                    }
                }
                if let errorMessage {
                    Section {
                        WorkplaceNotice(title: "Return needs attention", message: errorMessage,
                            symbol: "exclamationmark.circle", tint: WorkplaceTheme.danger)
                        if review == nil && !attempted {
                            Button("Try again") { self.errorMessage = nil; Task { await load() } }.frame(minHeight: 44)
                        }
                    }
                }
                if busy { ProgressView("Checking return…").frame(maxWidth: .infinity, minHeight: 60) }
            }
            .disabled(busy)
            .scrollDismissesKeyboard(.interactively)
            .workplaceScreen()
            .navigationTitle("Return goods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result != nil || attempted ? "Close" : "Cancel") { cancel() }.disabled(busy)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if let nextLine = nextLine {
                        Button("Next") { focusedLine = nextLine }
                    }
                    Spacer()
                    Button("Done") { focusedLine = nil }
                }
            }
            .confirmationDialog("Discard return draft?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: { Text("The return quantities haven’t been submitted.") }
            .interactiveDismissDisabled(busy || hasUnsavedChanges)
            .task { await load() }
        }
    }
    private var nextLine: Int? {
        guard let review, let focusedLine,
              let index = review.lines.firstIndex(where: { $0.id == focusedLine }),
              index + 1 < review.lines.count else { return nil }
        return review.lines[index + 1].id
    }
    private func cancel() {
        focusedLine = nil
        if hasUnsavedChanges { confirmDiscard = true } else { dismiss() }
    }
    private var selectedLines: [[String: Any]]? {
        guard let review else { return nil }
        var selected: [[String: Any]] = []
        for line in review.lines {
            let text = quantities[line.id] ?? ""
            if text.isEmpty { continue }
            guard let quantity = warehouseQuantity(text), quantity <= line.quantity else { return nil }
            if quantity > 0 { selected.append(["move_id": line.id, "quantity": quantity]) }
        }
        return selected.isEmpty ? nil : selected
    }
    private func load() async {
        guard let client = provider.client else { return }
        busy = true
        defer { busy = false }
        do { review = try await client.send(Endpoint(path: "/api/v1/inventory/pickings/\(pickingId)/returns/review", method: "POST", body: Data("{}".utf8))) }
        catch { errorMessage = APIClient.failureMessage(error) }
    }
    private func create() async {
        guard let client = provider.client, let review, let lines = selectedLines, !attempted else { return }
        busy = true; attempted = true; errorMessage = nil
        defer { busy = false }
        do {
            let payload: [String: Any] = ["event_id": UUID().uuidString, "device_id": DeviceStore.shared.deviceId,
                                          "record_version": review.record_version, "reviewed": true, "lines": lines]
            let response: ReturnResult = try await client.send(Endpoint(path: "/api/v1/inventory/pickings/\(pickingId)/returns/apply", method: "POST", body: try JSONSerialization.data(withJSONObject: payload)), retryOnAuth: false)
            if response.status == "success" { result = response }
            else { errorMessage = "Return was not confirmed. Close and refresh before trying again." }
        } catch { errorMessage = APIClient.failureMessage(error) + " Close and refresh before another attempt." }
    }
}

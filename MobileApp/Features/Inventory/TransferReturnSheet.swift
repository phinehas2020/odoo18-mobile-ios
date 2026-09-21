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
    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    Section {
                        Label("Return transfer created", systemImage: "checkmark.circle.fill").font(.headline)
                        Text(result.new_picking_name)
                        NavigationLink("Open return and process goods") { InventoryDetailView(pickingId: result.new_picking_id) }
                        Text("The return still needs to be physically processed and completed.").foregroundStyle(.secondary)
                    }
                } else if let review {
                    Section {
                        Text(review.picking_name).font(.headline)
                        Text("Enter only the quantities being returned. Leave other products at zero.").foregroundStyle(.secondary)
                    }
                    Section("Return quantities") {
                        ForEach(review.lines) { line in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(line.product_name).font(.headline)
                                Text("Up to \(line.quantity.formatted()) \(line.uom_name ?? "")").foregroundStyle(.secondary)
                                TextField("Quantity to return", text: Binding(get: { quantities[line.id] ?? "" }, set: { quantities[line.id] = $0 }))
                                    .keyboardType(.decimalPad)
                            }.padding(.vertical, 6)
                        }
                    }
                    Section {
                        Toggle("I verified the return quantities", isOn: $confirmed)
                        Button("Create return transfer") { Task { await create() } }
                            .buttonStyle(.borderedProminent).frame(minHeight: 52)
                            .disabled(!confirmed || selectedLines == nil || attempted)
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                if busy { ProgressView("Checking return…") }
            }
            .disabled(busy)
            .navigationTitle("Return goods")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .task { await load() }
        }
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

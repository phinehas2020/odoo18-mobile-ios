import SwiftUI

struct ManufacturingCompletionSheet: View {
    let detail: ManufacturingDetail
    let save: (ManufacturingCompletionPayload) async -> Bool
    @EnvironmentObject private var provider: APIClientProvider
    @Environment(\.dismiss) private var dismiss
    @State private var review: ManufacturingCompletionReview?
    @State private var quantity = ""
    @State private var lotName = ""
    @State private var disposition = "backorder"
    @State private var allocations: [ConsumptionDraft] = []
    @State private var inspected = false
    @State private var busy = false
    @State private var attempted = false
    @State private var errorMessage: String?

    struct ConsumptionDraft: Identifiable {
        let id = UUID()
        let component: ManufacturingComponent
        var quantity = ""
        var lot: ManufacturingLot?
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(detail.productName ?? detail.name).font(.title2.bold())
                    Text("Record the quantities actually produced and consumed. This completes production in Odoo.")
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                if let review {
                    if !review.blockers.isEmpty {
                        Section("Resolve before completing") {
                            ForEach(Array(review.blockers.enumerated()), id: \.offset) { _, text in Label(text, systemImage: "exclamationmark.triangle") }
                        }
                    }
                    if !review.warnings.isEmpty {
                        Section("Review carefully") {
                            ForEach(Array(review.warnings.enumerated()), id: \.offset) { _, text in Text(text) }
                        }
                    }
                    Section("Finished product") {
                        Text("Remaining: \(review.quantityRemaining.formatted()) \(detail.uomName ?? "")")
                        if detail.productTracking == "serial" { Text("Complete one finished serial number at a time. Enter a produced quantity of 1.").foregroundStyle(.secondary) }
                        TextField("Quantity produced", text: $quantity).keyboardType(.decimalPad)
                        if review.requiresFinishedLot {
                            TextField("Finished lot or serial number", text: $lotName).textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                        Picker("Unfinished quantity", selection: $disposition) {
                            Text("Create a backorder").tag("backorder")
                            Text("Close without a backorder").tag("close")
                        }
                        if disposition == "close", (warehouseQuantity(quantity) ?? review.quantityRemaining) < review.quantityRemaining { Text("Any remaining production quantity will not be backordered.").foregroundStyle(.secondary) }
                    }
                    Section("Final actual component consumption") {
                        Text("Enter the total actually consumed for this production, not an additional amount. Recorded consumption is shown for comparison.").font(.subheadline).foregroundStyle(.secondary)
                        ForEach($allocations) { $allocation in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(allocation.component.productName).font(.headline)
                                Text("Planned: \(allocation.component.quantity.formatted()) \(allocation.component.uomName ?? "")").foregroundStyle(.secondary)
                                if let recorded = allocation.component.doneQuantity { Text("Recorded total: \(recorded.formatted())").font(.subheadline).foregroundStyle(.secondary) }
                                TextField("Quantity consumed", text: $allocation.quantity).keyboardType(.decimalPad)
                                if let tracking = allocation.component.tracking, tracking != "none" {
                                    NavigationLink {
                                        ManufacturingLotPicker(productId: allocation.component.productId, selected: $allocation.lot)
                                    } label: {
                                        Label(allocation.lot?.name ?? "Choose a lot or serial number", systemImage: "tag")
                                    }
                                    if allocations.filter({ $0.component.id == allocation.component.id }).count > 1 {
                                        Button("Remove this allocation", role: .destructive) {
                                            allocations.removeAll { $0.id == allocation.id }
                                        }.buttonStyle(.bordered)
                                    }
                                    Button("Add another lot allocation") {
                                        allocations.append(ConsumptionDraft(component: allocation.component))
                                    }.buttonStyle(.bordered)
                                }
                            }.padding(.vertical, 6)
                        }
                    }
                    Section {
                        if payload == nil {
                            Text("Enter the produced quantity and every component’s actual consumption. Use 0 for unused components and choose lots for tracked quantities.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Toggle("I checked quantities, lots and completed operations", isOn: $inspected)
                        Button {
                            submit()
                        } label: {
                            Label("Complete production", systemImage: "checkmark.seal.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                        }.buttonStyle(.borderedProminent)
                        .disabled(!review.canComplete || !inspected || payload == nil || busy || attempted)
                    }
                } else if !busy && errorMessage != nil {
                    Button("Reload review") { Task { await load() } }
                }
                if busy { ProgressView("Checking production…") }
            }
            .disabled(busy)
            .navigationTitle("Review production")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .task {
                allocations = detail.components.flatMap { component -> [ConsumptionDraft] in
                    if let lots = component.lotQuantities, !lots.isEmpty {
                        return lots.map { lot in
                            ConsumptionDraft(component: component,
                                             quantity: component.picked == true ? lot.quantity.formatted(.number.grouping(.never)) : "",
                                             lot: lot.lotId.map { ManufacturingLot(id: $0, name: lot.lotName ?? "Recorded lot") })
                        }
                    }
                    return [ConsumptionDraft(component: component, quantity: component.picked == true ? (component.doneQuantity?.formatted(.number.grouping(.never)) ?? "") : "")]
                }
                lotName = detail.finishedLotName ?? ""
                await load()
            }
        }
    }

    private var payload: ManufacturingCompletionPayload? {
        guard let quantity = warehouseQuantity(quantity), quantity > 0, let review,
              quantity <= review.quantityRemaining else { return nil }
        guard detail.productTracking != "serial" || quantity == 1 else { return nil }
        let name = lotName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !review.requiresFinishedLot || !name.isEmpty else { return nil }
        var rows: [ManufacturingCompletionPayload.Component] = []
        for allocation in allocations {
            guard let used = warehouseQuantity(allocation.quantity), used >= 0 else { return nil }
            if allocation.component.tracking == "serial" && used != 0 && used != 1 { return nil }
            if used > 0, let tracking = allocation.component.tracking, tracking != "none", allocation.lot == nil { return nil }
            rows.append(.init(moveId: allocation.component.id, quantity: used, lotId: allocation.lot?.id))
        }
        return .init(quantity: quantity, disposition: quantity >= review.quantityRemaining ? "close" : disposition, finishedLotName: name.isEmpty ? nil : name, components: rows)
    }
    private func load() async {
        guard let client = provider.client else { errorMessage = "Sign in to review this order."; return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do { review = try await client.send(Endpoint(path: "/api/v1/manufacturing/orders/\(detail.id)/completion-review", method: "GET")) }
        catch { errorMessage = APIClient.failureMessage(error) }
    }
    private func submit() {
        guard let payload, !busy, !attempted else { return }
        busy = true
        attempted = true
        Task {
            let success = await save(payload)
            busy = false
            if success { dismiss() }
            else { errorMessage = "Couldn’t confirm completion. Close and refresh the order before another attempt." }
        }
    }
}

struct ManufacturingLotPicker: View {
    let productId: Int?
    @Binding var selected: ManufacturingLot?
    @EnvironmentObject private var provider: APIClientProvider
    @Environment(\.dismiss) private var dismiss
    @State private var lots: [ManufacturingLot] = []
    @State private var search = ""
    @State private var busy = false
    @State private var errorMessage: String?
    var body: some View {
        List {
            if busy { ProgressView("Finding lots…") }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            ForEach(lots) { lot in
                Button { selected = lot; dismiss() } label: { Text(lot.name).frame(minHeight: 48) }
            }
            if !busy && errorMessage == nil && lots.isEmpty { Text("No matching lots or serial numbers.") }
        }
        .navigationTitle("Choose lot or serial")
        .searchable(text: $search)
        .task(id: search) {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let productId, let client = provider.client else { errorMessage = "Product information is unavailable. Refresh the order."; return }
            busy = true
            defer { busy = false }
            do {
                let result: [ManufacturingLot] = try await client.send(Endpoint(path: "/api/v1/manufacturing/products/\(productId)/lots", method: "GET", queryItems: [URLQueryItem(name: "search", value: search)]))
                guard !Task.isCancelled else { return }
                lots = result; errorMessage = nil
            } catch { if !Task.isCancelled { errorMessage = APIClient.failureMessage(error) } }
        }
    }
}

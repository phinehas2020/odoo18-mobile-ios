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
    @State private var showDiscardConfirmation = false
    @State private var initialDraft: DraftSnapshot?
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case produced, lot, component(UUID) }

    private struct DraftSnapshot: Equatable {
        struct Allocation: Equatable {
            let moveId: Int
            let quantity: String
            let lotId: Int?
        }
        let quantity: String
        let lotName: String
        let disposition: String
        let inspected: Bool
        let allocations: [Allocation]
    }

    private var currentDraft: DraftSnapshot {
        DraftSnapshot(quantity: quantity, lotName: lotName, disposition: disposition, inspected: inspected,
                      allocations: allocations.map { .init(moveId: $0.component.id, quantity: $0.quantity, lotId: $0.lot?.id) })
    }

    private var hasUnsavedChanges: Bool {
        !attempted && initialDraft.map { $0 != currentDraft } == true
    }

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
                    WorkplaceHeader(title: detail.productName ?? detail.name,
                                    subtitle: "Record the quantities actually produced and consumed.",
                                    symbol: "checkmark.seal")
                    Label(detail.name, systemImage: "doc.text").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                if let errorMessage {
                    WorkplaceNotice(title: "Review needs attention", message: errorMessage, symbol: "exclamationmark.triangle", tint: WorkplaceTheme.danger)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)).listRowBackground(Color.clear)
                }
                if let review {
                    if !review.blockers.isEmpty {
                        Section("Resolve Before Completing") {
                            ForEach(Array(review.blockers.enumerated()), id: \.offset) { _, text in
                                Label(text, systemImage: "exclamationmark.octagon.fill").font(.subheadline).foregroundStyle(WorkplaceTheme.danger).padding(.vertical, 4)
                            }
                        }
                    }
                    if !review.warnings.isEmpty {
                        Section("Review Carefully") {
                            ForEach(Array(review.warnings.enumerated()), id: \.offset) { _, text in
                                Label(text, systemImage: "exclamationmark.triangle").font(.subheadline).padding(.vertical, 4)
                            }
                        }
                    }
                    Section("Finished Product") {
                        WorkplaceMetric(title: "Remaining to produce", value: "\(review.quantityRemaining.formatted()) \(detail.uomName ?? "")", symbol: "shippingbox")
                            .padding(.vertical, 6)
                        if detail.productTracking == "serial" {
                            Label("Complete one finished serial number at a time. Enter a produced quantity of 1.", systemImage: "number").font(.subheadline).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Produced").font(.subheadline.weight(.medium))
                            TextField("Quantity produced", text: $quantity).keyboardType(.decimalPad)
                                .font(.title3.weight(.semibold)).monospacedDigit().focused($focusedField, equals: .produced)
                                .padding(.vertical, 4)
                                .accessibilityLabel("Quantity produced for \(detail.productName ?? detail.name)")
                                .accessibilityHint("Enter the amount actually produced in \(detail.uomName ?? "the product’s unit").")
                        }
                        Text("Suggested from the remaining quantity. Change it to match what you actually made.").font(.caption).foregroundStyle(.secondary)
                        if review.requiresFinishedLot {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Finished lot or serial").font(.subheadline.weight(.medium))
                                TextField("Finished lot or serial number", text: $lotName).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focusedField, equals: .lot)
                                    .accessibilityLabel("Finished lot or serial number for \(detail.productName ?? detail.name)")
                            }.padding(.vertical, 4)
                        }
                        if let produced = warehouseQuantity(quantity), produced < review.quantityRemaining {
                            Picker("Unfinished quantity", selection: $disposition) {
                                Text("Create a backorder").tag("backorder")
                                Text("Close without a backorder").tag("close")
                            }
                        }
                        if disposition == "close", (warehouseQuantity(quantity) ?? review.quantityRemaining) < review.quantityRemaining {
                            Label("Any remaining production quantity will not be backordered.", systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(WorkplaceTheme.attention)
                        }
                    }
                    Section("Actual Component Consumption") {
                        Text("Enter the total actually consumed for this production, not an additional amount. Recorded consumption is shown for comparison.").font(.subheadline).foregroundStyle(.secondary)
                        ForEach($allocations) { $allocation in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(allocation.component.productName).font(.headline).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                                Text("Planned: \(allocation.component.quantity.formatted()) \(allocation.component.uomName ?? "")").font(.subheadline).foregroundStyle(.secondary)
                                if let recorded = allocation.component.doneQuantity { Text("Recorded total: \(recorded.formatted())").font(.caption).foregroundStyle(.secondary) }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Actual consumption").font(.subheadline.weight(.medium))
                                    TextField("Quantity consumed", text: $allocation.quantity).keyboardType(.decimalPad).focused($focusedField, equals: .component(allocation.id))
                                        .font(.title3.weight(.semibold)).monospacedDigit().padding(.vertical, 4)
                                        .accessibilityLabel("Actual consumption of \(allocation.component.productName), allocation \(allocationNumber(allocation.id))")
                                        .accessibilityHint("Enter the final total consumed in \(allocation.component.uomName ?? "the component’s unit").")
                                }
                                if let tracking = allocation.component.tracking, tracking != "none" {
                                    NavigationLink {
                                        ManufacturingLotPicker(productId: allocation.component.productId, selected: $allocation.lot)
                                    } label: {
                                        Label(allocation.lot?.name ?? "Choose a lot or serial number", systemImage: "tag").font(.subheadline.weight(.medium))
                                    }
                                    .accessibilityLabel("Lot or serial for \(allocation.component.productName), allocation \(allocationNumber(allocation.id))")
                                    .accessibilityValue(allocation.lot?.name ?? "Not selected")
                                    if allocations.filter({ $0.component.id == allocation.component.id }).count > 1 {
                                        Button("Remove this allocation", role: .destructive) {
                                            allocations.removeAll { $0.id == allocation.id }
                                        }.buttonStyle(.bordered).frame(minHeight: 44)
                                            .accessibilityLabel("Remove allocation \(allocationNumber(allocation.id)) for \(allocation.component.productName)")
                                    }
                                    Button("Add another lot allocation") {
                                        allocations.append(ConsumptionDraft(component: allocation.component))
                                    }.buttonStyle(.bordered).frame(minHeight: 44)
                                        .accessibilityLabel("Add another lot allocation for \(allocation.component.productName)")
                                }
                            }.padding(.vertical, 10)
                        }
                    }
                    Section("Confirm Your Review") {
                        ForEach(validationIssues, id: \.self) { issue in
                            Label(issue, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Toggle("I checked quantities, lots and completed operations", isOn: $inspected).font(.subheadline).padding(.vertical, 4)
                        Button {
                            submit()
                        } label: {
                            Label("Complete Production", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent).tint(WorkplaceTheme.buttonFill)
                        .controlSize(.large)
                        .disabled(!review.canComplete || !inspected || payload == nil || busy || attempted)
                        .accessibilityLabel("Complete production order \(detail.name)")
                    }
                } else if !busy && errorMessage != nil {
                    Button("Reload review") { Task { await load() } }
                }
                if busy { ProgressView("Checking production…").frame(maxWidth: .infinity).padding(.vertical, 12) }
            }
            .workplaceScreen()
            .disabled(busy)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Review Production")
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
            .onChange(of: validationIssues.count) { _, count in
                print("[mobile-api] completion-form order=\(detail.id) missing_fields=\(count) reviewed=\(inspected) submitting=\(busy)")
            }
            .onChange(of: inspected) { _, reviewed in
                print("[mobile-api] completion-form order=\(detail.id) reviewed=\(reviewed) payload_valid=\(payload != nil)")
            }
            .interactiveDismissDisabled(busy || hasUnsavedChanges)
            .confirmationDialog("Discard Production Review?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("The quantities, lot selections, and review changes you entered will be lost.")
            }
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
                initialDraft = currentDraft
            }
        }
    }

    private func allocationNumber(_ id: UUID) -> Int {
        (allocations.firstIndex(where: { $0.id == id }) ?? 0) + 1
    }

    private func requestDismiss() {
        focusedField = nil
        if hasUnsavedChanges { showDiscardConfirmation = true }
        else { dismiss() }
    }

    private var validationIssues: [String] {
        guard let review else { return [] }
        var issues: [String] = []
        if let produced = warehouseQuantity(quantity), produced > 0 {
            if produced > review.quantityRemaining { issues.append("Produced quantity exceeds the remaining quantity.") }
            if detail.productTracking == "serial" && produced != 1 { issues.append("Enter 1 for a serial-tracked finished product.") }
        } else { issues.append("Enter the quantity produced.") }
        if review.requiresFinishedLot && lotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Enter the finished lot or serial number.") }
        for (index, allocation) in allocations.enumerated() {
            guard let used = warehouseQuantity(allocation.quantity) else {
                issues.append("Enter consumption for component \(index + 1): \(allocation.component.productName).")
                continue
            }
            if allocation.component.tracking == "serial" && used != 0 && used != 1 { issues.append("Component \(index + 1) must use 0 or 1 per serial number.") }
            if used > 0, let tracking = allocation.component.tracking, tracking != "none", allocation.lot == nil { issues.append("Choose a lot or serial for component \(index + 1).") }
        }
        return issues
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
        do {
            let response: ManufacturingCompletionReview = try await client.send(Endpoint(path: "/api/v1/manufacturing/orders/\(detail.id)/completion-review", method: "GET"))
            review = response
            if quantity.isEmpty, let suggested = response.suggestedQuantity, suggested > 0 {
                quantity = (detail.productTracking == "serial" ? min(1, suggested) : suggested).formatted(.number.grouping(.never))
            }
            print("[mobile-api] completion-form order=\(detail.id) can_complete=\(response.canComplete) blockers=\(response.blockers.count) missing_fields=\(validationIssues.count) payload_valid=\(payload != nil)")
        }
        catch { errorMessage = APIClient.failureMessage(error) }
    }
    private func submit() {
        guard let payload, !busy, !attempted else { return }
        focusedField = nil
        busy = true
        attempted = true
        print("[mobile-api] completion-form order=\(detail.id) submit components=\(payload.components.count)")
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
            if busy { ProgressView("Finding lots…").frame(maxWidth: .infinity).padding(.vertical, 12) }
            if let errorMessage {
                WorkplaceNotice(title: "Couldn’t load lots", message: errorMessage, symbol: "exclamationmark.triangle", tint: WorkplaceTheme.danger)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)).listRowBackground(Color.clear)
            }
            ForEach(lots) { lot in
                Button { selected = lot; dismiss() } label: {
                    HStack(spacing: 14) {
                        WorkplaceIcon(symbol: "tag")
                        Text(lot.name).font(.body.weight(.medium)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if selected?.id == lot.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(WorkplaceTheme.accent) }
                    }.frame(minHeight: 48).padding(.vertical, 4)
                }.accessibilityLabel(lot.name).accessibilityValue(selected?.id == lot.id ? "Selected" : "")
            }
            if !busy && errorMessage == nil && lots.isEmpty {
                ContentUnavailableView("No matching lots", systemImage: "tag", description: Text("Try another lot or serial number."))
            }
        }
        .workplaceScreen()
        .navigationTitle("Choose Lot or Serial")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Lot or serial number")
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

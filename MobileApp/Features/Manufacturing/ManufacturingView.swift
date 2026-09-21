import SwiftUI

struct ManufacturingView: View {
    var workOrdersFirst = false
    @EnvironmentObject private var apiProvider: APIClientProvider
    @StateObject private var model = ManufacturingViewModel()
    @State private var search = ""
    @State private var dueOnly = false
    @State private var stateFilter = "all"
    @State private var showCreate = false

    private var filtered: [ManufacturingOrder] {
        model.orders.filter { (stateFilter == "all" || $0.state == stateFilter) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || ($0.productName ?? "").localizedCaseInsensitiveContains(search)) }
    }

    var body: some View {
        List {
            Section {
                Text(workOrdersFirst ? "Choose a manufacturing order to see its operations and work centers." : "See what needs to be made, check components and open work orders.")
                    .foregroundStyle(.secondary)
                Toggle("Due today or overdue", isOn: $dueOnly).disabled(model.isLoading)
                Picker("Status", selection: $stateFilter) {
                    Text("All statuses").tag("all")
                    ForEach(Array(Set(model.orders.map(\.state))).sorted(), id: \.self) { state in
                        Text(warehouseStateLabel(state)).tag(state)
                    }
                }
                Text("\(filtered.count) of \(model.orders.count) loaded orders")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if model.isLoading { ProgressView("Loading orders…") }
            if let error = model.errorMessage {
                LoadFailureView(message: error) { Task { await reload() } }
            } else if !model.isLoading && filtered.isEmpty {
                ContentUnavailableView("No matching orders", systemImage: "gearshape.2", description: Text("Try another search or change the due-date filter."))
            }
            Section("Open manufacturing orders") {
                ForEach(filtered) { order in
                    NavigationLink {
                        ManufacturingDetailView(orderId: order.id, workOrdersFirst: workOrdersFirst)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(order.productName ?? order.name).font(.headline)
                            Text(order.name).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                            WorkStatusBadge(state: order.state)
                            if let quantity = order.quantity {
                                Text("\(quantity.formatted()) \(order.uomName ?? "")")
                            }
                            if let assignee = order.assignedUserName { Text(assignee).font(.subheadline).foregroundStyle(.secondary) }
                        }.padding(.vertical, 10)
                    }
                }
            }
            if model.orders.count == 200 {
                Text("Showing the first 200 open orders by scheduled date. Search covers these loaded orders.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(workOrdersFirst ? "Work orders" : "Manufacturing")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showCreate = true } label: { Label("New production", systemImage: "plus") } } }
        .sheet(isPresented: $showCreate, onDismiss: { Task { await reload() } }) {
            ManufacturingCreateSheet { }
        }
        .searchable(text: $search, prompt: "Order or product")
        .task(id: dueOnly) { await reload() }
        .refreshable { await reload() }
    }
    private func reload() async { await model.load(client: apiProvider.client, dueOnly: dueOnly) }
}

struct ManufacturingDetailView: View {
    let orderId: Int
    var workOrdersFirst = false
    @EnvironmentObject private var apiProvider: APIClientProvider
    @EnvironmentObject private var network: NetworkMonitor
    @StateObject private var model = ManufacturingDetailViewModel()
    @State private var finishing: ManufacturingWorkOrder?
    @State private var selectedQuality: ManufacturingQualityCheck?
    @State private var showCompletion = false

    var body: some View {
        List {
            if let message = model.errorMessage {
                LoadFailureView(message: message) { Task { await reload() } }
            }
            if !network.isOnline { Text("Reconnect to change a work order.").foregroundStyle(.secondary) }
            if model.isBusy { ProgressView("Updating…") }
            if let detail = model.detail {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(detail.productName ?? detail.name).font(.title2.bold())
                        Text(detail.name).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                        WorkStatusBadge(state: detail.state)
                        if let quantity = detail.quantity { Text("To make: \(quantity.formatted()) \(detail.uomName ?? "")") }
                    }.padding(.vertical, 6)
                }
                if detail.isPlanned == false && !["done", "cancel"].contains(detail.state) {
                    Section {
                        actionButton("Plan operations", symbol: "calendar.badge.clock") {
                            Task { await model.plan(client: apiProvider.client, id: detail.id) }
                        }.disabled(model.isBusy || model.requiresRefresh || !network.isOnline)
                    }
                }
                if workOrdersFirst {
                    operations(detail)
                    qualityChecks(detail)
                    components(detail)
                } else {
                    components(detail)
                    operations(detail)
                    qualityChecks(detail)
                }
                if !["done", "cancel"].contains(detail.state) {
                    Section("Finish production") {
                        Text("Complete the operations and quality checks, then review actual quantities.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        actionButton("Review and complete production", symbol: "checkmark.seal") { showCompletion = true }
                            .disabled(model.isBusy || model.requiresRefresh || !network.isOnline)
                    }
                }
            }
        }
        .navigationTitle("Manufacturing order")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(item: $selectedQuality) { check in
            QualityCheckSheet(check: check) { passed, notes, photo in
                guard network.isOnline else { return false }
                await model.recordQuality(client: apiProvider.client, check: check, passed: passed, notes: notes, photo: photo)
                return model.errorMessage == nil && !model.requiresRefresh
            }
        }
        .sheet(isPresented: $showCompletion) {
            if let detail = model.detail {
                ManufacturingCompletionSheet(detail: detail) { payload in
                    guard network.isOnline else { return false }
                    await model.complete(client: apiProvider.client, id: orderId, payload: payload)
                    return model.errorMessage == nil && !model.requiresRefresh
                }
            }
        }
        .confirmationDialog("Finish this work order?", isPresented: Binding(get: { finishing != nil }, set: { if !$0 { finishing = nil } }), titleVisibility: .visible) {
            if let work = finishing {
                Button("Finish \(work.name)") { perform(work, action: "finish"); finishing = nil }
            }
            Button("Cancel", role: .cancel) { finishing = nil }
        } message: {
            Text("Confirm the operation and required checks are complete. This updates Odoo.")
        }
    }

    @ViewBuilder
    private func qualityChecks(_ detail: ManufacturingDetail) -> some View {
        if let checks = detail.qualityChecks, !checks.isEmpty {
            Section("Quality checks") {
                ForEach(checks) { check in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(check.name).font(.headline)
                        Label(check.state.capitalized, systemImage: ["pass", "passed"].contains(check.state) ? "checkmark.circle" : "checkmark.shield")
                        if let notes = check.notes, !notes.isEmpty { Text(notes).foregroundStyle(.secondary) }
                        if let person = check.completedByName { Text("Recorded by \(person)").font(.subheadline) }
                        if !["pass", "passed", "done", "cancel"].contains(check.state) {
                            actionButton("Inspect and record result", symbol: "checkmark.shield") { selectedQuality = check }
                                .disabled(model.isBusy || model.requiresRefresh || !network.isOnline)
                        }
                    }.padding(.vertical, 6)
                }
            }
        }
    }

    private func components(_ detail: ManufacturingDetail) -> some View {
        Section("Components") {
            if detail.components.isEmpty { Text("No components listed").foregroundStyle(.secondary) }
            ForEach(detail.components) { component in
                VStack(alignment: .leading, spacing: 6) {
                    Text(component.productName).font(.headline)
                    Text("Required: \(component.quantity.formatted()) \(component.uomName ?? "")")
                    if let done = component.doneQuantity { Text("Used: \(done.formatted())").foregroundStyle(.secondary) }
                }.padding(.vertical, 6)
            }
        }
    }

    private func operations(_ detail: ManufacturingDetail) -> some View {
        Section("Work orders") {
            if detail.workorders.isEmpty { Text("No work orders listed. Routing and operations are configured in Odoo.").foregroundStyle(.secondary) }
            ForEach(detail.workorders) { work in
                VStack(alignment: .leading, spacing: 12) {
                    Text(work.name).font(.title3.bold())
                    WorkStatusBadge(state: work.state)
                    WorkDetailRow(title: "Work center", value: work.workcenterName ?? "Not set")
                    WorkDetailRow(title: "Product", value: work.productName ?? "Not set")
                    WorkDetailRow(title: "Employee", value: work.employeeName ?? "Not assigned")
                    WorkDetailRow(title: "Quantity remaining", value: work.quantityRemaining.map { $0.formatted() } ?? "Not available")
                    WorkDetailRow(title: "Expected time (h:mm)", value: workDurationLabel(work.expectedDurationMinutes))
                    WorkDetailRow(title: "Actual time (h:mm)", value: workDurationLabel(work.realDurationMinutes))
                    if work.state == "waiting" || work.state == "pending" {
                        Label(work.state == "waiting" ? "Waiting for materials before this step is ready." : "An earlier operation must finish first.", systemImage: "info.circle")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if work.canStart { actionButton("Start work", symbol: "play.fill") { perform(work, action: "start") } }
                    if work.canPause { actionButton("Pause work", symbol: "pause.fill", secondary: true) { perform(work, action: "stop") } }
                    if work.canFinish { actionButton("Finish work order", symbol: "checkmark.circle", secondary: work.canStart) { finishing = work } }
                }
                .padding(.vertical, 10)
                .disabled(model.isBusy || model.requiresRefresh || !network.isOnline || ["done", "cancel"].contains(detail.state))
            }
        }
    }
    @ViewBuilder
    private func actionButton(_ title: String, symbol: String, secondary: Bool = false, action: @escaping () -> Void) -> some View {
        if secondary {
            Button(action: action) { Label(title, systemImage: symbol).font(.headline).frame(maxWidth: .infinity, minHeight: 52) }
                .buttonStyle(.bordered)
        } else {
            Button(action: action) { Label(title, systemImage: symbol).font(.headline).frame(maxWidth: .infinity, minHeight: 52) }
                .buttonStyle(.borderedProminent)
        }
    }
    private func perform(_ work: ManufacturingWorkOrder, action: String) {
        guard network.isOnline else { return }
        Task { await model.perform(client: apiProvider.client, workOrderId: work.id, action: action) }
    }
    private func reload() async { await model.load(client: apiProvider.client, id: orderId) }
}

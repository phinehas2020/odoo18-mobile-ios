import SwiftUI

struct ManufacturingView: View {
    var workOrdersFirst = false
    @EnvironmentObject private var apiProvider: APIClientProvider
    @StateObject private var model = ManufacturingViewModel()
    @State private var search = ""
    @State private var dueOnly = false
    @State private var stateFilter = "all"
    @State private var showCreate = false
    @Environment(\.dynamicTypeSize) private var textSize

    private var filtered: [ManufacturingOrder] {
        model.orders.filter { (stateFilter == "all" || $0.state == stateFilter) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || ($0.productName ?? "").localizedCaseInsensitiveContains(search)) }
    }

    var body: some View {
        List {
            if model.isLoading { ProgressView("Loading orders…").frame(maxWidth: .infinity).padding(.vertical, 12) }
            if let error = model.errorMessage {
                LoadFailureView(message: error) { Task { await reload() } }
            } else if !model.isLoading && filtered.isEmpty {
                ContentUnavailableView("No matching orders", systemImage: "gearshape.2", description: Text("Try another search or change your filters. Open an order to see its operations, materials, and quality checks."))
            }
            Section {
                Text("\(model.orders.count) open orders · \(model.orders.filter { $0.state == "progress" }.count) in progress")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Status", selection: $stateFilter) {
                    Text("All").tag("all")
                    ForEach(Array(Set(model.orders.map(\.state))).sorted(), id: \.self) { state in
                        Text(warehouseStateLabel(state)).tag(state)
                    }
                }

            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 0))
            Section {
                ForEach(filtered) { order in
                    NavigationLink {
                        ManufacturingDetailView(orderId: order.id, workOrdersFirst: workOrdersFirst)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(order.productName ?? order.name).font(.body.weight(.semibold))
                                .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                            let layout = textSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
                            layout {
                                Text(order.name).font(.caption.monospaced()).foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                quantityLabel(order)
                            }
                            layout {
                                WorkStatusBadge(state: order.state)
                                Spacer(minLength: 0)
                                if let assignee = order.assignedUserName {
                                    Text(assignee).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(.vertical, 8)
                    }
                    .listRowBackground(WorkplaceTheme.surface)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    .accessibilityHint("Open operations, materials, and quality checks for \(order.name)")
                }
            } header: {
                if dueOnly { Text("Due today & overdue").font(.caption).textCase(nil) }
            }
            if model.orders.count == 200 {
                Text("Showing the first 200 open orders by scheduled date. Search covers these loaded orders.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(12)
        .workplaceScreen()
        .navigationTitle(workOrdersFirst ? "Work" : "Manufacturing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Due today or overdue", isOn: $dueOnly).disabled(model.isLoading)
                    Picker("Status", selection: $stateFilter) {
                        Text("All statuses").tag("all")
                        ForEach(Array(Set(model.orders.map(\.state))).sorted(), id: \.self) { Text(warehouseStateLabel($0)).tag($0) }
                    }
                    Button("Clear filters") { dueOnly = false; stateFilter = "all" }
                } label: { Label("Filter orders", systemImage: "line.3.horizontal.decrease") }
                .accessibilityValue(dueOnly || stateFilter != "all" ? "Filters applied" : "All orders")
            }
            ToolbarItem(placement: .topBarTrailing) { Button { showCreate = true } label: { Label("New production", systemImage: "plus") } }
        }
        .sheet(isPresented: $showCreate, onDismiss: { Task { await reload() } }) {
            ManufacturingCreateSheet { }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Order or product")
        .task(id: dueOnly) { await reload() }
        .refreshable { await reload() }
    }
    @ViewBuilder private func quantityLabel(_ order: ManufacturingOrder) -> some View {
        if let quantity = order.quantity {
            Text("\(quantity.formatted()) \(order.uomName ?? "")")
                .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
                .accessibilityLabel("Quantity to produce: \(quantity.formatted()) \(order.uomName ?? "")")
        }
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
    @State private var showMaterials = false
    @State private var expandedWork: Set<Int> = []
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        List {
            if let message = model.errorMessage {
                LoadFailureView(message: message) { Task { await reload() } }
            }
            if !network.isOnline {
                WorkplaceNotice(title: "You’re offline", message: "Reconnect to change a work order.", symbol: "wifi.slash")
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)).listRowBackground(Color.clear)
            }
            if model.isBusy { ProgressView("Updating…").frame(maxWidth: .infinity).padding(.vertical, 12) }
            if let detail = model.detail {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PRODUCTION ORDER").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(WorkplaceTheme.accent)
                        Text(detail.productName ?? detail.name).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                        if textSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 8) { WorkStatusBadge(state: detail.state); productionQuantity(detail) }
                        } else {
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    WorkStatusBadge(state: detail.state).fixedSize()
                                    Spacer(minLength: 10)
                                    productionQuantity(detail).fixedSize()
                                }
                                VStack(alignment: .leading, spacing: 8) { WorkStatusBadge(state: detail.state); productionQuantity(detail) }
                            }
                        }
                    }.padding(.vertical, 10)
                }
                if detail.state == "draft" || (!detail.workorders.isEmpty && detail.isPlanned == false) {
                    Section {
                        WorkplaceHeader(title: "Ready to plan", subtitle: "Plan the operations to begin this order.", symbol: "calendar.badge.clock")
                        Button { Task { await model.plan(client: apiProvider.client, id: detail.id) } } label: {
                            Label("Plan operations", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity)
                        }.workplaceProminentControl().disabled(!canAct(detail))
                            .accessibilityLabel("Plan operations for \(detail.name)")
                    }
                }
                operations(detail)
                qualityChecks(detail)
                Section {
                    DisclosureGroup("Materials · \(detail.components.count)", isExpanded: $showMaterials) {
                        ForEach(detail.components) { component in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(component.productName).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                                Text("Required \(component.quantity.formatted()) \(component.uomName ?? "")").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                if let done = component.doneQuantity { Text("Used \(done.formatted()) \(component.uomName ?? "")").font(.subheadline).foregroundStyle(.secondary) }
                            }.padding(.vertical, 8).accessibilityElement(children: .combine)
                        }
                    }.tint(WorkplaceTheme.accent)
                }
                if !["done", "cancel"].contains(detail.state) {
                    Section {
                        Button { showCompletion = true } label: {
                            WorkplaceActionLabel(title: "Review production", subtitle: "Confirm actual quantities and lots", symbol: "checkmark.seal", emphasized: true)
                        }.disabled(!canAct(detail)).accessibilityLabel("Review quantities and lots for \(detail.name)")
                    } footer: {
                        Text("Review actual quantities and lots before completing this order.")
                    }
                }
            }
        }
        .workplaceScreen()
        .listStyle(.plain)
        .navigationTitle(model.detail?.name ?? "Production")
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
    private func productionQuantity(_ detail: ManufacturingDetail) -> some View {
        if let quantity = detail.quantity {
            Text("\(quantity.formatted()) \(detail.uomName ?? "")")
                .font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Quantity to produce: \(quantity.formatted()) \(detail.uomName ?? "")")
        }
    }

    private func nextWork(_ detail: ManufacturingDetail) -> ManufacturingWorkOrder? {
        detail.workorders.first(where: { $0.isUserWorking && $0.canFinish }) ?? detail.workorders.first(where: { $0.canStart || $0.canFinish })
    }

    @ViewBuilder
    private func qualityChecks(_ detail: ManufacturingDetail) -> some View {
        let checks = detail.qualityChecks ?? []
        Section("Quality · \(checks.filter { ["pass", "passed"].contains($0.state) }.count) of \(checks.count) passed") {
            if checks.isEmpty { Label("No quality checks for this order", systemImage: "checkmark.shield").foregroundStyle(.secondary) }
            ForEach(checks) { check in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {

                        VStack(alignment: .leading, spacing: 8) {
                            Text(check.name).font(.headline).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                            WorkplaceStatusPill(text: qualityTitle(check), symbol: qualitySymbol(check), tint: qualityTint(check))
                        }
                    }
                    if let notes = check.notes, !notes.isEmpty { Text(notes).font(.subheadline).foregroundStyle(.secondary) }
                    if let person = check.completedByName { Text("Recorded by \(person)").font(.caption).foregroundStyle(.secondary) }
                    if !["pass", "passed", "done", "cancel"].contains(check.state) {
                        Button { selectedQuality = check } label: {
                            Label("Inspect check", systemImage: "checklist").frame(maxWidth: .infinity)
                        }.workplaceSecondaryControl()
                            .accessibilityLabel("Inspect \(check.name)")
                            .disabled(model.isBusy || model.requiresRefresh || !network.isOnline)
                    }
                }.padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func operations(_ detail: ManufacturingDetail) -> some View {
        let current = nextWork(detail)
        if let work = current {
            Section(work.isUserWorking ? "Current operation" : "Next operation") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {

                        VStack(alignment: .leading, spacing: 8) {
                            Text(work.name).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                            WorkStatusBadge(state: work.state)
                        }
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "building.2")
                        Text(work.workcenterName ?? "Work center not set")
                    }.font(.subheadline).foregroundStyle(.secondary)
                    if let employee = work.employeeName {
                        Label(employee, systemImage: "person").font(.subheadline).foregroundStyle(.secondary)
                    }
                    workMetrics(work)
                    let buttons = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
                    buttons {
                        if work.canPause {
                            Button { perform(work, action: "stop") } label: { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity) }
                                .workplaceSecondaryControl().frame(maxWidth: .infinity)
                                .accessibilityLabel("Pause \(work.name)")
                        }
                        if work.canFinish && work.isUserWorking {
                            Button { finishing = work } label: { Label("Finish step", systemImage: "checkmark").frame(maxWidth: .infinity) }
                                .workplaceProminentControl().frame(maxWidth: .infinity)
                                .accessibilityLabel("Finish \(work.name)")
                        } else if work.canStart {
                            Button { perform(work, action: "start") } label: { Label("Start step", systemImage: "play.fill").frame(maxWidth: .infinity) }
                                .workplaceProminentControl().frame(maxWidth: .infinity)
                                .accessibilityLabel("Start \(work.name)")
                        } else if work.canFinish {
                            Button { finishing = work } label: { Label("Finish step", systemImage: "checkmark").frame(maxWidth: .infinity) }
                                .workplaceProminentControl().frame(maxWidth: .infinity)
                                .accessibilityLabel("Finish \(work.name)")
                        }
                    }.disabled(!canAct(detail))
                    if let product = work.productName, product != detail.productName {
                        Text(product).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
            }
        }
        let others = detail.workorders.filter { $0.id != current?.id }
        if !others.isEmpty {
            Section("Other steps") {
                ForEach(others) { work in
                    DisclosureGroup {
                        WorkDetailRow(title: "Product", value: work.productName ?? "Not set")
                        WorkDetailRow(title: "Employee", value: work.employeeName ?? "Not assigned")
                        WorkDetailRow(title: "Remaining", value: work.quantityRemaining.map { $0.formatted() } ?? "Not available")
                        WorkDetailRow(title: "Expected time", value: workDurationLabel(work.expectedDurationMinutes))
                        WorkDetailRow(title: "Actual time", value: workDurationLabel(work.realDurationMinutes))
                        if work.canStart { Button("Start step") { perform(work, action: "start") }.buttonStyle(.borderless).frame(minHeight: 44).disabled(!canAct(detail)).accessibilityLabel("Start \(work.name)") }
                        if work.canFinish { Button("Finish step") { finishing = work }.buttonStyle(.borderless).frame(minHeight: 44).disabled(!canAct(detail)).accessibilityLabel("Finish \(work.name)") }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(work.name).font(.headline)
                            if let workcenter = work.workcenterName { Text(workcenter).font(.caption).foregroundStyle(.secondary) }
                            WorkStatusBadge(state: work.state)
                        }.padding(.vertical, 8)
                    }.tint(WorkplaceTheme.accent)
                }
            }
        }
        if detail.workorders.isEmpty {
            Section { Label("No work steps on this order", systemImage: "checklist").foregroundStyle(.secondary) }
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        WorkplaceMetric(title: title, value: value)
    }

    @ViewBuilder private func workMetrics(_ work: ManufacturingWorkOrder) -> some View {
        if textSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) { metricContent(work) }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) { metricContent(work) }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 12) { metricContent(work) }
            }
        }
    }

    @ViewBuilder private func metricContent(_ work: ManufacturingWorkOrder) -> some View {
        metric("Remaining", value: work.quantityRemaining.map { $0.formatted() } ?? "—")
            .accessibilityLabel("Remaining quantity for \(work.name): \(work.quantityRemaining.map { $0.formatted() } ?? "Not available")")
        metric("Elapsed · h:mm", value: workDurationLabel(work.realDurationMinutes))
            .accessibilityLabel("Elapsed time for \(work.name): \(workDurationLabel(work.realDurationMinutes))")
        metric("Expected · h:mm", value: workDurationLabel(work.expectedDurationMinutes))
            .accessibilityLabel("Expected time for \(work.name): \(workDurationLabel(work.expectedDurationMinutes))")
    }

    private func qualityTitle(_ check: ManufacturingQualityCheck) -> String {
        switch check.state {
        case "pass", "passed": return "Passed"
        case "done": return "Completed"
        case "fail", "failed": return "Failed"
        case "none", "pending": return "To inspect"
        case "cancel": return "Cancelled"
        default: return check.state.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    private func qualityTint(_ check: ManufacturingQualityCheck) -> Color {
        switch check.state {
        case "pass", "passed", "done": return WorkplaceTheme.success
        case "fail", "failed": return WorkplaceTheme.danger
        case "cancel": return .secondary
        default: return WorkplaceTheme.attention
        }
    }
    private func qualitySymbol(_ check: ManufacturingQualityCheck) -> String {
        switch check.state {
        case "pass", "passed", "done": return "checkmark.circle.fill"
        case "fail", "failed": return "exclamationmark.octagon.fill"
        default: return "checkmark.shield"
        }
    }

    private func canAct(_ detail: ManufacturingDetail) -> Bool {
        !model.isBusy && !model.requiresRefresh && network.isOnline && !["done", "cancel"].contains(detail.state)
    }
    private func perform(_ work: ManufacturingWorkOrder, action: String) {
        guard network.isOnline else { return }
        Task { await model.perform(client: apiProvider.client, workOrderId: work.id, action: action) }
    }
    private func reload() async { await model.load(client: apiProvider.client, id: orderId) }
}

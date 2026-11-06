import SwiftUI

struct AdminWorkSnapshot: Decodable {
    let generatedAt: Date
    let totalOrders: Int
    let truncated: Bool
    let orders: [AdminProductionRow]
    enum CodingKeys: String, CodingKey { case generatedAt = "generated_at", totalOrders = "total_orders", truncated, orders }
}

struct AdminProductionRow: Decodable, Identifiable {
    let id: Int
    let name, product, uom, status: String
    let quantity: Double
    let responsible: String?
    let overdue: Bool
    let completedSteps, totalSteps: Int
    let operations: [AdminWorkOperation]
    enum CodingKeys: String, CodingKey {
        case id, name, product, uom, status, quantity, responsible, overdue, operations
        case completedSteps = "completed_steps", totalSteps = "total_steps"
    }
}

struct AdminWorkOperation: Decodable, Identifiable {
    let id: Int
    let name, status, state, workcenter: String
    let expectedMinutes, recordedMinutes: Double
    let operators: [AdminOperatorSession]
    enum CodingKeys: String, CodingKey {
        case id, name, status, state, workcenter, operators
        case expectedMinutes = "expected_minutes", recordedMinutes = "recorded_minutes"
    }
}

struct AdminOperatorSession: Decodable, Identifiable {
    let id, name: String
    let recordedMinutes, runningMinutes: Double
    let runningSince: Date?
    enum CodingKeys: String, CodingKey {
        case id, name
        case recordedMinutes = "recorded_minutes", runningMinutes = "running_minutes", runningSince = "running_since"
    }
    func elapsedMinutes(since receivedAt: Date, now: Date, fresh: Bool) -> Double {
        max(0, runningMinutes) + (runningSince != nil && fresh ? max(0, now.timeIntervalSince(receivedAt)) / 60 : 0)
    }
}

@MainActor
final class AdminWorkOverviewModel: ObservableObject {
    @Published private(set) var snapshot: AdminWorkSnapshot?
    @Published private(set) var receivedAt: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    func load(client: APIClient?, isAdmin: Bool) async {
        guard isAdmin else { snapshot = nil; receivedAt = nil; error = nil; return }
        guard !isLoading else { return }
        guard let client else { error = "Connecting to your server…"; return }
        isLoading = true
        defer { isLoading = false }
        do {
            let value: AdminWorkSnapshot = try await client.send(Endpoint(path: "/api/v1/manufacturing/overview", method: "GET"))
            try Task.checkCancellation()
            snapshot = value; receivedAt = Date(); error = nil
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled else { return }
            if case APIError.rejected(403, _) = error { snapshot = nil; receivedAt = nil }
            if case APIError.httpStatus(403) = error { snapshot = nil; receivedAt = nil }
            self.error = "Couldn’t update the overview. " + APIClient.failureMessage(error)
        }
    }
}

struct AdminWorkOverview: View {
    @EnvironmentObject private var apiProvider: APIClientProvider
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var network: NetworkMonitor
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AdminWorkOverviewModel()
    @State private var filter = "all"
    @State private var search = ""
    private var isAdmin: Bool { authStore.user?.isAdmin == true }
    private struct RefreshKey: Hashable {
        let client: ObjectIdentifier?
        let admin, online, active: Bool
    }

    var body: some View {
        Group {
            if !isAdmin { ContentUnavailableView("Admin access required", systemImage: "lock") }
            else {
                TimelineView(.periodic(from: .now, by: 5)) { tick in
                    overview(now: tick.date)
                }
            }
        }
        .navigationTitle("Production")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Employee, order or product")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { ManufacturingView() } label: { Label("All production", systemImage: "list.bullet.rectangle") }
            }
        }
        .task(id: RefreshKey(client: apiProvider.client.map(ObjectIdentifier.init), admin: isAdmin, online: network.isOnline, active: scenePhase == .active)) {
            guard isAdmin else { await model.load(client: nil, isAdmin: false); return }
            guard network.isOnline, scenePhase == .active else { return }
            while !Task.isCancelled {
                await reload()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }

    private func overview(now: Date) -> some View {
        let fresh = network.isOnline && scenePhase == .active && model.error == nil && model.receivedAt.map { now.timeIntervalSince($0) < 60 } == true
        let orders = model.snapshot?.orders ?? []
        let visible = orders.filter { row in
            (filter == "all" || row.status == filter || filter == "attention" && (row.overdue || ["blocked", "paused", "to_close"].contains(row.status))) &&
            (search.isEmpty || ([row.name, row.product, row.responsible ?? ""] + row.operations.flatMap { $0.operators.map(\.name) }).contains { $0.localizedCaseInsensitiveContains(search) })
        }
        return List {
            Section {
                if model.snapshot != nil {
                    Text("\(orders.count) open orders · \(orders.filter { $0.status == "running" }.count) running")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Picker("Show", selection: $filter) {
                    Text("All work").tag("all")
                    Text("Running").tag("running")
                    Text("Needs attention").tag("attention")
                    Text("Ready").tag("ready")
                    Text("Waiting").tag("waiting")
                }

            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            if let message = model.error { Section { LoadFailureView(message: message) { Task { await reload() } } } }
            if !network.isOnline { Section { Label("Offline — showing the last update", systemImage: "wifi.slash").font(.subheadline).foregroundStyle(.secondary) } }
            if let date = model.receivedAt, !fresh {
                Text("Last update \(date.formatted(date: .omitted, time: .shortened)) · may be out of date")
                    .font(.caption).foregroundStyle(WorkplaceTheme.attention)
            }
            if model.snapshot == nil, model.error == nil, network.isOnline {
                ProgressView("Loading production…").frame(maxWidth: .infinity, minHeight: 100)
            } else if model.snapshot != nil, visible.isEmpty {
                ContentUnavailableView(orders.isEmpty ? "No open production" : "No matching work", systemImage: "checklist", description: Text(orders.isEmpty ? "Open manufacturing orders will appear here." : "Try another filter or employee name."))
            }
            Section {
                ForEach(visible) { order in
                    AdminProductionRowView(order: order, now: now, receivedAt: model.receivedAt ?? now, fresh: fresh)
                        .listRowBackground(WorkplaceTheme.surface)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                }
            }
            if model.snapshot?.truncated == true {
                Text("Showing \(orders.count) of \(model.snapshot?.totalOrders ?? 0) open orders, with in-progress production first. Counts and search cover these loaded orders.").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                DisclosureGroup("About this overview") {
                    Text("Updates every 30 seconds. Progress counts completed operations, not elapsed time. Timers show recorded work sessions; an open timer is not proof that someone is physically working.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                }.font(.caption).foregroundStyle(.secondary)
            }.listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .listSectionSpacing(12)
        .workplaceScreen()
        .refreshable { await reload() }
    }
    private func reload() async { await model.load(client: apiProvider.client, isAdmin: isAdmin) }
}

private struct AdminProductionRowView: View {
    let order: AdminProductionRow
    let now, receivedAt: Date
    let fresh: Bool
    @Environment(\.dynamicTypeSize) private var textSize
    private var activeOperation: AdminWorkOperation? {
        order.operations.first { $0.status == "running" } ?? order.operations.first { $0.status != "done" }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink { ManufacturingDetailView(orderId: order.id, workOrdersFirst: true) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(order.product).font(.body.weight(.semibold)).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    let layout = textSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
                    layout {
                        Text(order.name).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text("\(order.quantity.formatted()) \(order.uom)").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    }
                }
            }
            AdminWorkStatus(status: order.status)
            if order.overdue { Label("Past scheduled deadline", systemImage: "calendar.badge.exclamationmark").font(.caption).foregroundStyle(WorkplaceTheme.attention) }
            if let work = activeOperation {
                VStack(alignment: .leading, spacing: 5) {
                    Text(work.name).font(.subheadline)
                    if work.operators.isEmpty {
                        Text(work.workcenter.isEmpty ? "No employee timer recorded" : work.workcenter)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(work.operators) { person in
                        if person.runningSince != nil {
                            Text("\(person.name) · \(fresh ? "running" : "last reported running") \(adminWorkDuration(person.elapsedMinutes(since: receivedAt, now: now, fresh: fresh)))")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        } else { Text(person.name).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if order.totalSteps > 0 {
                Text("\(order.completedSteps) of \(order.totalSteps) operations complete").font(.caption).foregroundStyle(.secondary)
            } else { Text("No operations configured").font(.caption).foregroundStyle(.secondary) }
            DisclosureGroup("Operation details") {
                VStack(alignment: .leading, spacing: 16) {
                    if let owner = order.responsible {
                        Text("Responsible: \(owner)").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(order.operations) { work in
                        VStack(alignment: .leading, spacing: 7) {
                            Divider()
                            Text(work.name).font(.subheadline.weight(.semibold))
                            AdminWorkStatus(status: work.status)
                            if !work.workcenter.isEmpty { Text(work.workcenter).font(.caption).foregroundStyle(.secondary) }
                            ForEach(work.operators) { person in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(person.name).font(.subheadline.weight(.medium))
                                    if person.runningSince != nil {
                                        Text("\(fresh ? "Running for" : "Last reported running") \(adminWorkDuration(person.elapsedMinutes(since: receivedAt, now: now, fresh: fresh)))")
                                            .font(.caption).monospacedDigit().foregroundStyle(WorkplaceTheme.accent)
                                    }
                                    Text("\(adminWorkDuration(person.recordedMinutes)) recorded on this operation").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if work.operators.isEmpty && work.status != "done" { Text("No employee timer recorded").font(.caption).foregroundStyle(.secondary) }
                            if work.expectedMinutes > 0 {
                                Text("Planned: \(adminWorkDuration(work.expectedMinutes)) · Recorded: \(adminWorkDuration(work.recordedMinutes))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.padding(.top, 10)
            }.font(.caption.weight(.medium)).tint(WorkplaceTheme.accent)
        }.padding(.vertical, 10)
    }
}

private struct AdminWorkStatus: View {
    let status: String
    private var appearance: (String, String, Color) {
        switch status {
        case "running": return ("Running", "play.circle.fill", WorkplaceTheme.accent)
        case "blocked": return ("Blocked", "exclamationmark.octagon.fill", WorkplaceTheme.danger)
        case "paused": return ("Paused", "pause.circle.fill", WorkplaceTheme.attention)
        case "ready": return ("Ready", "circle.dotted", WorkplaceTheme.accent)
        case "done": return ("Complete", "checkmark.circle.fill", WorkplaceTheme.accent)
        case "to_close": return ("To close", "checkmark.circle", WorkplaceTheme.attention)
        default: return ("Waiting", "clock", .secondary)
        }
    }
    var body: some View {
        Label(appearance.0, systemImage: appearance.1).font(.caption.weight(.semibold)).foregroundStyle(appearance.2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

func adminWorkDuration(_ minutes: Double) -> String {
    guard minutes.isFinite, minutes >= 0 else { return "Unavailable" }
    let total = Int(min(minutes, 5256000))
    if total < 1 { return "less than 1m" }
    return total < 60 ? "\(total)m" : "\(total / 60)h \(total % 60)m"
}

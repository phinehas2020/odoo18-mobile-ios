import SwiftUI

/// The landing page is an overview; actions remain in their existing workspaces.
struct HomePulseView: View {
    @ObservedObject var menu: MenuViewModel
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var api: APIClientProvider
    @EnvironmentObject private var network: NetworkMonitor
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var model = HomePulseModel()
    let open: (String) -> Void

    private var hasManufacturing: Bool { menu.items.contains { $0.key == "manufacturing" } }
    private var hasFulfillment: Bool { menu.items.contains { ["packing", "shopify_fulfillment", "shopify"].contains($0.key) } }
    private var hasTodo: Bool { menu.items.contains(where: HomeView.isTodo) }
    private var hasPacking: Bool { menu.items.contains { $0.key == "packing" && $0.native } }
    private var isAdmin: Bool { auth.user?.isAdmin == true }
    private struct RefreshKey: Hashable {
        let client: ObjectIdentifier?
        let online, active, fulfillment, manufacturing, todo, admin: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                overviewHeader
                if let error = menu.errorMessage { LoadFailureView(message: error) { Task { await refresh() } } }
                if menu.isLoading && menu.items.isEmpty { ProgressView("Getting your day ready…").frame(maxWidth: .infinity, minHeight: 120) }
                activity
                attention
                if hasManufacturing { productionSection }
                if hasTodo { todoSection }
                quickActions
                if !menu.isLoading && menu.items.isEmpty && menu.errorMessage == nil {
                    ContentUnavailableView("Your workspace is getting ready", systemImage: "square.grid.2x2", description: Text("Open More to find your available apps, or pull down to refresh."))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Homestead Gristmill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { open("settings") } label: { Image(systemName: "person.crop.circle").font(.title3) }
                    .accessibilityLabel("Account and settings")
            }
        }
        .refreshable { await refresh() }
        .task(id: RefreshKey(client: api.client.map(ObjectIdentifier.init), online: network.isOnline, active: scenePhase == .active, fulfillment: hasFulfillment, manufacturing: hasManufacturing, todo: hasTodo, admin: isAdmin)) {
            guard network.isOnline, scenePhase == .active, let client = api.client else { return }
            while !Task.isCancelled {
                await model.refresh(client: client, fulfillment: hasFulfillment, manufacturing: hasManufacturing, todo: hasTodo, admin: isAdmin)
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
    }

    private var overviewHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Overview").font(.title2.weight(.bold))
                Spacer()
                Text(Date.now.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if !network.isOnline {
                Label("Offline · showing your last update", systemImage: "wifi.slash")
                    .font(.caption).foregroundStyle(WorkplaceTheme.attention)
            }
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 10) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                if hasFulfillment {
                    activityTile("Unfulfilled orders", value: model.fulfillment.value.map { $0.total.formatted() },
                                 symbol: "shippingbox", loading: model.fulfillment.isLoading, destination: "unfulfilled")
                        .accessibilityIdentifier("home.unfulfilled")
                }
                if hasManufacturing {
                    activityTile(isAdmin ? "Production orders" : "Your production", value: model.production.value.map { "\($0.total)\(!isAdmin && $0.limited ? "+" : "")" },
                                 symbol: "checklist", loading: model.production.isLoading, destination: "work")
                }
            }
            if hasFulfillment {
                HStack(spacing: 4) {
                    Text("Shopify queue")
                    if let date = model.fulfillment.updatedAt {
                        Text("· \(date.formatted(date: .omitted, time: .shortened))")
                    }
                    if model.fulfillment.error != nil && model.fulfillment.value != nil { Text("· last known counts") }
                }.font(.caption2).foregroundStyle(.secondary)
                if let error = model.fulfillment.error { LoadFailureView(message: error) { Task { await refresh() } } }
            }
        }
    }

    private func activityTile(_ title: String, value: String?, symbol: String, loading: Bool, destination: String) -> some View {
        Button { open(destination) } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline) {
                    Text(value ?? "—").font(.title.weight(.semibold)).monospacedDigit()
                    Spacer(minLength: 8)
                    if loading && value == nil { ProgressView() }
                    else { Image(systemName: symbol).font(.body).foregroundStyle(.secondary) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var attention: some View {
        let review = model.fulfillment.value?.needsReview ?? 0
        let production = model.production.value?.attention ?? 0
        if review > 0 || production > 0 {
            VStack(alignment: .leading, spacing: 0) {
                Text("Needs attention").font(.subheadline.weight(.semibold)).padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
                if review > 0 {
                    attentionRow("\(review) \(review == 1 ? "order needs" : "orders need") review", destination: "unfulfilled")
                }
                if production > 0 {
                    attentionRow("\(production) production \(production == 1 ? "order needs" : "orders need") attention", destination: "work")
                }
            }
        }
    }

    private func attentionRow(_ text: String, destination: String) -> some View {
        Button { open(destination) } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(WorkplaceTheme.attention)
                Text(text).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                chevron
            }.font(.subheadline).frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var productionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeading(isAdmin ? "Production" : "Your production", action: "View all", destination: "work")
            if let pulse = model.production.value {
                Text("\(pulse.running)\(pulse.limited ? "+" : "") in progress")
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
                if pulse.rows.isEmpty {
                    Text("No open production orders").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
                }
                ForEach(pulse.rows.prefix(2)) { row in
                    NavigationLink { ManufacturingDetailView(orderId: row.id, workOrdersFirst: true) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(row.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                Text([row.reference, row.detail].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                                if typeSize.isAccessibilitySize { productionStatus(row) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if !typeSize.isAccessibilitySize { productionStatus(row).padding(.top, 2) }
                            chevron.padding(.top, 4)
                        }.padding(.vertical, 14).frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Divider()
                }
                if pulse.limited { Text("Activity covers the first 200 orders.").font(.caption).foregroundStyle(.secondary).padding(.top, 8) }
            } else if model.production.isLoading { ProgressView("Loading production…").padding(.vertical, 12) }
            if let error = model.production.error { LoadFailureView(message: error) { Task { await refresh() } } }
            freshness(model.production.updatedAt, failed: model.production.error != nil)
        }
    }

    private func productionStatus(_ row: ProductionPulseRow) -> some View {
        Text(row.overdue ? "Overdue" : row.statusLabel)
            .font(.caption)
            .foregroundStyle(row.overdue || ["blocked", "paused", "to_close"].contains(row.status) ? WorkplaceTheme.attention : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var todoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeading("Your to-dos", action: model.todos.value.map { "View all (\($0.items.count)\($0.truncated ? "+" : ""))" } ?? "View all", destination: "todo")
            if let tasks = model.todos.value {
                if tasks.items.isEmpty {
                    Text("Nothing on your list").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
                }
                ForEach(tasks.items.prefix(3)) { task in
                    NavigationLink { TodoDetailView(taskId: task.id) } label: {
                        HStack(spacing: 12) {
                            Text(task.name).font(.subheadline).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                            chevron
                        }.padding(.vertical, 12).frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Divider()
                }
            } else if model.todos.isLoading { ProgressView("Loading to-dos…").padding(.vertical, 12) }
            if let error = model.todos.error { LoadFailureView(message: error) { Task { await refresh() } } }
            freshness(model.todos.updatedAt, failed: model.todos.error != nil)
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasPacking { shortcut("Pack an order", symbol: "barcode.viewfinder", destination: "packing") }
            shortcut("All apps", symbol: "square.grid.2x2", destination: "more")
        }
    }

    private func shortcut(_ title: String, symbol: String, destination: String) -> some View {
        Button { open(destination) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 22)
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
                chevron
            }.font(.subheadline).frame(minHeight: 48).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private func sectionHeading(_ title: String, action: String, destination: String) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return layout {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            if !typeSize.isAccessibilitySize { Spacer() }
            Button(action) { open(destination) }.font(.subheadline).foregroundStyle(.secondary).frame(minHeight: 44)
        }
    }

    @ViewBuilder private func freshness(_ date: Date?, failed: Bool) -> some View {
        if let date, failed || !network.isOnline {
            Text("Last update \(date.formatted(date: .omitted, time: .shortened)) · may be out of date")
                .font(.caption2).foregroundStyle(.secondary).padding(.top, 8)
        }
    }

    private func refresh() async {
        guard let client = api.client, network.isOnline else { return }
        await menu.load(apiClient: client)
        await model.refresh(client: client, fulfillment: hasFulfillment, manufacturing: hasManufacturing, todo: hasTodo, admin: isAdmin)
    }
}

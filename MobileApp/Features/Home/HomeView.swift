import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var apiProvider: APIClientProvider
    @EnvironmentObject private var syncEngine: SyncEngine
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @StateObject private var viewModel = MenuViewModel()
    @State private var tab = "work"
    @State private var workPath = NavigationPath()
    @State private var warehousePath = NavigationPath()
    @State private var morePath = NavigationPath()
    @State private var search = ""
    @State private var selectedWebModule: MenuItem?

    init(initialTab: String = "work") { _tab = State(initialValue: initialTab) }

    private var hasInventory: Bool { viewModel.items.contains { $0.key == "inventory" } }
    private var hasManufacturing: Bool { viewModel.items.contains { $0.key == "manufacturing" } }
    private var hasPacking: Bool { viewModel.items.contains { $0.key == "packing" && $0.native } }
    /// Odoo's To-Do app (`project_todo`) is handled natively instead of in a web view.
    static func isTodo(_ item: MenuItem) -> Bool { ["project_todo", "todo"].contains(item.key) }

    var body: some View {
        workspaceTabs
        .tint(WorkplaceTheme.accent)
        .task(id: apiProvider.client.map { ObjectIdentifier($0) }) {
            await reload()
            await syncEngine.refresh()
        }
        .onChange(of: networkMonitor.isOnline) { _, online in
            if online { Task { await syncEngine.refresh() } }
        }
        .onChange(of: appState.deepLink) { _, link in
            guard let link else { return }
            switch link {
            case .inventoryHome: tab = "warehouse"; warehousePath.append("inventory")
            case .picking: tab = "warehouse"; warehousePath.append(link)
            case .packingHome: tab = "warehouse"; warehousePath.append("packing")
            case .packingShipment: tab = "warehouse"; warehousePath.append(link)
            case .manufacturingHome: tab = "work"; workPath = NavigationPath()
            case .manufacturingOrder: tab = "work"; workPath.append(link)
            case .salesHome: tab = "more"; morePath.append("sales")
            case .salesOrder: tab = "more"; morePath.append(link)
            case .settings: tab = "more"; morePath.append("settings")
            case .todoHome: tab = "more"; morePath.append("todo")
            case .todo: tab = "more"; morePath.append(link)
            }
            appState.deepLink = nil
        }
        .sheet(item: $selectedWebModule) { item in
            if let url = item.webURL {
                NavigationStack {
                    OdooWebView(title: item.label, targetURL: url)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { selectedWebModule = nil } } }
                }
            }
        }
    }
    @ViewBuilder
    private var workspaceTabs: some View {
        if #available(iOS 18, *) {
            TabView(selection: $tab) {
                Tab("Work", systemImage: "checklist", value: "work") { workWorkspace }
                Tab("Warehouse", systemImage: "shippingbox", value: "warehouse") { warehouseWorkspace }
                Tab("More", systemImage: "ellipsis.circle", value: "more") { moreWorkspace }
            }
        } else {
            TabView(selection: $tab) {
                workWorkspace.tabItem { Label("Work", systemImage: "checklist") }.tag("work")
                warehouseWorkspace.tabItem { Label("Warehouse", systemImage: "shippingbox") }.tag("warehouse")
                moreWorkspace.tabItem { Label("More", systemImage: "ellipsis.circle") }.tag("more")
            }
        }
    }

    private var workWorkspace: some View {
        NavigationStack(path: $workPath) {
            Group {
                if hasManufacturing && authStore.user?.isAdmin == true { AdminWorkOverview() }
                else if hasManufacturing { ManufacturingView(workOrdersFirst: true) }
                else if hasInventory { InventoryView() }
                else if viewModel.isLoading { ProgressView("Loading your work…") }
                else if let message = viewModel.errorMessage { LoadFailureView(message: message) { Task { await reload() } } }
                else { ContentUnavailableView("No assigned workspace", systemImage: "checklist", description: Text("Your available apps are in More.")) }
            }
            .navigationDestination(for: String.self) { destination($0) }
            .navigationDestination(for: DeepLink.self) { deepDestination($0) }
        }
    }

    private var warehouseWorkspace: some View {
        NavigationStack(path: $warehousePath) {
            List {
                if hasPacking {
                    Section("Shipping") {
                        taskLink("Pack orders", subtitle: "Scan a shipping label", symbol: "barcode.viewfinder", key: "packing")
                    }
                }
                if hasInventory {
                    Section("Stock movement") {
                        taskLink("Receipts", subtitle: "Receive incoming goods", symbol: "tray.and.arrow.down", key: "receipts")
                        taskLink("Deliveries", subtitle: "Pick and ship orders", symbol: "shippingbox", key: "deliveries")
                        taskLink("Internal transfers", subtitle: "Move between locations", symbol: "arrow.left.arrow.right", key: "internal")
                    }
                    Section("Stock records") {
                        taskLink("On hand", subtitle: "Availability, counts and scrap", symbol: "square.stack.3d.up", key: "stock")
                        taskLink("History & returns", subtitle: "Completed transfers", symbol: "clock.arrow.circlepath", key: "history")
                        taskLink("My transfers", subtitle: "Ready and assigned to you", symbol: "person.crop.rectangle", key: "inventory")
                    }
                } else if !hasPacking { ContentUnavailableView("Warehouse unavailable", systemImage: "shippingbox") }
                if let message = viewModel.errorMessage { LoadFailureView(message: message) { Task { await reload() } } }
            }
            .listStyle(.plain)
            .listSectionSpacing(12)
            .workplaceScreen()
            .navigationTitle("Warehouse")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await reload() }
            .navigationDestination(for: String.self) { destination($0) }
            .navigationDestination(for: DeepLink.self) { deepDestination($0) }
        }
    }

    private var moreWorkspace: some View {
        NavigationStack(path: $morePath) {
            List {
                if hasManufacturing && matches("Manufacturing") {
                    Section { taskLink("Manufacturing", subtitle: "Plan and create production", symbol: "gearshape.2", key: "manufacturing") }
                }
                Section("Apps") {
                    ForEach(viewModel.items.filter { !["inventory", "manufacturing", "packing", "settings"].contains($0.key) && matches($0.label) }) { item in
                        if item.native && item.key == "sales" {
                            NavigationLink(value: item.key) { WorkplaceActionLabel(title: item.label, subtitle: "Customers and sales orders", symbol: "cart") }
                        } else if Self.isTodo(item) {
                            NavigationLink(value: "todo") { WorkplaceActionLabel(title: item.label, subtitle: "Your personal tasks", symbol: "checklist") }
                        } else if item.webURL != nil {
                            Button { selectedWebModule = item } label: {
                                HStack {
                                    WorkplaceActionLabel(title: item.label, symbol: "square.grid.2x2")
                                    Image(systemName: "arrow.up.forward").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                }
                                .frame(minHeight: 44)
                            }
                        }
                    }
                }
                Section {
                    NavigationLink(value: "settings") { WorkplaceActionLabel(title: "Settings", subtitle: "Account, connection, and help", symbol: "gearshape") }
                } footer: {
                    Label(networkMonitor.isOnline ? "Connected" : "Offline", systemImage: networkMonitor.isOnline ? "checkmark.icloud" : "wifi.slash")
                }
            }
            .workplaceScreen()
            .listStyle(.plain)
            .navigationTitle("More")
            .searchable(text: $search, prompt: "Find an app")
            .navigationDestination(for: String.self) { destination($0) }
            .navigationDestination(for: DeepLink.self) { deepDestination($0) }
        }
    }

    private func taskLink(_ title: String, subtitle: String, symbol: String, key: String) -> some View {
        NavigationLink(value: key) {
            WorkplaceActionLabel(title: title, subtitle: subtitle, symbol: symbol, emphasized: key == "packing")
        }
    }
    @ViewBuilder private func destination(_ key: String) -> some View {
        switch key {
        case "inventory": InventoryView()
        case "packing": PackingView()
        case "receipts": InventoryView(scope: .receipts)
        case "deliveries": InventoryView(scope: .deliveries)
        case "internal": InventoryView(scope: .internalTransfers)
        case "stock": StockOperationsView()
        case "history": InventoryView(scope: .history)
        case "manufacturing": ManufacturingView()
        case "sales": SalesView()
        case "todo": TodoListView()
        case "settings": SettingsView()
        default: ContentUnavailableView("Unavailable", systemImage: "exclamationmark.circle")
        }
    }
    @ViewBuilder private func deepDestination(_ link: DeepLink) -> some View {
        switch link {
        case .picking(let id): InventoryDetailView(pickingId: id)
        case .packingShipment(let id): PackingView(shipmentId: id)
        case .manufacturingOrder(let id): ManufacturingDetailView(orderId: id, workOrdersFirst: true)
        case .salesOrder(let id): SalesOrderDetailView(orderId: id)
        case .todo(let id): TodoDetailView(taskId: id)
        default: EmptyView()
        }
    }
    private func matches(_ value: String) -> Bool { search.isEmpty || value.localizedCaseInsensitiveContains(search) }
    private func reload() async {
        if let client = apiProvider.client { await viewModel.load(apiClient: client) }
    }
}

struct LoadFailureView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkplaceNotice(title: "Unable to refresh", message: message, symbol: "wifi.exclamationmark")
            Button(action: retry) {
                Text("Try again")
            }.buttonStyle(.bordered).controlSize(.large).tint(WorkplaceTheme.accent)
        }.padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - WebView for non-native modules

import WebKit

struct OdooWebView: View {
    let title: String
    let targetURL: String
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var apiProvider: APIClientProvider

    @State private var authenticatedURL: URL?
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        ZStack {
            if let authenticatedURL {
                WebViewRepresentable(
                    url: authenticatedURL,
                    isLoading: $isLoading,
                    error: $error
                )
                .id(authenticatedURL)
            }

            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            }

            if let error {
                Color(.systemBackground).ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Failed to load")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await fetchAuthenticatedURL() }
                    }
                    .buttonStyle(.borderedProminent).tint(WorkplaceTheme.buttonFill)
                }
                .padding()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await fetchAuthenticatedURL()
        }
    }

    private func fetchAuthenticatedURL() async {
        guard let client = apiProvider.client else {
            error = NSError(domain: "OdooWebView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
            isLoading = false
            return
        }

        authenticatedURL = nil
        isLoading = true
        error = nil

        do {
            let endpoint = Endpoint(path: "/api/v1/auth/web-session", method: "GET", queryItems: [
                URLQueryItem(name: "redirect", value: targetURL)
            ])
            let response: WebSessionResponse = try await client.send(endpoint)

            if let url = URL(string: response.loginUrl) {
                authenticatedURL = url
            } else {
                throw NSError(domain: "OdooWebView", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid login URL"])
            }
        } catch {
            self.error = error
            isLoading = false
        }
    }
}

struct WebViewRepresentable: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var error: Error?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.requestedURL != url else { return }
        context.coordinator.requestedURL = url
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewRepresentable
        var requestedURL: URL?

        init(_ parent: WebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.error = nil
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            parent.isLoading = false
            parent.error = NSError(domain: "OdooWebView", code: -4, userInfo: [
                NSLocalizedDescriptionKey: "This Odoo page stopped running. Tap Retry to reopen it."
            ])
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.error = error
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.error = error
        }
    }
}

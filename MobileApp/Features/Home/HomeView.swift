import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var apiProvider: APIClientProvider
    @EnvironmentObject private var syncEngine: SyncEngine
    @EnvironmentObject private var networkMonitor: NetworkMonitor

    @StateObject private var viewModel = MenuViewModel()
    @State private var searchText = ""
    @State private var path = NavigationPath()
    @State private var selectedWebModule: MenuItem?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 16) {
                    SyncStatusBar(
                        lastSync: syncEngine.lastSync,
                        pending: syncEngine.pendingOutboxCount,
                        isOnline: networkMonitor.isOnline
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What would you like to do?").font(.title2.bold())
                        Text("Choose an app to get started.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if viewModel.isLoading && viewModel.items.isEmpty {
                        ProgressView("Loading your apps…").padding(24)
                    }
                    if let message = viewModel.errorMessage {
                        LoadFailureView(message: message) { Task { await reload() } }
                    }
                    if !viewModel.isLoading && viewModel.errorMessage == nil && viewModel.items.isEmpty {
                        ContentUnavailableView("No apps available", systemImage: "square.grid.2x2", description: Text("Ask your Odoo administrator to enable your apps."))
                    }
                    if !searchText.isEmpty && !viewModel.items.isEmpty && !viewModel.items.contains(where: { $0.label.localizedCaseInsensitiveContains(searchText) }) && !(viewModel.items.contains(where: { $0.key == "inventory" }) && "Receive goods Receipts Deliveries Ship goods Internal transfers Move stock Stock on hand Count Scrap Completed transfers Returns History".localizedCaseInsensitiveContains(searchText)) && !(viewModel.items.contains(where: { $0.key == "manufacturing" }) && "Work orders".localizedCaseInsensitiveContains(searchText)) {
                        ContentUnavailableView.search(text: searchText)
                    }
                    if viewModel.items.contains(where: { $0.key == "inventory" }) && (searchText.isEmpty || "Receive goods Receipts".localizedCaseInsensitiveContains(searchText)) {
                        NavigationLink { InventoryView(receiptsOnly: true) } label: {
                            WarehouseTaskCard(title: "Receive goods", subtitle: "Open receipts from suppliers", symbol: "tray.and.arrow.down")
                        }.buttonStyle(.plain)
                    }
                    if viewModel.items.contains(where: { $0.key == "inventory" }) {
                        if searchText.isEmpty || "Stock on hand Count Scrap".localizedCaseInsensitiveContains(searchText) {
                            NavigationLink { StockOperationsView() } label: {
                                WarehouseTaskCard(title: "Stock on hand", subtitle: "Find stock, count quantities and record scrap", symbol: "square.stack.3d.up")
                            }.buttonStyle(.plain)
                        }
                        if searchText.isEmpty || "Completed transfers Returns History".localizedCaseInsensitiveContains(searchText) {
                            NavigationLink { InventoryView(scope: .history) } label: {
                                WarehouseTaskCard(title: "Completed transfers", subtitle: "Review history and return goods", symbol: "clock.arrow.circlepath")
                            }.buttonStyle(.plain)
                        }
                        if searchText.isEmpty || "Deliveries Ship goods".localizedCaseInsensitiveContains(searchText) {
                            NavigationLink { InventoryView(scope: .deliveries) } label: {
                                WarehouseTaskCard(title: "Ship goods", subtitle: "Pick, pack and complete deliveries", symbol: "shippingbox")
                            }.buttonStyle(.plain)
                        }
                        if searchText.isEmpty || "Internal transfers Move stock".localizedCaseInsensitiveContains(searchText) {
                            NavigationLink { InventoryView(scope: .internalTransfers) } label: {
                                WarehouseTaskCard(title: "Move stock", subtitle: "Internal warehouse transfers", symbol: "arrow.left.arrow.right")
                            }.buttonStyle(.plain)
                        }
                    }
                    if viewModel.items.contains(where: { $0.key == "manufacturing" }) && (searchText.isEmpty || "Work orders".localizedCaseInsensitiveContains(searchText)) {
                        NavigationLink { ManufacturingView(workOrdersFirst: true) } label: {
                            WarehouseTaskCard(title: "Work orders", subtitle: "Start, pause and finish operations", symbol: "wrench.and.screwdriver")
                        }.buttonStyle(.plain)
                    }
                    ForEach(viewModel.items.filter { searchText.isEmpty || $0.label.localizedCaseInsensitiveContains(searchText) }) { item in
                        if item.native && ["inventory", "sales", "settings", "manufacturing"].contains(item.key) {
                            NavigationLink(value: item.key) {
                                ModuleTile(item: item)
                            }
                            .buttonStyle(.plain)
                        } else if item.webURL != nil {
                            Button {
                                selectedWebModule = item
                            } label: {
                                ModuleTile(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Home")
            .searchable(text: $searchText, prompt: "Find an app")
            .refreshable { await reload() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: "settings") { Label("Settings", systemImage: "gearshape") }
                }
            }
            .task {
                if let client = apiProvider.client {
                    await viewModel.load(apiClient: client)
                    await syncEngine.refresh()
                }
            }
            .onChange(of: networkMonitor.isOnline) { isOnline in
                guard isOnline, apiProvider.client != nil else { return }
                Task { await syncEngine.refresh() }
            }
            .navigationDestination(for: String.self) { key in
                switch key {
                case "inventory":
                    InventoryView()
                case "manufacturing":
                    ManufacturingView()
                case "sales":
                    SalesView()
                case "settings":
                    SettingsView()
                default:
                    Text("Not available")
                }
            }
            .onChange(of: appState.deepLink) { link in
                guard let link else { return }
                switch link {
                case .inventoryHome:
                    path.append("inventory")
                case .manufacturingHome:
                    path.append("manufacturing")
                case .manufacturingOrder(let id):
                    path.append("manufacturing")
                    path.append(DeepLink.manufacturingOrder(id: id))
                case .salesHome:
                    path.append("sales")
                case .settings:
                    path.append("settings")
                case .picking(let id):
                    path.append("inventory")
                    path.append(DeepLink.picking(id: id))
                case .salesOrder(let id):
                    path.append("sales")
                    path.append(DeepLink.salesOrder(id: id))
                }
                appState.deepLink = nil
            }
            .navigationDestination(for: DeepLink.self) { link in
                switch link {
                case .picking(let id):
                    InventoryDetailView(pickingId: id)
                case .manufacturingOrder(let id):
                    ManufacturingDetailView(orderId: id)
                case .salesOrder(let id):
                    SalesOrderDetailView(orderId: id)
                default:
                    EmptyView()
                }
            }
            .sheet(item: $selectedWebModule) { item in
                if let urlString = item.webURL {
                    NavigationStack {
                        OdooWebView(title: item.label, targetURL: urlString)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") {
                                        selectedWebModule = nil
                                    }
                                }
                            }
                    }
                }
            }
        }
    }
    private func reload() async {
        guard let client = apiProvider.client else { return }
        await viewModel.load(apiClient: client)
    }
}

struct LoadFailureView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Unable to refresh", systemImage: "wifi.exclamationmark").font(.headline)
            Text(message).foregroundStyle(.secondary)
            Button(action: retry) {
                Text("Try again").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.borderedProminent)
        }.padding().frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ModuleTile: View {
    let item: MenuItem

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.title2).foregroundStyle(.tint)
                .frame(width: 52, height: 52)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.label).font(.title3.bold())
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.body.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .contentShape(Rectangle())
    }

    private var symbol: String {
        switch item.key {
        case "inventory": return "shippingbox"
        case "manufacturing": return "gearshape.2"
        case "sales": return "cart"
        case "settings": return "gearshape"
        default: return "square.grid.2x2"
        }
    }

    private var subtitle: String {
        switch item.key {
        case "inventory": return "Pick, scan and complete transfers"
        case "manufacturing": return "Products, components and work orders"
        case "sales": return "Find customers and view orders"
        case "settings": return "Account, connection and sync"
        default: return "Open in Odoo"
        }
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
                    .buttonStyle(.borderedProminent)
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

struct WarehouseTaskCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.title).foregroundStyle(.tint).frame(width: 48)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title3.bold())
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding(20).frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

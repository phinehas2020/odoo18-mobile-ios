import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var apiProvider: APIClientProvider
    @EnvironmentObject private var syncEngine: SyncEngine
    @EnvironmentObject private var networkMonitor: NetworkMonitor

    @StateObject private var viewModel = MenuViewModel()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 16) {
                    SyncStatusBar(
                        lastSync: syncEngine.lastSync,
                        pending: syncEngine.pendingOutboxCount,
                        isOnline: networkMonitor.isOnline
                    )
                    ForEach(viewModel.items) { item in
                        NavigationLink(value: item.key) {
                            ModuleTile(title: item.label)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Modules")
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
                case .salesOrder(let id):
                    SalesOrderDetailView(orderId: id)
                default:
                    EmptyView()
                }
            }
        }
    }
}

struct ModuleTile: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Image(systemName: "chevron.right")
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

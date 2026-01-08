import SwiftUI

@main
struct MobileOdooApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var authStore: AuthStore
    @StateObject private var appState = AppState()
    @StateObject private var config: EnvironmentConfig
    @StateObject private var apiProvider: APIClientProvider
    @StateObject private var syncEngine: SyncEngine
    @StateObject private var networkMonitor = NetworkMonitor()

    init() {
        let authStore = AuthStore()
        let config = EnvironmentConfig()
        let provider = APIClientProvider(config: config, authStore: authStore)
        _authStore = StateObject(wrappedValue: authStore)
        _config = StateObject(wrappedValue: config)
        _apiProvider = StateObject(wrappedValue: provider)
        _syncEngine = StateObject(wrappedValue: SyncEngine())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authStore)
                .environmentObject(appState)
                .environmentObject(config)
                .environmentObject(apiProvider)
                .environmentObject(syncEngine)
                .environmentObject(networkMonitor)
                .onReceive(apiProvider.$client) { client in
                    syncEngine.updateClient(client)
                }
        }
    }
}

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var apiProvider: APIClientProvider

    private let deviceService = DeviceRegistrationService()

    var body: some View {
        Group {
            if authStore.accessToken == nil {
                LoginView()
            } else {
                HomeView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkReceived)) { notification in
            guard let userInfo = notification.object as? [AnyHashable: Any],
                  let link = DeepLinkParser.parse(userInfo: userInfo) else { return }
            appState.deepLink = link
        }
        .onReceive(authStore.$accessToken) { _ in
            registerDeviceIfPossible()
        }
        .onReceive(NotificationCenter.default.publisher(for: .apnsTokenUpdated)) { _ in
            registerDeviceIfPossible()
        }
    }

    private func registerDeviceIfPossible() {
        guard let client = apiProvider.client, authStore.accessToken != nil else { return }
        Task {
            await deviceService.register(apiClient: client)
            await deviceService.heartbeat(apiClient: client)
        }
    }
}

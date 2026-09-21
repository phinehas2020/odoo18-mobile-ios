import Foundation
import Combine

@MainActor
final class APIClientProvider: ObservableObject {
    @Published private(set) var client: APIClient?

    private var cancellables: Set<AnyCancellable> = []

    init(client: APIClient) {
        self.client = client
    }

    init(config: EnvironmentConfig, authStore: AuthStore) {
        config.$baseURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                guard let url else {
                    self?.client = nil
                    return
                }
                self?.client = APIClient(baseURL: url, authStore: authStore)
            }
            .store(in: &cancellables)
    }
}

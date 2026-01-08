import Foundation
import Combine

final class APIClientProvider: ObservableObject {
    @Published private(set) var client: APIClient?

    private var cancellables: Set<AnyCancellable> = []

    init(config: EnvironmentConfig, authStore: AuthStore) {
        config.$baseURL
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

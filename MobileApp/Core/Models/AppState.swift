import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var deepLink: DeepLink?
}

enum DeepLink: Hashable {
    case inventoryHome
    case manufacturingHome
    case manufacturingOrder(id: Int)
    case salesHome
    case settings
    case picking(id: Int)
    case salesOrder(id: Int)
}

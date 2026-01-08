import Foundation

final class AppState: ObservableObject {
    @Published var deepLink: DeepLink?
}

enum DeepLink: Hashable {
    case inventoryHome
    case salesHome
    case settings
    case picking(id: Int)
    case salesOrder(id: Int)
}

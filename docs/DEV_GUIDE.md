# iOS Module Additions

1. Add Codable models under `MobileApp/Core/Models`.
2. Create a new feature folder under `MobileApp/Features/<Module>`.
3. Wire navigation in `HomeView` and deep links in `DeepLinkParser`.
4. For offline actions, enqueue with `OutboxStore` and ensure the server has a matching handler in `mobile.sync.service`.

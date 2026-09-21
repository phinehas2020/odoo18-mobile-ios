import Foundation
import GRDB

@MainActor
final class SyncEngine: ObservableObject {
    @Published private(set) var lastSync: Date?
    @Published private(set) var pendingOutboxCount: Int = 0
    @Published private(set) var failedOutboxCount: Int = 0
    private var isRefreshing = false

    private var apiClient: APIClient?
    private let dbQueue: DatabaseQueue
    private let outboxStore: OutboxStore
    private let errorStore: ApiErrorStore

    init(
        apiClient: APIClient? = nil,
        dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue,
        errorStore: ApiErrorStore = ApiErrorStore.shared
    ) {
        self.apiClient = apiClient
        self.dbQueue = dbQueue
        self.outboxStore = OutboxStore(dbQueue: dbQueue)
        self.errorStore = errorStore
    }

    func updateClient(_ client: APIClient?) {
        apiClient = client
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await pullChanges()
        await pushOutbox()
        updatePendingCount()
    }

    func pullChanges() async {
        guard let apiClient else { return }
        do {
            let cursor = try await dbQueue.read { db -> Int in
                try Int.fetchOne(db, sql: "SELECT cursor FROM sync_state WHERE id = 1") ?? 0
            }
            let endpoint = Endpoint(path: "/api/v1/sync/changes", method: "GET", queryItems: [
                URLQueryItem(name: "cursor", value: String(cursor))
            ])
            let response: SyncChangesResponse = try await apiClient.send(endpoint)
            try await dbQueue.write { db in
                if try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_state") == 0 {
                    try db.execute(sql: "INSERT INTO sync_state (id, cursor) VALUES (1, ?)", arguments: [response.cursor])
                } else {
                    try db.execute(sql: "UPDATE sync_state SET cursor = ?, last_sync_at = ? WHERE id = 1", arguments: [response.cursor, Date()])
                }
            }
            lastSync = Date()
        } catch {
            errorStore.record(endpoint: "/api/v1/sync/changes", logURL: nil, message: error.localizedDescription)
        }
    }

    func pushOutbox() async {
        guard let apiClient else { return }
        do {
            let actions = try outboxStore.pendingActions()
            pendingOutboxCount = actions.count
            if actions.isEmpty { return }

            let request = SyncPushRequest(deviceId: DeviceStore.shared.deviceId, actions: actions)
            let body = try DateCoding.encoder.encode(request)
            let endpoint = Endpoint(path: "/api/v1/sync/push", method: "POST", body: body)
            let response: SyncPushResponse = try await apiClient.send(endpoint)

            for result in response.results {
                try outboxStore.mark(eventId: result.eventId, status: result.status)
            }
            updatePendingCount()
        } catch {
            errorStore.record(endpoint: "/api/v1/sync/push", logURL: nil, message: error.localizedDescription)
        }
    }

    private func updatePendingCount() {
        failedOutboxCount = (try? outboxStore.failedCount()) ?? failedOutboxCount
        pendingOutboxCount = (try? outboxStore.pendingCount()) ?? pendingOutboxCount
    }
}

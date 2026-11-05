import Foundation

enum TodoAPI {
    static let tasks = "/api/v1/todo/tasks"
    static func task(_ id: Int) -> String { "\(tasks)/\(id)" }

    static func patch(_ id: Int, _ patch: TodoPatch, client: APIClient) async throws -> TodoDetail {
        try await client.send(Endpoint(path: task(id), method: "PATCH", body: try DateCoding.encoder.encode(patch)))
    }
}

@MainActor
final class TodoListViewModel: ObservableObject {
    @Published var items: [TodoItem] = []
    @Published var stages: [TodoStage] = []
    @Published var filter: TodoFilter = .open
    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var truncated = false
    @Published var errorMessage: String?
    /// A failed check-off, star or delete. Shown above the list without hiding it.
    @Published var actionMessage: String?
    @Published private(set) var busyIds: Set<Int> = []

    private var loadGeneration = 0

    func sections(matching search: String) -> [TodoSection] {
        let visible = search.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(search) }
        if filter == .done { return visible.isEmpty ? [] : [TodoSection(id: "done", title: "Completed", items: visible)] }
        return TodoSection.group(visible, stages: stages)
    }

    func load(client: APIClient) async {
        loadGeneration += 1
        let generation = loadGeneration
        let requested = filter
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let response: TodoListResponse = try await client.send(Endpoint(
                path: TodoAPI.tasks, method: "GET",
                queryItems: [URLQueryItem(name: "status", value: requested.rawValue)]))
            // A filter switch while this request was in flight makes the result stale.
            guard generation == loadGeneration else { return }
            items = response.items
            stages = response.stages
            truncated = response.truncated
            errorMessage = nil
            hasLoaded = true
        } catch {
            guard generation == loadGeneration else { return }
            if case APIError.httpStatus(404) = error {
                errorMessage = "To-do isn’t enabled on this Odoo server yet. Ask your administrator to install Mobile API To-Do."
            } else {
                errorMessage = Self.message(for: error, fallback: "Couldn’t load your to-dos.")
            }
        }
    }

    func setFilter(_ value: TodoFilter, client: APIClient?) async {
        guard value != filter else { return }
        filter = value
        items = []
        hasLoaded = false
        if let client { await load(client: client) }
    }

    func toggleDone(_ item: TodoItem, client: APIClient) async {
        let target = !item.done
        await mutate(item.id, client: client, patch: TodoPatch(done: target), failure: target ? "Couldn’t complete this to-do." : "Couldn’t reopen this to-do.") {
            $0.done = target
            $0.closed = target
        }
    }

    func toggleStar(_ item: TodoItem, client: APIClient) async {
        let target = !item.starred
        await mutate(item.id, client: client, patch: TodoPatch(starred: target), failure: "Couldn’t update the star.") { $0.starred = target }
    }

    func move(_ item: TodoItem, to stage: TodoStage, client: APIClient) async {
        guard item.stageId != stage.id else { return }
        await mutate(item.id, client: client, patch: TodoPatch(stageId: stage.id), failure: "Couldn’t move this to-do.") {
            $0.stageId = stage.id
            $0.stageName = stage.name
        }
    }

    func delete(_ item: TodoItem, client: APIClient) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        actionMessage = nil
        let removed = items.remove(at: index)
        do {
            try await client.sendNoResponse(Endpoint(path: TodoAPI.task(item.id), method: "DELETE"))
        } catch {
            items.insert(removed, at: min(index, items.count))
            actionMessage = Self.message(for: error, fallback: "Couldn’t delete “\(item.name)”.")
        }
    }

    func create(_ request: TodoCreateRequest, client: APIClient) async throws -> TodoItem {
        let detail: TodoDetail = try await client.send(Endpoint(
            path: TodoAPI.tasks, method: "POST", body: try DateCoding.encoder.encode(request)))
        if filter == .open { items.insert(detail.item, at: 0) }
        return detail.item
    }

    /// Detail screens report saved changes so the list stays current without a reload.
    func apply(_ item: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    func remove(id: Int) { items.removeAll { $0.id == id } }

    func isBusy(_ id: Int) -> Bool { busyIds.contains(id) }

    private func mutate(_ id: Int, client: APIClient, patch: TodoPatch, failure: String, change: (inout TodoItem) -> Void) async {
        guard let index = items.firstIndex(where: { $0.id == id }), !busyIds.contains(id) else { return }
        actionMessage = nil
        let original = items[index]
        change(&items[index])
        busyIds.insert(id)
        defer { busyIds.remove(id) }
        do {
            let detail = try await TodoAPI.patch(id, patch, client: client)
            apply(detail.item)
        } catch {
            if let current = items.firstIndex(where: { $0.id == id }) { items[current] = original }
            actionMessage = Self.message(for: error, fallback: failure)
        }
    }

    static func message(for error: Error, fallback: String) -> String {
        if case APIError.rejected(_, let message) = error { return message }
        if case APIError.httpStatus(404) = error { return "This to-do was removed or is no longer assigned to you. Pull to refresh." }
        return fallback + " " + APIClient.failureMessage(error)
    }
}

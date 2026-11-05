import XCTest
import SwiftUI
@testable import MobileOdoo

final class TodoTests: XCTestCase {
    static let listFixture = Data(#"""
    {"items":[
      {"id":11,"name":"Order more flour bags","state":"01_in_progress","done":false,"closed":false,"starred":true,
       "date_deadline":"2026-11-05 23:00:00","stage_id":2,"stage_name":"Today","tags":[{"id":1,"name":"Purchasing","color":3}],
       "assignees":[{"id":2,"name":"Admin"}],"has_description":true},
      {"id":12,"name":"Call the rye supplier about the late delivery and confirm the new pallet count","state":"01_in_progress","done":false,"closed":false,"starred":false,
       "date_deadline":"2026-10-01 15:00:00","stage_id":1,"stage_name":"Inbox","tags":[],
       "assignees":[{"id":2,"name":"Admin"},{"id":7,"name":"Samuel"}],"has_description":false},
      {"id":13,"name":"Clean the sifter screens","state":"01_in_progress","done":false,"closed":false,"starred":false,
       "date_deadline":null,"stage_id":3,"stage_name":"This Week","tags":[],"assignees":[{"id":2,"name":"Admin"}],"has_description":false},
      {"id":14,"name":"Review label proofs","state":"01_in_progress","done":false,"closed":false,"starred":false,
       "date_deadline":null,"stage_id":null,"stage_name":null,"tags":[],"assignees":[{"id":2,"name":"Admin"}],"has_description":false}
    ],
    "stages":[{"id":1,"name":"Inbox","sequence":1,"folded":false},{"id":2,"name":"Today","sequence":2,"folded":false},
              {"id":3,"name":"This Week","sequence":3,"folded":false},{"id":4,"name":"Later","sequence":5,"folded":false}],
    "truncated":false}
    """#.utf8)

    static func detailFixture(id: Int = 11, done: Bool = false, starred: Bool = true) -> Data {
        Data(#"""
        {"id":\#(id),"name":"Order more flour bags","state":"\#(done ? "1_done" : "01_in_progress")","done":\#(done),"closed":\#(done),"starred":\#(starred),
         "date_deadline":"2026-11-05 23:00:00","stage_id":2,"stage_name":"Today","tags":[{"id":1,"name":"Purchasing","color":3}],
         "assignees":[{"id":2,"name":"Admin"},{"id":7,"name":"Samuel"}],"has_description":true,
         "description_html":"<p>Ask for <b>50 lb</b> bags.</p><ul><li>Einkorn</li><li>Spelt</li></ul>"}
        """#.utf8)
    }

    @MainActor
    private func client() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return APIClient(baseURL: URL(string: "https://example.com")!, authStore: AuthStore(), session: URLSession(configuration: config), errorStore: nil)
    }

    private func respond(_ status: Int, _ body: Data, for request: URLRequest) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, body)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: Models

    func testListDecodesOdooNaiveUTCDeadlinesAndGroupsByPersonalStage() throws {
        let response = try DateCoding.decoder.decode(TodoListResponse.self, from: Self.listFixture)
        XCTAssertEqual(response.items.count, 4)
        let first = try XCTUnwrap(response.items.first)
        XCTAssertEqual(first.dateDeadline, ISO8601DateFormatter().date(from: "2026-11-05T23:00:00Z"))
        XCTAssertEqual(first.tags.map(\.name), ["Purchasing"])
        let sections = TodoSection.group(response.items, stages: response.stages)
        XCTAssertEqual(sections.map(\.title), ["No stage", "Inbox", "Today", "This Week"], "Empty stages are hidden and stage order is kept")
        XCTAssertEqual(sections.flatMap(\.items).count, 4, "Every to-do lands in exactly one section")
    }

    func testDetailKeepsNotesHTMLAlongsideTheItem() throws {
        let detail = try DateCoding.decoder.decode(TodoDetail.self, from: Self.detailFixture())
        XCTAssertEqual(detail.item.assignees.count, 2)
        XCTAssertTrue(detail.descriptionHTML.contains("<b>50 lb</b>"))
        let text = String(QualityInstructionText.render(detail.descriptionHTML, baseURL: nil).characters)
        XCTAssertTrue(text.contains("Ask for 50 lb bags."))
        XCTAssertTrue(text.contains("• Einkorn"))
    }

    func testPatchSendsOnlyChangedFieldsAndExplicitNullToClear() throws {
        func json(_ patch: TodoPatch) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: DateCoding.encoder.encode(patch)) as? [String: Any])
        }
        XCTAssertEqual(try json(TodoPatch(done: true)) as NSDictionary, ["done": true])
        let cleared = try json(TodoPatch(dateDeadline: .some(nil), descriptionText: .some(nil)))
        XCTAssertEqual(Set(cleared.keys), ["date_deadline", "description_text"])
        XCTAssertTrue(cleared["date_deadline"] is NSNull)
        XCTAssertTrue(cleared["description_text"] is NSNull)
        let dated = try json(TodoPatch(dateDeadline: .some(Date(timeIntervalSince1970: 0))))
        XCTAssertEqual(dated["date_deadline"] as? String, "1970-01-01T00:00:00.000Z")
        XCTAssertTrue(try json(TodoPatch()).isEmpty)
    }

    func testTodoMenuEntryIsNativeAndDeepLinksParse() throws {
        let data = Data(#"{"items":[{"key":"project_todo","label":"To-do","web_url":"https://example.com/web#action=9"},{"key":"crm","label":"CRM","web_url":"https://example.com/web#action=3"}]}"#.utf8)
        let items = try JSONDecoder().decode(MenuResponse.self, from: data).items
        XCTAssertEqual(items.map(HomeView.isTodo), [true, false])
        XCTAssertEqual(DeepLinkParser.parse(userInfo: ["deeplink": ["module": "todo"]]), .todoHome)
        XCTAssertEqual(DeepLinkParser.parse(userInfo: ["deeplink": ["module": "project_todo", "id": 11]]), .todo(id: 11))
    }

    func testDefaultDeadlineIsNextFivePM() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 19))!
        XCTAssertEqual(calendar.dateComponents([.day, .hour], from: TodoComposeSheet.defaultDeadline(now: morning, calendar: calendar)), DateComponents(day: 5, hour: 17))
        XCTAssertEqual(calendar.dateComponents([.day, .hour], from: TodoComposeSheet.defaultDeadline(now: evening, calendar: calendar)), DateComponents(day: 6, hour: 17))
    }

    // MARK: View model

    @MainActor
    func testLoadRequestsOpenToDos() async {
        var paths: [String] = []
        MockURLProtocol.requestHandler = { request in
            paths.append("\(request.httpMethod!) \(request.url!.path)?\(request.url!.query ?? "")")
            return self.respond(200, Self.listFixture, for: request)
        }
        let model = TodoListViewModel()
        await model.load(client: client())
        XCTAssertEqual(paths, ["GET /api/v1/todo/tasks?status=open"])
        XCTAssertEqual(model.items.count, 4)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testMissingServerModuleExplainsWhatToInstall() async {
        MockURLProtocol.requestHandler = { request in self.respond(404, Data(#"{"detail":"Not Found"}"#.utf8), for: request) }
        let model = TodoListViewModel()
        await model.load(client: client())
        XCTAssertEqual(model.errorMessage?.contains("Mobile API To-Do"), true)
    }

    @MainActor
    func testCompletingSendsDoneAndKeepsServerResult() async throws {
        let client = client()
        MockURLProtocol.requestHandler = { request in self.respond(200, Self.listFixture, for: request) }
        let model = TodoListViewModel()
        await model.load(client: client)
        var sent: [String: Any] = [:]
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/todo/tasks/11")
            let body = request.httpBody ?? request.httpBodyStream.map { stream in
                stream.open(); defer { stream.close() }
                var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: 1024); if n <= 0 { break }; data.append(buffer, count: n) }
                return data
            } ?? Data()
            sent = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
            return self.respond(200, Self.detailFixture(done: true), for: request)
        }
        await model.toggleDone(try XCTUnwrap(model.items.first), client: client)
        XCTAssertEqual(sent as NSDictionary, ["done": true])
        XCTAssertEqual(model.items.first?.done, true)
        XCTAssertEqual(model.items.first?.assignees.count, 2, "The list adopts the server's saved copy")
        XCTAssertNil(model.actionMessage)
    }

    @MainActor
    func testRejectedChangeRollsBackAndShowsOdooMessage() async throws {
        let client = client()
        MockURLProtocol.requestHandler = { request in self.respond(200, Self.listFixture, for: request) }
        let model = TodoListViewModel()
        await model.load(client: client)
        MockURLProtocol.requestHandler = { request in
            self.respond(400, Data(#"{"detail":"You cannot close a task blocked by another task."}"#.utf8), for: request)
        }
        await model.toggleDone(try XCTUnwrap(model.items.first), client: client)
        XCTAssertEqual(model.items.first?.done, false)
        XCTAssertEqual(model.actionMessage, "You cannot close a task blocked by another task.")
        XCTAssertFalse(model.isBusy(11))
    }

    @MainActor
    func testFailedDeleteRestoresTheRow() async throws {
        let client = client()
        MockURLProtocol.requestHandler = { request in self.respond(200, Self.listFixture, for: request) }
        let model = TodoListViewModel()
        await model.load(client: client)
        let target = model.items[1]
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            return self.respond(500, Data(), for: request)
        }
        await model.delete(target, client: client)
        XCTAssertEqual(model.items.map(\.id), [11, 12, 13, 14])
        XCTAssertNotNil(model.actionMessage)
    }

    // MARK: Rendering

    @MainActor
    private func capture<V: View>(_ view: V, name: String) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(1500))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("todo-\(name).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("UX_SCREEN \(url.path)")
    }

    @MainActor
    func testTodoScreensRenderNatively() async throws {
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/v1/todo/tasks" { return self.respond(200, Self.listFixture, for: request) }
            if request.url?.path == "/api/v1/todo/stages" {
                return self.respond(200, Data(#"[{"id":1,"name":"Inbox","sequence":1,"folded":false},{"id":2,"name":"Today","sequence":2,"folded":false}]"#.utf8), for: request)
            }
            return self.respond(200, Self.detailFixture(), for: request)
        }
        let provider = APIClientProvider(client: client())
        let config = EnvironmentConfig(defaults: UserDefaults(suiteName: "todo-render-\(UUID().uuidString)")!)
        for (name, scheme, size) in [("list", ColorScheme.light, DynamicTypeSize.large), ("list-dark", .dark, .large), ("list-large", .light, .accessibility2)] {
            let view = NavigationStack { TodoListView() }
                .environmentObject(provider).environmentObject(config)
                .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
            try await capture(view, name: name)
        }
        let detail = NavigationStack { TodoDetailView(taskId: 11) }
            .environmentObject(provider).environmentObject(config)
        try await capture(detail, name: "detail")
        let compose = TodoComposeSheet(stages: [TodoStage(id: 1, name: "Inbox", sequence: 1, folded: false)]) { _ in }
        try await capture(compose, name: "compose")
    }
}

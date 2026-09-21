import XCTest
@testable import MobileOdoo

final class MenuTests: XCTestCase {
    func testSharedModuleKeysHaveDistinctStableIdentities() throws {
        let data = Data(#"{"items":[{"key":"base","label":"Contacts","web_url":"https://example.com/web#action=1"},{"key":"base","label":"Settings","web_url":"https://example.com/web#action=2"}]}"#.utf8)
        let first = try JSONDecoder().decode(MenuResponse.self, from: data).items
        let second = try JSONDecoder().decode(MenuResponse.self, from: data).items
        XCTAssertNotEqual(first[0].id, first[1].id)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.map(\.key), ["base", "base"])
    }

    @MainActor
    func testMenuPreservesDistinctDestinationsAndRemovesExactDuplicates() async {
        defer { MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { request in
            let data = Data(#"{"items":[{"key":"base","label":"Contacts","web_url":"https://example.com/web#action=1"},{"key":"base","label":"Settings","web_url":"https://example.com/web#action=2"},{"key":"base","label":"Contacts","web_url":"https://example.com/web#action=1"},{"key":"hidden","label":"Hidden","enabled":false}]}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = APIClient(baseURL: URL(string: "https://example.com")!, authStore: AuthStore(), session: URLSession(configuration: configuration), errorStore: nil)
        let model = MenuViewModel()
        await model.load(apiClient: client)
        XCTAssertEqual(model.items.map(\.label), ["Contacts", "Settings"])
        XCTAssertEqual(Set(model.items.map(\.id)).count, model.items.count)
    }
}

import XCTest
@testable import MobileOdoo

final class WarehouseTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    @MainActor
    private func client() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return APIClient(baseURL: URL(string: "https://example.com")!, authStore: AuthStore(), session: URLSession(configuration: config), errorStore: nil)
    }

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else {
            throw NSError(domain: "WarehouseTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Request has no body"])
        }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }

    @MainActor
    func testReceiptsExcludeDeliveriesAndIncludeAllAssignees() async {
        MockURLProtocol.requestHandler = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first(where: { $0.name == "mine" })?.value, "0")
            let json = #"[{"id":1,"name":"IN/001","picking_type_code":"incoming","progress":{"done":0,"total":5}},{"id":2,"name":"OUT/001","picking_type_code":"outgoing","progress":{"done":0,"total":5}}]"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let model = InventoryViewModel()
        await model.load(apiClient: client(), receiptsOnly: true)
        XCTAssertEqual(model.pickings.map(\.id), [1])
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testLegacyAPIIsNotMisrepresentedAsReceipts() async {
        MockURLProtocol.requestHandler = { request in
            let json = #"[{"id":1,"name":"Transfer","progress":{"done":0,"total":5}}]"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let model = InventoryViewModel()
        await model.load(apiClient: client(), receiptsOnly: true)
        XCTAssertTrue(model.pickings.isEmpty)
        XCTAssertNotNil(model.errorMessage)
    }

    func testScannerDetectionGateSuppressesDuplicateCallbacksUntilReset() {
        var gate = BarcodeDetectionGate()
        XCTAssertEqual(gate.accept("012345"), "012345")
        XCTAssertNil(gate.accept("012345"))
        XCTAssertNil(gate.accept("999999"))
        gate.reset()
        XCTAssertEqual(gate.accept("999999"), "999999")
    }

    @MainActor
    func testCreatingReceiptLineUsesAbsoluteQuantityAndMoveContract() async throws {
        let api = client()
        let model = InventoryDetailViewModel()
        MockURLProtocol.requestHandler = { request in
            let json = #"{"id":1,"name":"WH/IN/001","state":"assigned","picking_type_code":"incoming","source_location":{"id":1,"name":"Vendors"},"dest_location":{"id":2,"name":"Stock"},"record_version":"v1","lines":[],"moves":[{"id":22,"product_id":7,"product_name":"Cornmeal","qty_demanded":5,"qty_done":0,"tracking":"lot"}]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        await model.load(apiClient: api, pickingId: 1)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/inventory/pickings/1/lines")
            let body = try Self.bodyData(from: request)
            let payload = try JSONDecoder().decode(PickingLineCreateRequest.self, from: body)
            XCTAssertEqual(payload.moveId, 22)
            XCTAssertEqual(payload.qtyDone, 3)
            XCTAssertEqual(payload.lotName, "LOT-24")
            let json = #"{"status":"success","record_version":"v2","line":{"id":101,"move_id":22,"product_id":7,"product_name":"Cornmeal","qty_done":3,"qty_reserved":0,"qty_demanded":5,"lot_name":"LOT-24","tracking":"lot"}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let saved = await model.createLine(
            apiClient: api,
            pickingId: 1,
            moveId: 22,
            quantity: 3,
            lotId: nil,
            lotName: "LOT-24",
            isOnline: true
        )
        XCTAssertTrue(saved)
        XCTAssertEqual(model.detail?.lines.first?.qtyDone, 3)
        XCTAssertEqual(model.detail?.recordVersion, "v2")
    }

    @MainActor
    func testValidateWaitsForExplicitBackorderDecision() async {
        let api = client()
        let model = InventoryDetailViewModel()
        MockURLProtocol.requestHandler = { request in
            let json = #"{"id":1,"name":"WH/IN/001","state":"assigned","source_location":{"id":1,"name":"Vendors"},"dest_location":{"id":2,"name":"Stock"},"record_version":"v1","lines":[]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        await model.load(apiClient: api, pickingId: 1)

        MockURLProtocol.requestHandler = { request in
            let body = try Self.bodyData(from: request)
            let payload = try JSONDecoder().decode(ValidateRequest.self, from: body)
            XCTAssertEqual(payload.backorderPolicy, .ask)
            let json = #"{"status":"needs_backorder","picking_state":"assigned","record_version":"v2","backorder_required":true,"message":"Two units remain."}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        await model.validate(apiClient: api, pickingId: 1, isOnline: true)
        XCTAssertTrue(model.needsBackorderDecision)
        XCTAssertEqual(model.detail?.state, "assigned")
        XCTAssertEqual(model.detail?.recordVersion, "v2")
        XCTAssertNil(model.lastScanStatus)
    }

    func testWorkOrderActionsFollowStateAndCurrentWorker() throws {
        func work(_ state: String, working: Bool = false) throws -> ManufacturingWorkOrder {
            let json = "{\"id\":1,\"name\":\"Pack\",\"state\":\"\(state)\",\"is_user_working\":\(working)}"
            return try JSONDecoder().decode(ManufacturingWorkOrder.self, from: Data(json.utf8))
        }
        XCTAssertTrue(try work("ready").canStart)
        XCTAssertFalse(try work("pending").canStart)
        XCTAssertTrue(try work("progress", working: true).canPause)
        XCTAssertFalse(try work("progress").canPause)
        XCTAssertTrue(try work("progress").canFinish)
        XCTAssertFalse(try work("done").canFinish)
    }

    @MainActor
    func testUncertainWorkOrderActionRequiresRefresh() async {
        let api = client()
        let model = ManufacturingDetailViewModel()
        MockURLProtocol.requestHandler = { request in
            let json = #"{"id":1,"name":"MO/001","state":"progress","components":[],"workorders":[{"id":2,"name":"Pack","state":"ready","is_user_working":false}]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        await model.load(client: api, id: 1)
        var requests = 0
        MockURLProtocol.requestHandler = { request in
            requests += 1
            XCTAssertEqual(request.url?.path, "/api/v1/manufacturing/workorders/2/start")
            throw URLError(.timedOut)
        }
        await model.perform(client: api, workOrderId: 2, action: "start")
        await model.perform(client: api, workOrderId: 2, action: "start")
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(model.requiresRefresh)
        XCTAssertNotNil(model.errorMessage)
    }
}

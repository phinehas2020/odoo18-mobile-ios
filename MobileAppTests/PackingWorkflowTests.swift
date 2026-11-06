import XCTest
@testable import MobileOdoo

final class PackingWorkflowTests: XCTestCase {
    func testDiscountCardGuidance() throws {
        var json = try JSONSerialization.jsonObject(with: Self.fixture()) as! [String: Any]
        func decode() throws -> PackingDetail {
            try JSONDecoder().decode(PackingDetail.self, from: JSONSerialization.data(withJSONObject: json))
        }
        XCTAssertEqual(try decode().customerHistoryTitle, "Customer history unavailable")
        XCTAssertEqual(try decode().discountCardInstruction, "Check customer history before adding a discount card.")
        json["customer_order_count"] = 1
        XCTAssertEqual(try decode().customerHistoryTitle, "First-time customer")
        XCTAssertEqual(try decode().discountCardInstruction, "Add discount card — one card for this order")
        json["box_number"] = 2
        XCTAssertEqual(try decode().discountCardInstruction, "Add discount card to box 1 only")
        json["box_count"] = 1
        json["box_number"] = 1
        XCTAssertEqual(try decode().discountCardInstruction, "Add discount card")
        json["customer_order_count"] = 3
        XCTAssertEqual(try decode().customerHistoryTitle, "Repeat customer")
        XCTAssertEqual(try decode().discountCardInstruction, "Do not add discount card")
        json["customer_order_count"] = 0
        XCTAssertEqual(try decode().customerHistoryTitle, "Customer history unavailable")
    }

    private static let device = "packing-test-device"
    private let scan = BarcodeCandidate(barcode: "1ZTEST000123456789", symbology: "code128")

    override func tearDown() { MockURLProtocol.requestHandler = nil; super.tearDown() }

    @MainActor
    private func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return APIClient(baseURL: URL(string: "https://example.com")!, authStore: AuthStore(), session: URLSession(configuration: configuration), errorStore: nil)
    }

    static func fixture(id: Int = 42, confirmed: Double = 0, version: Int = 1, packing: String = "in_progress", operational: String = "pending", sync: String = "not_ready", edit: Bool = true, complete: Bool = true, review: String? = nil) throws -> Data {
        var json: [String: Any] = [
            "shipment_id": id, "order_id": 9, "order_name": "#1042", "customer_name": "Packing test customer",
            "tracking_number": "1ZTEST000123456789", "carrier": "ups", "box_number": 1, "box_count": 2,
            "packing_state": packing, "operational_state": operational, "sync_state": sync,
            "order_state": operational == "complete" && sync == "synced" ? "shipped" : "ready_to_ship",
            "version": version, "workflow_version": "packing_v1", "owner": ["id": 7, "name": "Warehouse worker"],
            "items": [["line_id": 12, "title": "Stoneground yellow cornmeal", "variant_title": "2 lb bag", "sku": "CORN-2", "product_id": 18, "required_quantity": 3.0, "confirmed_quantity": confirmed, "remaining_quantity": max(0, 3 - confirmed)]],
            "siblings": [["shipment_id": id, "box_number": 1, "packing_state": packing], ["shipment_id": 43, "box_number": 2, "packing_state": "unstarted"]],
            "allowed_actions": ["claim": false, "edit": edit, "complete": complete],
            "resolved_barcode": "1ZTEST000123456789", "resolved_symbology": "code128"
        ]
        if let review { json["review_reason"] = review }
        return try JSONSerialization.data(withJSONObject: json)
    }

    static var capabilities: Data { Data(#"{"enabled":true,"business_enabled":true,"can_pack":true,"can_supervise":false,"requires_online":true,"workflow_version":"packing_v1"}"#.utf8) }

    private static func response(_ request: URLRequest, data: Data, status: Int = 200) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, data)
    }

    static func body(_ request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let body = request.httpBody { data = body }
        else {
            let stream = try XCTUnwrap(request.httpBodyStream)
            stream.open(); defer { stream.close() }
            var result = Data()
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
                if count == 0 { break }
                result.append(bytes, count: count)
            }
            data = result
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @MainActor
    private func prepared(confirmed: Double = 0, store: PackingRecoveryStore? = nil) async throws -> (PackingViewModel, APIClient) {
        let api = client()
        MockURLProtocol.requestHandler = { request in
            if request.url?.path.hasSuffix("capabilities") == true { return Self.response(request, data: Self.capabilities) }
            return Self.response(request, data: try Self.fixture(confirmed: confirmed))
        }
        let model = PackingViewModel(recoveryStore: store ?? PackingRecoveryStore(defaults: UserDefaults(suiteName: UUID().uuidString)!), deviceId: Self.device)
        await model.prepare(client: api, online: true, userId: 7, companyId: 1)
        _ = await model.resolve(candidates: [scan], client: api, online: true)
        return (model, api)
    }

    @MainActor
    func testRefreshObservesServerActivationAndEmergencyShutoff() async throws {
        let (model, api) = try await prepared(confirmed: 3)
        for enabled in [false, true, false] {
            MockURLProtocol.requestHandler = { request in
                if request.url?.path.hasSuffix("capabilities") == true {
                    var payload = try JSONSerialization.jsonObject(with: Self.capabilities) as! [String: Any]
                    payload["business_enabled"] = enabled
                    return Self.response(request, data: try JSONSerialization.data(withJSONObject: payload))
                }
                return Self.response(request, data: try Self.fixture(confirmed: 3))
            }
            await model.refresh(client: api, online: true)
            XCTAssertEqual(model.canWritePacking, enabled)
            XCTAssertEqual(model.canFinish, enabled)
        }
    }

    @MainActor
    func testFailedCapabilityRefreshDisablesPackingWrites() async throws {
        let (model, api) = try await prepared(confirmed: 3)
        XCTAssertTrue(model.canFinish)
        MockURLProtocol.requestHandler = { _ in throw URLError(.timedOut) }
        await model.refresh(client: api, online: true)
        XCTAssertFalse(model.canWritePacking)
        XCTAssertFalse(model.canFinish)
        XCTAssertTrue(model.requiresRefresh)
    }

    @MainActor
    func testLabelLookupIsReadOnlyAndKeepsAllUniqueCandidates() async throws {
        let (model, api) = try await prepared()
        let second = BarcodeCandidate(barcode: "OTHER", symbology: "qr")
        var paths: [String] = []
        MockURLProtocol.requestHandler = { request in
            paths.append(request.url!.path)
            let body = try Self.body(request)
            XCTAssertEqual(body["device_id"] as? String, Self.device)
            XCTAssertEqual((body["candidates"] as? [[String: String]])?.count, 2)
            return Self.response(request, data: try Self.fixture())
        }
        let accepted = await model.resolve(candidates: [scan, scan, second], client: api, online: true)
        XCTAssertTrue(accepted)
        XCTAssertEqual(paths, ["/api/v1/shopify/packing/resolve"])
        XCTAssertEqual(model.detail?.shipmentId, 42)
    }

    @MainActor
    func testCameraScanCannotCompleteWithoutExplicitFinishAction() async throws {
        let (model, api) = try await prepared(confirmed: 3)
        var calls = 0
        MockURLProtocol.requestHandler = { request in calls += 1; return Self.response(request, data: try Self.fixture()) }
        let result = await model.finish(candidates: [scan], client: api, online: true, userId: 7, companyId: 1)
        XCTAssertFalse(result)
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(model.beginFinish())
        model.cancelFinish()
        let afterCancel = await model.finish(candidates: [scan], client: api, online: true, userId: 7, companyId: 1)
        XCTAssertFalse(afterCancel)
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testWrongLabelDoesNotSendCompletionAndCanBeScannedAgain() async throws {
        let (model, api) = try await prepared(confirmed: 3)
        XCTAssertTrue(model.beginFinish())
        var paths: [String] = []
        MockURLProtocol.requestHandler = { request in
            paths.append(request.url!.path)
            return Self.response(request, data: try Self.fixture(id: 99, confirmed: 3))
        }
        let result = await model.finish(candidates: [scan], client: api, online: true, userId: 7, companyId: 1)
        XCTAssertFalse(result)
        XCTAssertEqual(paths, ["/api/v1/shopify/packing/resolve"])
        XCTAssertEqual(model.detail?.shipmentId, 42)
        XCTAssertFalse(model.requiresRefresh)
        XCTAssertTrue(model.errorMessage?.contains("another box") == true)
    }

    @MainActor
    func testProgressUsesAbsoluteQuantityAndVersionOnDirectRoute() async throws {
        let (model, api) = try await prepared()
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/shopify/packing/42/items/12")
            let body = try Self.body(request)
            XCTAssertEqual(body["quantity"] as? Double, 3)
            XCTAssertNil(body["increment"])
            XCTAssertEqual(body["version"] as? Int, 1)
            XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(body["event_id"] as? String)))
            return Self.response(request, data: try Self.fixture(confirmed: 3, version: 2))
        }
        await model.setQuantity(lineId: 12, quantity: 3, client: api, online: true)
        XCTAssertEqual(model.detail?.version, 2)
        XCTAssertTrue(model.canFinish)
    }

    @MainActor
    func testSimultaneousCameraCallbacksSendOneVersionedCompletion() async throws {
        let (model, api) = try await prepared(confirmed: 3)
        XCTAssertTrue(model.beginFinish())
        var completes = 0
        MockURLProtocol.requestHandler = { request in
            if request.url!.path.hasSuffix("/complete") {
                completes += 1
                let body = try Self.body(request)
                XCTAssertEqual(body["barcode"] as? String, "1ZTEST000123456789")
                XCTAssertEqual(body["symbology"] as? String, "code128")
                XCTAssertEqual(body["version"] as? Int, 1)
                return Self.response(request, data: try Self.fixture(confirmed: 3, version: 2, packing: "packed", edit: false, complete: false))
            }
            return Self.response(request, data: try Self.fixture(confirmed: 3))
        }
        async let first = model.finish(candidates: [scan], client: api, online: true, userId: 7, companyId: 1)
        async let duplicate = model.finish(candidates: [scan], client: api, online: true, userId: 7, companyId: 1)
        _ = await (first, duplicate)
        XCTAssertEqual(completes, 1)
        XCTAssertTrue(model.detail?.isPacked == true)
        XCTAssertFalse(model.canFinish)
    }

    @MainActor
    func testLostCompletionResponseRequiresReadBeforeAnyRetry() async throws {
        let (model, api) = try await prepared(confirmed: 3)
        XCTAssertTrue(model.beginFinish())
        var completes = 0
        MockURLProtocol.requestHandler = { request in
            if request.url!.path.hasSuffix("/complete") { completes += 1; throw URLError(.timedOut) }
            return Self.response(request, data: try Self.fixture(confirmed: 3))
        }
        _ = await model.finish(candidates: [scan], client: api, online: true, userId: 7, companyId: 1)
        XCTAssertTrue(model.requiresRefresh)
        XCTAssertFalse(model.beginFinish())
        _ = await model.finish(candidates: [scan], client: api, online: true, userId: 7, companyId: 1)
        XCTAssertEqual(completes, 1)
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Device-ID"), Self.device)
            if request.url?.path.hasSuffix("/capabilities") == true {
                return Self.response(request, data: Self.capabilities)
            }
            return Self.response(request, data: try Self.fixture(confirmed: 3, packing: "packed", operational: "complete", sync: "pending", edit: false, complete: false))
        }
        await model.refresh(client: api, online: true)
        XCTAssertFalse(model.requiresRefresh)
        XCTAssertEqual(model.detail?.statusTitle, "Packed — tracking update pending")
    }

    @MainActor
    func testAppRestartRecoversPendingCompletionWithGETOnly() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = PackingRecoveryStore(defaults: defaults)
        store.save(PendingPackingCompletion(shipmentId: 42, eventId: UUID().uuidString, deviceId: Self.device, userId: 7, companyId: 1))
        let model = PackingViewModel(recoveryStore: store, deviceId: Self.device)
        var paths: [String] = []
        MockURLProtocol.requestHandler = { request in
            paths.append(request.url!.path)
            XCTAssertEqual(request.httpMethod, "GET")
            return Self.response(request, data: request.url!.path.hasSuffix("capabilities") ? Self.capabilities : try Self.fixture(confirmed: 3, packing: "packed", operational: "complete", sync: "synced", edit: false, complete: false))
        }
        await model.prepare(client: client(), online: true, userId: 7, companyId: 1)
        XCTAssertEqual(paths, ["/api/v1/shopify/packing/capabilities", "/api/v1/shopify/packing/42"])
        XCTAssertNil(store.read())
        XCTAssertEqual(model.detail?.statusTitle, "Shipped")
    }

    @MainActor
    func testOfflineAndServerOwnershipPreventWrites() async throws {
        let (model, api) = try await prepared()
        var calls = 0
        MockURLProtocol.requestHandler = { request in calls += 1; return Self.response(request, data: try Self.fixture(confirmed: 3, edit: false, complete: false)) }
        await model.setQuantity(lineId: 12, quantity: 3, client: api, online: false)
        XCTAssertEqual(calls, 0)
        await model.refresh(client: api, online: true)
        await model.setQuantity(lineId: 12, quantity: 3, client: api, online: true)
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(model.beginFinish())
    }

    @MainActor
    func testSpecificBusinessHoldIsShownWithoutClaimingCompletion() async throws {
        let (model, api) = try await prepared(confirmed: 3)
        XCTAssertTrue(model.beginFinish())
        MockURLProtocol.requestHandler = { request in
            Self.response(request, data: Data(#"{"detail":{"code":"order_cancelled","message":"This order was cancelled. Ask a supervisor."}}"#.utf8), status: 409)
        }
        _ = await model.finish(candidates: [scan], client: api, online: true, userId: 7, companyId: 1)
        XCTAssertTrue(model.errorMessage?.contains("order was cancelled") == true)
        XCTAssertFalse(model.detail?.isPacked == true)
    }

    func testCandidateGateAndDetectionTargetDoNotSelectArbitraryCode() {
        var gate = BarcodeCandidateGate()
        let second = BarcodeCandidate(barcode: "OTHER", symbology: "pdf417")
        XCTAssertNil(gate.accept([]))
        XCTAssertEqual(Set(gate.accept([scan, second, scan]) ?? []), Set([scan, second]))
        XCTAssertNil(gate.accept([second]))
        gate.reset()
        XCTAssertEqual(gate.accept([second]), [second])
        let target = ScannerGeometry.targetRect(in: CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertEqual(target.size, CGSize(width: 290, height: 170))
        XCTAssertEqual(target.midX, 195)
        XCTAssertEqual(target.midY, 422)
    }

    func testPendingMappingFailureShowsReasonAndPreventsConfirmation() throws {
        let reason = "SKU 276 does not have one valid physical product mapping."
        let detail = try JSONDecoder().decode(PackingDetail.self, from: Self.fixture(confirmed: 3, packing: "unstarted", review: " \n" + reason + "\n"))
        XCTAssertTrue(detail.needsReview)
        XCTAssertEqual(detail.statusTitle, "Supervisor review needed")
        XCTAssertEqual(detail.statusExplanation, reason)
        XCTAssertFalse(detail.canEdit)
        XCTAssertFalse(detail.canFinish)
        let cleared = try JSONDecoder().decode(PackingDetail.self, from: Self.fixture(confirmed: 3, review: " \n"))
        XCTAssertFalse(cleared.needsReview)
        XCTAssertTrue(cleared.canEdit)
        XCTAssertTrue(cleared.canFinish)
    }

    func testRepeatedScanningAcceptsEachLabelOnceAndResets() {
        var gate = BarcodeCandidateGate()
        for index in 0..<50 {
            let label = BarcodeCandidate(barcode: "TEST-\(index)", symbology: "code128")
            XCTAssertNil(gate.accept([]))
            XCTAssertEqual(gate.accept([label, label]), [label])
            XCTAssertNil(gate.accept([label]))
            gate.reset()
        }
    }

    func testReviewAndPartialBoxStatesNeverClaimOrderReady() throws {
        let partial = try JSONDecoder().decode(PackingDetail.self, from: Self.fixture(confirmed: 3, packing: "packed", edit: false, complete: false))
        XCTAssertEqual(partial.statusTitle, "Box packed")
        XCTAssertFalse(partial.canFinish)
        let review = try JSONDecoder().decode(PackingDetail.self, from: Self.fixture(confirmed: 3, packing: "packed", operational: "review", review: "Delivery needs a lot number."))
        XCTAssertEqual(review.statusTitle, "Packed — review needed")
        XCTAssertEqual(review.statusExplanation, "Delivery needs a lot number.")
        XCTAssertFalse(review.canFinish)
    }

    func testReconciledLocalCompletionStillAllowsRemainingPhysicalPacking() throws {
        let detail = try JSONDecoder().decode(PackingDetail.self, from: Self.fixture(confirmed: 3, operational: "complete", sync: "synced"))
        XCTAssertFalse(detail.needsReview)
        XCTAssertTrue(detail.canEdit)
        XCTAssertTrue(detail.canFinish)
        XCTAssertEqual(detail.statusTitle, "Pick this box")
        XCTAssertTrue(detail.statusExplanation.contains("Confirm every item"))
    }

    @MainActor
    func testReadOnlyPreviewResolvesLabelsAndNeverAllowsWrites() async throws {
        let api = client()
        var paths: [String] = []
        MockURLProtocol.requestHandler = { request in
            paths.append(request.url!.path)
            if request.url!.path.hasSuffix("capabilities") {
                return Self.response(request, data: Data(#"{"enabled":true,"business_enabled":false,"can_pack":true,"can_supervise":false,"requires_online":true,"workflow_version":"packing_v1"}"#.utf8))
            }
            return Self.response(request, data: try Self.fixture(confirmed: 3))
        }
        let model = PackingViewModel(recoveryStore: PackingRecoveryStore(defaults: UserDefaults(suiteName: UUID().uuidString)!), deviceId: Self.device)
        await model.prepare(client: api, online: true, userId: 7, companyId: 1)
        let accepted = await model.resolve(candidates: [scan], client: api, online: true)
        XCTAssertTrue(accepted)
        XCTAssertTrue(model.canUsePacking)
        XCTAssertFalse(model.canWritePacking)
        XCTAssertFalse(model.canEdit)
        XCTAssertFalse(model.beginFinish())
        await model.setQuantity(lineId: 12, quantity: 3, client: api, online: true)
        _ = await model.finish(candidates: [scan], client: api, online: true, userId: 7, companyId: 1)
        XCTAssertEqual(paths, ["/api/v1/shopify/packing/capabilities", "/api/v1/shopify/packing/resolve"])
    }
}

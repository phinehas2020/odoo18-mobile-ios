import XCTest
@testable import MobileOdoo

final class ManufacturingWorkflowTests: XCTestCase {
    func testCompletionPayloadIncludesReviewedQuantitiesAndLots() throws {
        let payload = ManufacturingCompletionPayload(quantity: 4, disposition: "backorder", finishedLotName: "BATCH-A", components: [.init(moveId: 12, quantity: 2.5, lotId: 19)])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertEqual(json["reviewed"] as? Bool, true)
        XCTAssertEqual(json["quantity"] as? Double, 4)
        XCTAssertEqual(json["disposition"] as? String, "backorder")
        XCTAssertEqual(json["finished_lot_name"] as? String, "BATCH-A")
        let row = try XCTUnwrap((json["components"] as? [[String: Any]])?.first)
        XCTAssertEqual(row["move_id"] as? Int, 12)
        XCTAssertEqual(row["lot_id"] as? Int, 19)
        XCTAssertEqual(row["quantity"] as? Double, 2.5)
    }

    func testManufacturingDetailDecodesQualityAndTracking() throws {
        let data = Data(#"{"id":1,"name":"MO/1","state":"progress","is_planned":true,"components":[{"id":3,"product_id":6,"product_name":"Flour","quantity":4,"tracking":"lot"}],"workorders":[],"quality_checks":[{"id":7,"name":"Weight check","state":"pending","control_type":"pass_fail","instructions":"Weigh the bag."}]}"#.utf8)
        let result = try DateCoding.decoder.decode(ManufacturingDetail.self, from: data)
        XCTAssertEqual(result.qualityChecks?.first?.instructions, "Weigh the bag.")
        XCTAssertEqual(result.components.first?.tracking, "lot")
        XCTAssertEqual(result.components.first?.productId, 6)
    }

    func testQuantityInputRejectsPartialParseAndInvalidNumbers() {
        XCTAssertEqual(warehouseQuantity("12"), 12)
        XCTAssertEqual(warehouseQuantity("0"), 0)
        for text in ["-1", "12 bags", "NaN", "Infinity", "", "1e9"] {
            XCTAssertNil(warehouseQuantity(text), text)
        }
    }
}

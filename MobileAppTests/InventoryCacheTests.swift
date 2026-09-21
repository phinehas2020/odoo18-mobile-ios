import XCTest
import GRDB
@testable import MobileOdoo

final class InventoryCacheTests: XCTestCase {
    func testTrackingAndDemandSurviveCacheRoundTrip() throws {
        let db = try DatabaseQueue()
        try DatabaseManager.migrator.migrate(db)
        let json = #"{"id":42,"name":"IN/42","state":"assigned","picking_type_code":"incoming","source_location":{"id":1,"name":"Vendor"},"dest_location":{"id":2,"name":"Stock"},"record_version":"version-2","lines":[{"id":3,"move_id":4,"product_id":5,"product_name":"Grain","qty_done":1,"qty_reserved":0,"qty_demanded":8,"lot_id":6,"lot_name":"LOT-A","tracking":"lot"}],"moves":[{"id":4,"product_id":5,"product_name":"Grain","qty_done":1,"qty_demanded":8,"tracking":"lot"}]}"#
        let detail = try DateCoding.decoder.decode(PickingDetail.self, from: Data(json.utf8))
        let store = InventoryStore(dbQueue: db)
        try store.save(detail: detail)
        let cached = try XCTUnwrap(store.fetch(pickingId: 42))
        XCTAssertEqual(cached.pickingTypeCode, "incoming")
        XCTAssertEqual(cached.lines.first?.moveId, 4)
        XCTAssertEqual(cached.lines.first?.lotName, "LOT-A")
        XCTAssertEqual(cached.moves?.first?.qtyDemanded, 8)
        XCTAssertEqual(cached.recordVersion, "version-2")
    }
}

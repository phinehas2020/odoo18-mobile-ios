import XCTest
@testable import MobileOdoo

final class DateCodingTests: XCTestCase {
    private struct Payload: Decodable { let scheduledDate: Date? }

    private func decode(_ value: String) throws -> Date? {
        let data = try JSONSerialization.data(withJSONObject: ["scheduledDate": value])
        return try DateCoding.decoder.decode(Payload.self, from: data).scheduledDate
    }

    func testOdooNaiveDatesAreUTCAndMatchExplicitOffsets() throws {
        let expected = try XCTUnwrap(decode("2026-09-21T15:30:45Z"))
        for value in ["2026-09-21T15:30:45", "2026-09-21 15:30:45",
                      "2026-09-21T15:30:45.000000", "2026-09-21 15:30:45.000000",
                      "2026-09-21T10:30:45-05:00", "2026-09-21T15:30:45+00:00"] {
            XCTAssertEqual(try XCTUnwrap(decode(value)).timeIntervalSince1970,
                           expected.timeIntervalSince1970, accuracy: 0.001, value)
        }
        let fractional = try XCTUnwrap(decode("2026-09-21T15:30:45.123456"))
        XCTAssertEqual(fractional.timeIntervalSince(expected), 0.123456, accuracy: 0.001)
    }

    func testRealPickingShapeDecodesNaiveScheduledDate() throws {
        let data = Data(#"[{"id":1,"name":"IN/001","scheduled_date":"2026-09-21T15:30:45","progress":{"done":0,"total":5}}]"#.utf8)
        let pickings = try DateCoding.decoder.decode([PickingListItem].self, from: data)
        XCTAssertNotNil(pickings.first?.scheduledDate)
    }

    func testNullMissingAndMalformedDates() throws {
        for json in [#"{"scheduledDate":null}"#, "{}"] {
            XCTAssertNil(try DateCoding.decoder.decode(Payload.self, from: Data(json.utf8)).scheduledDate)
        }
        for value in ["", "not a date", "2026-09-21T15:30:45garbage"] {
            XCTAssertThrowsError(try decode(value))
        }
    }
}

import Foundation

enum DateCoding {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            // Odoo datetime fields are UTC but its Python API can serialize them
            // without a timezone. Do not interpret those values in the phone's zone.
            let naivePattern = #"^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?$"#
            let isNaiveUTC = rawValue.range(of: naivePattern, options: .regularExpression) != nil
            let value = isNaiveUTC
                ? rawValue.replacingOccurrences(of: " ", with: "T") + "Z"
                : rawValue
            if let date = formatter.date(from: value) {
                return date
            }
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let date = fallback.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let value = formatter.string(from: date)
            try container.encode(value)
        }
        return encoder
    }()
}

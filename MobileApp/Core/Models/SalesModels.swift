import Foundation

struct CustomerItem: Codable, Identifiable {
    let id: Int
    let name: String
    let email: String?
    let phone: String?
}

struct SaleOrderItem: Codable, Identifiable {
    let id: Int
    let name: String
    let state: String
    let amountTotal: Double
    let currencyId: Int
    let partnerName: String?
    let dateOrder: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, state
        case amountTotal = "amount_total"
        case currencyId = "currency_id"
        case partnerName = "partner_name"
        case dateOrder = "date_order"
    }
}

struct SaleOrderLineItem: Codable, Identifiable {
    let id: Int
    let productName: String
    let quantity: Double
    let priceSubtotal: Double

    enum CodingKeys: String, CodingKey {
        case id
        case productName = "product_name"
        case quantity
        case priceSubtotal = "price_subtotal"
    }
}

struct SaleOrderDetail: Codable {
    let id: Int
    let name: String
    let state: String
    let amountTotal: Double
    let currencyId: Int
    let partnerName: String?
    let dateOrder: Date?
    let note: String?
    let lines: [SaleOrderLineItem]

    enum CodingKeys: String, CodingKey {
        case id, name, state, note, lines
        case amountTotal = "amount_total"
        case currencyId = "currency_id"
        case partnerName = "partner_name"
        case dateOrder = "date_order"
    }
}

struct SalesNoteRequest: Codable {
    let note: String
}

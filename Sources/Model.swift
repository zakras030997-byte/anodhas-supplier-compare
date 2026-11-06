import Foundation

enum TaxMode: String, Codable, CaseIterable {
    case unknown = "Не указан", included = "В цене", extra = "Сверху", exempt = "Без НДС"
}
enum ShippingMode: String, Codable, CaseIterable {
    case unknown = "Неизвестна", included = "Включена", extra = "Отдельно"
}
struct Product: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var sku = ""
    var specification = ""
    var unit = "шт."
    var quantity = ""
}
struct QuoteLine: Codable, Identifiable, Equatable {
    var id = UUID()
    var productID: UUID
    var price = ""
    var unit = ""
    var factor = ""
    var minimum = "0"
    var step = "0"
    var discount = "0"
    var tax: TaxMode = .unknown
    var taxRate = ""
    var stock = ""
    var checked = false
    var source = ""
}
struct Supplier: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var currency = "RUB"
    var exchangeRate = ""
    var rateDate = ""
    var rateSource = ""
    var deliveryDate = ""
    var validUntil = ""
    var advance = ""
    var paymentTerms = ""
    var shipping: ShippingMode = .unknown
    var shippingAmount = ""
    var freeShippingAbove = ""
    var fees = ""
    var source = "Ручной ввод"
    var lines: [QuoteLine] = []

    static func blank(products: [Product], currency: String) -> Supplier {
        var s = Supplier(); s.currency = currency
        s.lines = products.map { QuoteLine(productID: $0.id, unit: $0.unit) }
        return s
    }
}
struct Purchase: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "Новая закупка"
    var currency = "RUB"
    var precision = 2
    var deadline = ""
    var maxAdvance = "100"
    var products: [Product] = []
    var suppliers: [Supplier] = []
    var choices: [String: String] = [:]
    var decision = ""
    var isDemo = false
}
struct Workspace: Codable, Equatable {
    var version = 1
    var purchases: [Purchase] = []
    var selected: UUID?

    mutating func refreshExampleLabels() {
        for i in purchases.indices where purchases[i].isDemo {
            if purchases[i].name == "Демо · материалы и оборудование" { purchases[i].name = "Материалы и оборудование" }
            if purchases[i].decision == "Демонстрация: самые дешёвые строки дают 66 000 RUB с доставкой, весь заказ у Б — 65 000 RUB. Это условные данные." {
                purchases[i].decision = "Сравните целые предложения и ручной вариант. При выборе разных поставщиков учитывается доставка каждого заказа."
            }
            for s in purchases[i].suppliers.indices {
                if purchases[i].suppliers[s].source == "Условный пример ANODHAS AI" { purchases[i].suppliers[s].source = "Пример закупки" }
                for q in purchases[i].suppliers[s].lines.indices where purchases[i].suppliers[s].lines[q].source == "Демонстрационные данные" {
                    purchases[i].suppliers[s].lines[q].source = "Пример позиции"
                }
            }
        }
    }

    func validate() throws {
        guard version == 1, purchases.count <= 100,
              Set(purchases.map(\.id)).count == purchases.count else { throw DataError.invalid }
        for p in purchases { try ProjectFile.validate(p) }
    }
}
struct ProjectFile: Codable {
    var version = 1
    var purchase: Purchase
    static func validate(_ p: Purchase) throws {
        let products = Set(p.products.map(\.id))
        let suppliers = Set(p.suppliers.map(\.id))
        guard p.products.count <= 200, p.suppliers.count <= 50, (0...4).contains(p.precision),
              products.count == p.products.count, suppliers.count == p.suppliers.count,
              p.choices.count <= 200 else { throw DataError.invalid }
        for s in p.suppliers {
            guard s.lines.count <= 200, Set(s.lines.map(\.productID)).count == s.lines.count,
                  Set(s.lines.map(\.id)).count == s.lines.count,
                  s.lines.allSatisfy({ products.contains($0.productID) }) else { throw DataError.invalid }
        }
        for (item,supplier) in p.choices {
            guard let i = UUID(uuidString:item), products.contains(i),
                  let s = UUID(uuidString:supplier), suppliers.contains(s) else { throw DataError.invalid }
        }
    }
}
enum DataError: Error { case invalid, tooLarge }
struct LocalDisk {
    let url: URL
    func load() throws -> Workspace {
        guard FileManager.default.fileExists(atPath:url.path) else { return Workspace() }
        guard try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0 <= 16_000_000 else { throw DataError.tooLarge }
        let data = try JSONDecoder().decode(Workspace.self, from:Data(contentsOf:url))
        try data.validate()
        return data
    }
    func save(_ data: Workspace) throws {
        try data.validate()
        let encoded = try JSONEncoder().encode(data)
        guard encoded.count <= 16_000_000 else { throw DataError.tooLarge }
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(), withIntermediateDirectories:true, attributes:[.posixPermissions:0o700])
        try encoded.write(to:url, options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath:url.path)
    }
}

enum Value {
    static func clean(_ s: String) -> String { s.trimmingCharacters(in:.whitespacesAndNewlines) }
    static func key(_ s: String) -> String { clean(s).lowercased() }
    static func unit(_ s: String) -> String { key(s).trimmingCharacters(in:CharacterSet(charactersIn:".")) }
    static func currency(_ s: String) -> String { clean(s).uppercased() }
    static func validCurrency(_ s: String) -> Bool { currency(s).range(of:"^[A-Z]{3}$", options:.regularExpression) != nil }
    static func number(_ text: String, positive: Bool = false) -> Decimal? {
        let s = clean(text)
        let pattern = "^(?:[0-9]+|[0-9]{1,3}(?:[ \u{00a0}\u{202f}][0-9]{3})+)(?:[.,][0-9]{1,6})?$"
        guard s.range(of:pattern, options:.regularExpression) != nil else { return nil }
        let plain = s.replacingOccurrences(of:" ",with:"").replacingOccurrences(of:"\u{00a0}",with:"").replacingOccurrences(of:"\u{202f}",with:"").replacingOccurrences(of:",",with:".")
        guard let d = Decimal(string:plain, locale:Locale(identifier:"en_US_POSIX")), d <= 1_000_000_000, d >= 0, !positive || d > 0 else { return nil }
        return d
    }
    static func round(_ value: Decimal, _ precision: Int) -> Decimal {
        var input = value; var result = Decimal()
        NSDecimalRound(&result, &input, precision, .plain)
        return result
    }
    static func ceil(_ value: Decimal) -> Decimal {
        var input = value; var result = Decimal()
        NSDecimalRound(&result, &input, 0, .up)
        return result
    }
    static func display(_ d: Decimal) -> String { NSDecimalNumber(decimal:d).stringValue.replacingOccurrences(of:".",with:",") }
    static func money(_ d: Decimal?, currency: String, precision: Int) -> String {
        guard let d else { return "Не рассчитано" }
        let f = NumberFormatter(); f.locale = Locale(identifier:"ru_RU"); f.numberStyle = .decimal
        f.minimumFractionDigits = precision; f.maximumFractionDigits = precision
        return (f.string(from:NSDecimalNumber(decimal:d)) ?? display(d)) + " " + currency
    }
    static func safeAmount(_ d: Decimal) -> Bool {
        !d.isNaN && d >= 0 && d <= Decimal(1_000_000_000_000_000 as Int64)
    }
}
enum Dates {
    static func formatter() -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier:"en_US_POSIX"); f.calendar = Calendar(identifier:.gregorian)
        f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        return f
    }
    static func string(_ d: Date) -> String { formatter().string(from:d) }
    static func valid(_ s: String) -> Bool {
        guard let d = formatter().date(from:s) else { return false }
        return string(d) == s
    }
}

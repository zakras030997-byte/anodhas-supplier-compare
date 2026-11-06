import Foundation

struct LineResult: Identifiable {
    var id: UUID
    var title: String
    var purchasedUnits: Decimal?
    var purchasedBase: Decimal?
    var surplus: Decimal?
    var sourceTotal: Decimal?
    var total: Decimal?
    var baseUnitPrice: Decimal?
    var issues: [String] = []
}
struct SupplierResult: Identifiable {
    var id: UUID
    var name: String
    var delivery: String
    var advance: Decimal?
    var lines: [LineResult] = []
    var goods: Decimal?
    var shipping: Decimal?
    var fees: Decimal?
    var total: Decimal?
    var issues: [String] = []
    var eligible: Bool { total != nil && issues.isEmpty && lines.allSatisfy { $0.issues.isEmpty } }
    var reasons: [String] { issues + lines.flatMap { row in row.issues.map { row.title + ": " + $0 } } }
}
struct MixedResult {
    var groups: [SupplierResult] = []
    var issues: [String] = []
    var total: Decimal? {
        guard issues.isEmpty, !groups.isEmpty, groups.allSatisfy(\.eligible) else { return nil }
        let sum = groups.reduce(Decimal(0)) { $0 + ($1.total ?? 0) }
        return Value.safeAmount(sum) ? sum : nil
    }
}
enum Engine {
    static func line(_ item: Product, offer: QuoteLine?, rate: Decimal, precision: Int) -> LineResult {
        var r = LineResult(id:item.id, title:Value.clean(item.name).isEmpty ? "Без названия" : item.name)
        guard let offer else { r.issues.append("Нет предложения"); return r }
        if Value.clean(item.name).isEmpty { r.issues.append("Укажите название товара") }
        if Value.clean(item.unit).isEmpty { r.issues.append("Укажите единицу потребности") }
        if !offer.checked { r.issues.append("Подтвердите товар, объём и условия") }
        guard let need = Value.number(item.quantity, positive:true) else { r.issues.append("Проверьте необходимое количество"); return r }
        guard let price = Value.number(offer.price) else { r.issues.append("Укажите корректную цену"); return r }
        guard !Value.clean(offer.unit).isEmpty else { r.issues.append("Укажите единицу цены"); return r }
        let factor: Decimal
        if Value.unit(item.unit) == Value.unit(offer.unit) { factor = 1 }
        else {
            guard let d = Value.number(offer.factor, positive:true) else { r.issues.append("Нужен коэффициент единицы цены в \(item.unit)"); return r }
            factor = d
        }
        guard let minimum = Value.number(offer.minimum), let step = Value.number(offer.step),
              let discount = Value.number(offer.discount), discount <= 100 else { r.issues.append("Проверьте минимум, шаг и скидку 0–100%"); return r }
        var units = max(need / factor, minimum)
        if step > 0 { units = Value.ceil(units / step) * step }
        let purchased = max(need, units * factor)
        let discounted = units * price * (1 - discount / 100)
        var gross = discounted
        switch offer.tax {
        case .unknown: r.issues.append("Уточните, включён ли НДС"); return r
        case .extra:
            guard let tax = Value.number(offer.taxRate), tax <= 100 else { r.issues.append("Укажите ставку НДС сверху 0–100%"); return r }
            gross *= 1 + tax / 100
        case .included:
            if !offer.taxRate.isEmpty && (Value.number(offer.taxRate) == nil || Value.number(offer.taxRate)! > 100) {
                r.issues.append("Проверьте указанную ставку НДС"); return r
            }
        case .exempt: break
        }
        if !offer.stock.isEmpty {
            guard let stock = Value.number(offer.stock) else { r.issues.append("Проверьте подтверждённый остаток"); return r }
            if stock < purchased { r.issues.append("Не хватает подтверждённого остатка") }
        }
        let total = Value.round(gross * rate, precision)
        guard Value.safeAmount(total), Value.safeAmount(gross), Value.safeAmount(purchased) else {
            r.issues.append("Сумма или объём слишком велики"); return r
        }
        r.purchasedUnits = units; r.purchasedBase = purchased; r.surplus = purchased - need
        r.sourceTotal = gross; r.total = total
        r.baseUnitPrice = purchased > 0 ? total / purchased : nil
        return r
    }

    static func supplier(_ p: Purchase, _ s: Supplier, products: [Product]? = nil, asOf: String = Dates.string(Date())) -> SupplierResult {
        let items = products ?? p.products
        var r = SupplierResult(id:s.id, name:s.name, delivery:s.deliveryDate, advance:Value.number(s.advance))
        if items.isEmpty { r.issues.append("Добавьте товары в закупку") }
        if Value.clean(s.name).isEmpty { r.issues.append("Укажите поставщика") }
        if !Value.validCurrency(p.currency) || !Value.validCurrency(s.currency) { r.issues.append("Валюты: три латинские буквы, например RUB") }
        if !Dates.valid(asOf) { r.issues.append("Неверная дата сравнения") }
        if !Dates.valid(s.validUntil) { r.issues.append("Укажите срок действия КП: ГГГГ-ММ-ДД") }
        else if s.validUntil < asOf { r.issues.append("Срок действия КП истёк") }
        if !Dates.valid(s.deliveryDate) { r.issues.append("Укажите дату получения: ГГГГ-ММ-ДД") }
        else if s.deliveryDate < asOf { r.issues.append("Дата поставки уже прошла") }
        if !p.deadline.isEmpty {
            if !Dates.valid(p.deadline) { r.issues.append("Проверьте крайнюю дату закупки") }
            else if Dates.valid(s.deliveryDate) && s.deliveryDate > p.deadline { r.issues.append("Поставка позже обязательного срока") }
        }
        if let limit = Value.number(p.maxAdvance), limit <= 100, let advance = r.advance, advance <= 100 {
            if advance > limit { r.issues.append("Предоплата выше допустимой") }
        } else { r.issues.append("Укажите предоплату и её предел: 0–100%") }
        var rate: Decimal = 1
        var comparable = Value.validCurrency(p.currency) && Value.validCurrency(s.currency)
        if Value.currency(p.currency) != Value.currency(s.currency) {
            if let value = Value.number(s.exchangeRate, positive:true) { rate = value }
            else { r.issues.append("Укажите курс: базовой валюты за 1 \(s.currency)"); comparable = false }
            if !Dates.valid(s.rateDate) || Value.clean(s.rateSource).isEmpty {
                r.issues.append("Нужны дата и источник курса"); comparable = false
            }
        }
        r.lines = items.map { item in line(item, offer:s.lines.first { $0.productID == item.id }, rate:rate, precision:p.precision) }
        if !comparable {
            for i in r.lines.indices {
                r.lines[i].total = nil; r.lines[i].baseUnitPrice = nil
                r.lines[i].issues.append("Нет подтверждённой общей валюты")
            }
        }
        guard comparable, r.lines.allSatisfy({ $0.total != nil }) else { return r }
        r.goods = r.lines.reduce(Decimal(0)) { $0 + ($1.total ?? 0) }
        let sourceGoods = r.lines.reduce(Decimal(0)) { $0 + ($1.sourceTotal ?? 0) }
        var shipping: Decimal?
        switch s.shipping {
        case .unknown: r.issues.append("Стоимость доставки неизвестна")
        case .included: shipping = 0
        case .extra:
            var free = false
            var thresholdValid = true
            if !s.freeShippingAbove.isEmpty {
                if let threshold = Value.number(s.freeShippingAbove) {
                    free = sourceGoods >= threshold
                } else { r.issues.append("Проверьте порог бесплатной доставки"); thresholdValid = false }
            }
            if thresholdValid {
                if free { shipping = 0 }
                else if let amount = Value.number(s.shippingAmount) { shipping = amount }
                else { r.issues.append("Укажите окончательную сумму доставки") }
            }
        }
        if let shipping { r.shipping = Value.round(shipping * rate, p.precision) }
        if let fees = Value.number(s.fees) { r.fees = Value.round(fees * rate, p.precision) }
        else { r.issues.append("Укажите прочие сборы, 0 если их нет") }
        if let goods = r.goods, let freight = r.shipping, let fees = r.fees {
            let sum = goods + freight + fees
            if Value.safeAmount(sum) { r.total = sum }
            else { r.issues.append("Итоговая сумма слишком велика") }
        }
        return r
    }
    static func all(_ p: Purchase, asOf: String = Dates.string(Date())) -> [SupplierResult] {
        p.suppliers.map { supplier(p,$0,asOf:asOf) }
    }
    static func mixed(_ p: Purchase, asOf: String = Dates.string(Date())) -> MixedResult {
        var r = MixedResult()
        if p.products.isEmpty { r.issues.append("Добавьте товары"); return r }
        var groups: [UUID:[Product]] = [:]
        for item in p.products {
            guard let raw = p.choices[item.id.uuidString], let id = UUID(uuidString:raw), p.suppliers.contains(where:{$0.id == id}) else {
                r.issues.append("Выберите поставщика: \(item.name)"); continue
            }
            groups[id,default:[]].append(item)
        }
        r.groups = p.suppliers.compactMap { s in
            guard let items = groups[s.id] else { return nil }
            return supplier(p,s,products:items,asOf:asOf)
        }
        for group in r.groups where !group.eligible { r.issues += group.reasons.map { group.name + ": " + $0 } }
        return r
    }
    static func cheapest(_ rows: [SupplierResult]) -> [SupplierResult] {
        let valid = rows.filter(\.eligible)
        guard let minimum = valid.compactMap(\.total).min() else { return [] }
        return valid.filter { $0.total == minimum }
    }
}

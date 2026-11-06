import Foundation

enum ImportError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
struct CSVTable {
    var headers: [String]
    var rows: [[String]]
    var delimiter: Character
}
enum Delimited {
    static func delimiter(_ text: String) -> Character {
        let chars = Array(text); var quoted = false; var i = 0
        var counts: [Character:Int] = [";":0, ",":0, "\t":0]
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i+1 < chars.count && chars[i+1] == "\"" { i += 2; continue }
                quoted.toggle()
            } else if !quoted {
                if c == "\n" || c == "\r" { break }
                if counts[c] != nil { counts[c,default:0] += 1 }
            }
            i += 1
        }
        return [";","\t",","].max { counts[$0,default:0] < counts[$1,default:0] } ?? ";"
    }
    static func parse(_ input: String, separator: Character? = nil) throws -> CSVTable {
        guard input.utf8.count <= 1_048_576 else { throw ImportError.message("Таблица больше 1 МиБ. Разделите её на части.") }
        var text = input.replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n")
        if text.first == "\u{feff}" { text.removeFirst() }
        let sep = separator ?? delimiter(text)
        let chars = Array(text); var rows: [[String]] = []; var row: [String] = []
        var field = ""; var quoted = false; var closed = false; var i = 0
        func finishField() throws {
            row.append(field); field = ""; closed = false
            if row.count > 100 { throw ImportError.message("В таблице больше 100 колонок.") }
        }
        func finishRow() throws {
            try finishField(); rows.append(row); row = []
            if rows.count > 201 { throw ImportError.message("За один импорт доступно до 200 записей.") }
        }
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i+1 < chars.count && chars[i+1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(c) }
            } else if c == sep { try finishField() }
            else if c == "\n" { try finishRow() }
            else if c == "\"" {
                guard field.isEmpty && !closed else { throw ImportError.message("Кавычка внутри неэкранированного поля.") }
                quoted = true
            } else if closed {
                guard c == " " else { throw ImportError.message("После закрывающей кавычки нужен разделитель.") }
            } else { field.append(c) }
            i += 1
        }
        guard !quoted else { throw ImportError.message("Не закрыта кавычка в таблице.") }
        if !field.isEmpty || !row.isEmpty || closed { try finishRow() }
        guard let header = rows.first, header.count >= 2, rows.count >= 2 else {
            throw ImportError.message("Нужна строка заголовков и хотя бы одна запись с разделителями.")
        }
        return CSVTable(headers:header, rows:Array(rows.dropFirst()), delimiter:sep)
    }
}
struct ColumnMap {
    var product = 0
    var price = 1
    var unit = 2
    static func guess(_ headers: [String]) -> ColumnMap {
        func find(_ words: [String], _ fallback: Int) -> Int {
            headers.firstIndex { h in words.contains { Value.key(h).contains($0) } } ?? min(fallback,headers.count-1)
        }
        return ColumnMap(product:find(["товар","артикул","product","sku","item","наименование"],0),
                         price:find(["цена","price","rate","стоимость"],1),
                         unit:find(["единиц","ед.","unit","uom"],2))
    }
}
struct ImportRow: Identifiable {
    var id: Int
    var productID: String
    var sourceName: String
    var price: String
    var unit: String
    var issues: [String] = []
}
enum ImportPlan {
    static func rows(_ table: CSVTable, map: ColumnMap, purchase: Purchase, overrides: [Int:String] = [:]) -> [ImportRow] {
        var rows: [ImportRow] = []
        for (i,fields) in table.rows.enumerated() where fields.contains(where:{!Value.clean($0).isEmpty}) {
            func field(_ column: Int) -> String { fields.indices.contains(column) ? Value.clean(fields[column]) : "" }
            let name = field(map.product)
            let matches = purchase.products.filter {
                (!Value.clean($0.sku).isEmpty && Value.key($0.sku) == Value.key(name)) || Value.key($0.name) == Value.key(name)
            }
            let chosen = overrides[i+2] ?? (matches.count == 1 ? matches[0].id.uuidString : "")
            var row = ImportRow(id:i+2, productID:chosen, sourceName:name, price:field(map.price), unit:field(map.unit))
            if Set([map.product,map.price,map.unit]).count != 3 { row.issues.append("Выберите три разные колонки") }
            if !purchase.products.contains(where:{$0.id.uuidString == chosen}) { row.issues.append("Выберите товар закупки") }
            if Value.number(row.price) == nil { row.issues.append("Неверная цена") }
            if row.unit.isEmpty { row.issues.append("Нет единицы цены") }
            rows.append(row)
        }
        let counts = Dictionary(grouping:rows.filter{!$0.productID.isEmpty},by:\.productID).mapValues(\.count)
        for i in rows.indices where counts[rows[i].productID,default:0] > 1 { rows[i].issues.append("Повтор одного товара в импорте") }
        return rows
    }
    static func apply(_ rows: [ImportRow], to supplier: Supplier, source: String) throws -> Supplier {
        guard !rows.isEmpty, rows.allSatisfy({$0.issues.isEmpty}),
              Set(rows.map(\.productID)).count == rows.count else { throw ImportError.message("Исправьте отмеченные записи; импорт не применён.") }
        var result = supplier
        for row in rows {
            guard let product = UUID(uuidString:row.productID) else { throw ImportError.message("Неверная связь товара.") }
            var line = QuoteLine(productID:product, price:row.price, unit:row.unit)
            line.source = source + " · запись " + String(row.id)
            if let index = result.lines.firstIndex(where:{$0.productID == product}) {
                line.id = result.lines[index].id; result.lines[index] = line
            } else { result.lines.append(line) }
        }
        return result
    }
}
enum Report {
    static func cell(_ s: String) -> String {
        let prefixIgnored = CharacterSet.whitespacesAndNewlines.union(.controlCharacters).union(CharacterSet(charactersIn:"\u{feff}"))
        let unsafe = s.trimmingCharacters(in:prefixIgnored).first.map { "=+-@".contains($0) } ?? false
        return "\"" + (unsafe ? "'" : "") + s.replacingOccurrences(of:"\"",with:"\"\"") + "\""
    }
    static func data(_ rows: [[String]]) -> Data {
        Data(("\u{feff}" + rows.map{$0.map(cell).joined(separator:";")}.joined(separator:"\r\n") + "\r\n").utf8)
    }
    static func raw(_ value: Decimal?) -> String { value.map(Value.display) ?? "" }
    static func csv(_ p: Purchase, asOf: String = Dates.string(Date())) -> Data {
        var rows = [["Закупка","Дата сравнения","Поставщик","Валюта итога","Товары","Доставка","Прочие сборы","Всего","Получение","Предоплата %","Статус","Причины","Условия оплаты","Источник КП"]]
        let evaluated = Engine.all(p,asOf:asOf)
        for r in evaluated {
            let s = p.suppliers.first{$0.id == r.id}!
            rows.append([p.name,asOf,r.name,Value.currency(p.currency),raw(r.goods),raw(r.shipping),raw(r.fees),raw(r.total),r.delivery,raw(r.advance),r.eligible ? "Подходит" : "Нужна проверка",r.reasons.joined(separator:"; "),s.paymentTerms,s.source])
        }
        let mix = Engine.mixed(p,asOf:asOf)
        if !p.choices.isEmpty {
            rows.append([p.name,asOf,"Ручной вариант",Value.currency(p.currency),"","","",raw(mix.total),"","",mix.total == nil ? "Нужна проверка" : "Подходит",mix.issues.joined(separator:"; "),"","Выбор позиций пользователем"])
        }
        return data(rows)
    }
    static func linesCSV(_ p: Purchase, asOf: String = Dates.string(Date())) -> Data {
        var rows = [["Поставщик","Товар","Артикул","Характеристики","Потребность","Единица потребности","Закупаемый объём","Излишек","Сумма строки","Валюта итога","Статус строки","Причины","Источник строки"]]
        for s in p.suppliers {
            let r = Engine.supplier(p,s,asOf:asOf)
            for line in r.lines {
                let item = p.products.first{$0.id == line.id}!
                let source = s.lines.first{$0.productID == line.id}?.source ?? ""
                rows.append([s.name,item.name,item.sku,item.specification,item.quantity,item.unit,raw(line.purchasedBase),raw(line.surplus),raw(line.total),Value.currency(p.currency),line.issues.isEmpty ? "Проверена" : "Нужна проверка",line.issues.joined(separator:"; "),source])
            }
        }
        return data(rows)
    }
    static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;").replacingOccurrences(of:"'",with:"&#39;")
    }
    static func html(_ p: Purchase, asOf: String = Dates.string(Date())) -> Data {
        func e(_ s: String) -> String { htmlEscape(s) }
        func money(_ d: Decimal?) -> String { e(Value.money(d,currency:Value.currency(p.currency),precision:p.precision)) }
        let result = Engine.all(p,asOf:asOf)
        let leaders = Engine.cheapest(result).map(\.name).joined(separator:", ")
        var html = """
        <!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(e(p.name))</title><style>
        body{font:15px -apple-system,Arial,sans-serif;color:#3D302A;background:#FFFCF7;max-width:1200px;margin:40px auto;padding:0 24px;line-height:1.5}
        h1{font-size:32px}h2{font-size:22px;margin-top:32px}small{color:#746052}table{width:100%;border-collapse:collapse;margin:16px 0}th{background:#F5E9DC;text-align:left}
        th,td{padding:10px;border-bottom:1px solid #EED8C6;vertical-align:top;overflow-wrap:anywhere}header{border-bottom:3px solid #AD6248;padding-bottom:20px}.bad{color:#984b26}aside{padding:16px;background:#F5E9DC;border-radius:10px}
        @media print{body{margin:0;padding:0;background:white}table{font-size:11px}thead{display:table-header-group}tr{break-inside:avoid}}
        </style><header><small>ANODHAS AI · Сравнение поставщиков</small><h1>\(e(p.name))</h1>
        <p>Дата сравнения: \(e(asOf)). Базовая валюта: \(e(Value.currency(p.currency))). Округление: \(p.precision) знака по строкам.</p>
        <p>Крайний срок: \(e(p.deadline.isEmpty ? "не задан" : p.deadline)). Предоплата не выше \(e(p.maxAdvance))%.</p></header>
        <h2>01. Потребность</h2><table><thead><tr><th>Товар / артикул</th><th>Характеристики</th><th>Количество</th></tr></thead><tbody>
        """
        for item in p.products { html += "<tr><td>\(e(item.name))<br><small>\(e(item.sku))</small></td><td>\(e(item.specification))</td><td>\(e(item.quantity)) \(e(item.unit))</td></tr>" }
        html += "</tbody></table><h2>02. Предложения целиком</h2><aside>Минимальная стоимость среди подходящих: \(e(leaders.isEmpty ? "нет подходящих предложений" : leaders))</aside>"
        html += "<table><thead><tr><th>Поставщик</th><th>Товары</th><th>Доставка</th><th>Сборы</th><th>Всего</th><th>Срок / оплата</th><th>Проверка</th></tr></thead><tbody>"
        for row in result {
            let supplier = p.suppliers.first{$0.id == row.id}!
            html += "<tr><td>\(e(row.name))<br><small>\(e(supplier.source))</small></td><td>\(money(row.goods))</td><td>\(money(row.shipping))</td><td>\(money(row.fees))</td><td>\(money(row.total))</td><td>\(e(row.delivery))<br>Предоплата \(e(supplier.advance))%<br>\(e(supplier.paymentTerms))</td><td>\(e(row.eligible ? "Подходит" : row.reasons.joined(separator:"; ")))</td></tr>"
        }
        html += "</tbody></table><h2>03. Позиции предложений</h2>"
        for s in p.suppliers {
            let result = Engine.supplier(p,s,asOf:asOf)
            html += "<h3>\(e(s.name))</h3><table><tr><th>Товар</th><th>Закупаем</th><th>Излишек</th><th>Сумма строки</th><th>Проверка и источник</th></tr>"
            for row in result.lines {
                let item = p.products.first{$0.id == row.id}!
                let source = s.lines.first{$0.productID == row.id}?.source ?? ""
                html += "<tr><td>\(e(item.name))</td><td>\(e(raw(row.purchasedBase))) \(e(item.unit))</td><td>\(e(raw(row.surplus))) \(e(item.unit))</td><td>\(money(row.total))</td><td>\(e(row.issues.joined(separator:"; ")))<br><small>\(e(source))</small></td></tr>"
            }
            html += "</table>"
        }
        let mix = Engine.mixed(p,asOf:asOf)
        html += "<h2>04. Ручной вариант</h2><p>Итог: \(money(mix.total))</p>"
        for item in p.products {
            let supplier = p.suppliers.first{$0.id.uuidString == p.choices[item.id.uuidString]}?.name ?? "не выбран"
            html += "<p>\(e(item.name)): \(e(supplier))</p>"
        }
        for group in mix.groups { html += "<p>\(e(group.name)): \(money(group.total)), доставка \(money(group.shipping)), сборы \(money(group.fees))</p>" }
        html += "<p class=\"bad\">\(e(mix.issues.joined(separator:"; ")))</p><p>\(e(p.decision))</p><hr><small>Расчёт по введённым условиям. Неподходящие предложения не являются рекомендацией. Возмещение налогов и неуказанные расходы не вычисляются. Исходные КП следует проверить перед закупкой.</small></html>"
        return Data(html.utf8)
    }
}

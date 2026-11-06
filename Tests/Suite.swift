import Foundation
import Darwin

@main struct Suite {
    static func main() throws {
        var passed: [String] = []
        func test(_ name: String, _ condition: Bool) {
            guard condition else {
                FileHandle.standardError.write(Data(("FAILED: "+name+"\n").utf8)); exit(1)
            }
            passed.append(name)
        }
        func throwsTest(_ name: String, _ body: () throws -> Void) {
            do { try body(); test(name,false) } catch { test(name,true) }
        }
        let date = Dates.formatter().date(from:"2026-11-06")!
        let asOf = "2026-11-06"
        let demo = Demo.purchase(today:date)
        let a = demo.suppliers[0]; let b = demo.suppliers[1]
        func evaluate(_ p: Purchase, _ s: Supplier) -> SupplierResult { Engine.supplier(p,s,asOf:asOf) }
        let rows = Engine.all(demo,asOf:asOf)
        test("demo has five suppliers",rows.count == 5)
        test("two compliant offers",rows.filter(\.eligible).count == 2)
        test("A full basket 67000",rows[0].total == 67000)
        test("B full basket 65000",rows[1].total == 65000)
        test("B is least total cost",Engine.cheapest(rows).map(\.id) == [b.id])
        test("late quotation not recommended",!rows[2].eligible && rows[2].reasons.contains{$0.contains("позже")})
        test("unknown shipping not zero",rows[3].total == nil && !rows[3].eligible)
        test("excess advance not recommended",!rows[4].eligible && rows[4].reasons.contains{$0.contains("Предоплата")})
        test("split cheapest lines cost 66000",Engine.mixed(demo,asOf:asOf).total == 66000)
        var same = demo; same.choices = Dictionary(uniqueKeysWithValues:demo.products.map{($0.id.uuidString,b.id.uuidString)})
        test("single supplier selected twice charged once",Engine.mixed(same,asOf:asOf).total == 65000)
        var extraFee = a; extraFee.fees = "500"
        test("common fees charged once",evaluate(demo,extraFee).total == 67500)
        var free = a; free.freeShippingAbove = "60000"
        test("shipping threshold uses actual basket",evaluate(demo,free).total == 64000)
        var split = demo; split.suppliers[0] = free
        test("split recalculates free freight threshold",Engine.mixed(split,asOf:asOf).total == 66000)
        free.shippingAmount = ""
        test("explicit free threshold need not know irrelevant paid tariff",evaluate(demo,free).eligible && evaluate(demo,free).total == 64000)
        free.freeShippingAbove = "70000"
        test("missing tariff below threshold blocks total",evaluate(demo,free).total == nil)
        var missingFee = a; missingFee.fees = ""
        test("unknown fee not zero",evaluate(demo,missingFee).total == nil)
        var missingLine = a; missingLine.lines.removeFirst()
        test("missing product not zero",evaluate(demo,missingLine).total == nil)
        var unchecked = a; unchecked.lines[0].checked = false
        test("unchecked quote may show arithmetic but cannot lead",evaluate(demo,unchecked).total == 67000 && !evaluate(demo,unchecked).eligible)
        var empty = Purchase(); empty.suppliers = [a]
        test("empty basket has no eligible offer",!evaluate(empty,a).eligible)
        var ties = demo; var twin = b; twin.id = UUID(); twin.name = "Равный вариант"
        ties.suppliers = [b,twin]
        test("equal totals retain multiple leaders",Engine.cheapest(Engine.all(ties,asOf:asOf)).count == 2)

        let item = Product(name:"Материал",sku:"M-01",unit:"кг",quantity:"10")
        var offer = QuoteLine(productID:item.id,price:"100",unit:"мешок",factor:"3",minimum:"0",step:"1",tax:.exempt,checked:true)
        func line(_ i: Product, _ o: QuoteLine) -> LineResult { Engine.line(i,offer:o,rate:1,precision:2) }
        test("package rounds up",line(item,offer).purchasedUnits == 4)
        test("package actual quantity",line(item,offer).purchasedBase == 12)
        test("package surplus visible",line(item,offer).surplus == 2)
        test("package cost 400",line(item,offer).total == 400)
        offer.minimum = "5"
        test("MOQ applied in priced units",line(item,offer).purchasedBase == 15)
        offer.step = "2"
        test("step applied after MOQ",line(item,offer).purchasedBase == 18)
        offer.stock = "17"
        test("stock covers actual surplus too",line(item,offer).issues.contains{$0.contains("остатка")})
        offer.stock = ""; offer.factor = ""
        test("different unit needs explicit conversion",line(item,offer).total == nil)
        offer.unit = "кг"; offer.minimum = "0"; offer.step = "0"; offer.price = "100"; offer.discount = "10"; offer.tax = .extra; offer.taxRate = "20"
        test("discount then explicit tax",line(item,offer).total == 1080)
        offer.tax = .included
        test("included tax not added again",line(item,offer).total == 900)
        offer.taxRate = ""
        test("included unspecified rate retains payable amount",line(item,offer).total == 900)
        offer.tax = .unknown
        test("unknown tax blocks amount",line(item,offer).total == nil)
        offer.tax = .extra
        test("extra tax needs rate",line(item,offer).total == nil)
        offer.taxRate = "101"
        test("invalid tax rejected",line(item,offer).total == nil)
        offer.tax = .exempt; offer.price = "0"; offer.discount = "0"
        test("explicit free item allowed",line(item,offer).total == 0)
        var fraction = item; fraction.quantity = "2,5"; offer.price = "0,1"
        test("decimal arithmetic exact",line(fraction,offer).total == Decimal(string:"0.25"))
        offer.price = "100"; offer.discount = "100"
        test("full discount explicit zero",line(item,offer).total == 0)
        offer.discount = "101"
        test("discount over 100 rejected",line(item,offer).total == nil)
        var badQty = item; badQty.quantity = "0"
        test("zero demand rejected",line(badQty,offer).total == nil)
        test("correct grouped number accepted",Value.number("1 234,56") == Decimal(string:"1234.56"))
        test("invalid grouping rejected",Value.number("12 34") == nil)
        test("mixed decimal separators rejected",Value.number("1,234.56") == nil)
        for value in ["-1","1e3","NaN","inf","0.1234567","1000000001",""] {
            test("invalid number rejected "+value,Value.number(value) == nil)
        }
        test("half-up rounding",Value.round(Decimal(string:"1.005")!,2) == Decimal(string:"1.01"))
        test("currency needs ISO shaped code",Value.validCurrency("rub") && !Value.validCurrency("руб"))

        var fx = Supplier.blank(products:[item],currency:"USD")
        fx.name = "Валютное КП"; fx.exchangeRate = "100"; fx.rateDate = asOf; fx.rateSource = "Условный курс"
        fx.deliveryDate = "2026-11-07"; fx.validUntil = "2026-11-30"; fx.advance = "0"
        fx.shipping = .extra; fx.shippingAmount = "3"; fx.fees = "1"
        fx.lines[0] = QuoteLine(productID:item.id,price:"2",unit:"кг",tax:.exempt,checked:true)
        var fxPurchase = Purchase(products:[item],suppliers:[fx])
        test("FX applies to goods freight and fees",evaluate(fxPurchase,fx).total == 2400)
        fx.exchangeRate = ""
        let missingRate = evaluate(fxPurchase,fx)
        test("missing FX prevents misleading base line total",missingRate.total == nil && missingRate.lines[0].total == nil)
        fx.exchangeRate = "100"; fx.rateSource = ""
        test("rate provenance mandatory",evaluate(fxPurchase,fx).total == nil)
        fx.rateSource = "Документ"; fx.validUntil = "2026-11-05"
        test("expired quotation excluded",!evaluate(fxPurchase,fx).eligible)
        fx.validUntil = asOf
        test("valid-through date inclusive",evaluate(fxPurchase,fx).eligible)
        fxPurchase.deadline = "2026-11-06"
        test("deadline enforced",!evaluate(fxPurchase,fx).eligible)
        fxPurchase.deadline = ""; fx.deliveryDate = "2026-11-05"
        test("past delivery needs revision",!evaluate(fxPurchase,fx).eligible)
        test("impossible date rejected",!Dates.valid("2026-02-30"))
        test("date input format strict",!Dates.valid("06.11.2026"))
        var large = a; large.lines[0].price = "1000000000"; var big = demo; big.products[0].quantity = "1000000000"
        test("unrealistic overflow not presented as valid amount",evaluate(big,large).total == nil)

        let csv = "\u{feff}Артикул;Цена;Единица\r\nCAB-01;520;м\r\nLGT-01;650;шт.\r\n"
        let table = try Delimited.parse(csv)
        test("UTF8 BOM and semicolon headers",table.headers[0] == "Артикул" && table.rows.count == 2)
        let planned = ImportPlan.rows(table,map:ColumnMap.guess(table.headers),purchase:demo)
        test("SKU maps to internal product IDs",planned[0].productID == demo.products[0].id.uuidString && planned.allSatisfy{$0.issues.isEmpty})
        let imported = try ImportPlan.apply(planned,to:b,source:"пример.csv")
        test("import resets operator review",imported.lines.allSatisfy{!$0.checked && $0.tax == .unknown})
        test("import records source",imported.lines[0].source == "пример.csv · запись 2")
        test("supplier conditions preserved",imported.shipping == b.shipping && imported.deliveryDate == b.deliveryDate)
        let tsv = try Delimited.parse("Товар\tЦена\tЕдиница\nCAB-01\t1,5\tм")
        test("Excel TSV auto detected",tsv.delimiter == "\t" && tsv.rows[0][1] == "1,5")
        let quoted = try Delimited.parse("Товар,Цена,Единица\n\"Товар, \"\"особый\"\"\nстрока\",10,шт.")
        test("quoted delimiters newline and escaped quote",quoted.rows[0][0] == "Товар, \"особый\"\nстрока")
        throwsTest("unclosed quoted input blocked"){_ = try Delimited.parse("A;B\n\"broken;1")}
        throwsTest("characters after closing quote blocked"){_ = try Delimited.parse("A;B\n\"x\"z;1")}
        throwsTest("too large import blocked"){_ = try Delimited.parse(String(repeating:"x",count:1_048_577))}
        throwsTest("over 200 input records blocked"){_ = try Delimited.parse("A;B\n"+String(repeating:"a;1\n",count:201))}
        let duplicateTable = try Delimited.parse("Товар;Цена;Единица\nCAB-01;1;м\nCAB-01;2;м")
        let duplicates = ImportPlan.rows(duplicateTable,map:ColumnMap(),purchase:demo)
        test("duplicate target rows flagged",duplicates.allSatisfy{!$0.issues.isEmpty})
        throwsTest("duplicates not partially imported"){_ = try ImportPlan.apply(duplicates,to:b,source:"dup.csv")}
        let sameColumns = ImportPlan.rows(table,map:ColumnMap(product:0,price:1,unit:1),purchase:demo)
        test("column mapping must be distinct",sameColumns.contains{!$0.issues.isEmpty})
        var ambiguous = demo; ambiguous.products[1].name = ambiguous.products[0].name
        let ambiguousTable = try Delimited.parse("Товар;Цена;Единица\nКабель монтажный;1;м")
        let ambiguousRows = ImportPlan.rows(ambiguousTable,map:ColumnMap(),purchase:ambiguous)
        test("ambiguous product not guessed",ambiguousRows[0].productID.isEmpty)
        let corrected = ImportPlan.rows(ambiguousTable,map:ColumnMap(),purchase:ambiguous,overrides:[2:ambiguous.products[0].id.uuidString])
        test("manual matching resolves ambiguity",corrected[0].issues.isEmpty)
        test("CSV formula escaped",Report.cell("=1+1") == "\"'=1+1\"")
        test("CSV whitespace formula escaped",Report.cell("  @SUM(A1)").hasPrefix("\"'"))
        test("CSV leading control formula escaped",Report.cell("\u{0000}=1+1").hasPrefix("\"'"))
        test("CSV quotes escaped",Report.cell("a\"b") == "\"a\"\"b\"")
        let summary = String(data:Report.csv(demo,asOf:asOf),encoding:.utf8)!
        test("CSV has totals and manual comparison",summary.contains("65000") && summary.contains("66000") && summary.contains("Ручной вариант"))
        test("CSV BOM",Report.csv(demo).starts(with:[239,187,191]))
        let details = String(data:Report.linesCSV(demo,asOf:asOf),encoding:.utf8)!
        test("details include source and specifications",details.contains("Медный") && details.contains("Пример позиции"))
        var htmlAttack = demo; htmlAttack.name = "<script>alert('x')</script>"; htmlAttack.products[0].specification = "<img onerror=x>"
        let html = String(data:Report.html(htmlAttack,asOf:asOf),encoding:.utf8)!
        test("HTML user content escaped",html.contains("&lt;script&gt;") && !html.contains("<script>") && !html.contains("<img"))
        test("HTML includes all suppliers and manual result",html.contains("Б · Комплект") && html.contains("66"))

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("supplier-compare-check-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let disk = LocalDisk(url:folder.appendingPathComponent("state.json"))
        let snapshot = Workspace(purchases:[demo],selected:demo.id)
        var legacy = snapshot
        legacy.purchases[0].name = "Демо · материалы и оборудование"
        legacy.purchases[0].suppliers[0].lines[0].source = "Демонстрационные данные"
        legacy.refreshExampleLabels()
        test("old example title updated",legacy.purchases[0].name == "Материалы и оборудование")
        test("old example source updated",legacy.purchases[0].suppliers[0].lines[0].source == "Пример позиции")
        test("example update preserves selections and IDs",legacy.purchases[0].choices == demo.choices && legacy.purchases[0].id == demo.id)
        legacy.purchases[0].name = "Моя закупка"; legacy.purchases[0].suppliers[0].lines[0].source = "Мой документ"
        legacy.refreshExampleLabels()
        test("owner edits preserved during label update",legacy.purchases[0].name == "Моя закупка" && legacy.purchases[0].suppliers[0].lines[0].source == "Мой документ")
        try disk.save(snapshot); let restored = try disk.load()
        test("atomic state preserves complete project and selections",restored == snapshot)
        test("restart recalculates same total",Engine.mixed(restored.purchases[0],asOf:asOf).total == 66000)
        let perms = try FileManager.default.attributesOfItem(atPath:disk.url.path)[.posixPermissions] as? NSNumber
        test("private local file permissions",perms?.intValue == 0o600)
        var invalid = snapshot; invalid.version = 99
        throwsTest("unknown state schema rejected"){try invalid.validate()}
        invalid = snapshot; invalid.purchases.append(demo)
        throwsTest("duplicate project IDs rejected"){try invalid.validate()}
        var duplicateProduct = demo; duplicateProduct.products.append(demo.products[0])
        throwsTest("duplicate product IDs rejected"){try ProjectFile.validate(duplicateProduct)}
        var dangling = demo; dangling.choices["invalid"] = "unknown"
        throwsTest("invalid manual assignments rejected"){try ProjectFile.validate(dangling)}
        let projectBytes = try JSONEncoder().encode(ProjectFile(purchase:demo))
        let archive = try JSONDecoder().decode(ProjectFile.self,from:projectBytes)
        test("portable JSON roundtrip",archive.purchase == demo && archive.version == 1)
        try Data("corrupt".utf8).write(to:disk.url)
        throwsTest("corrupt state rejected without overwrite"){_ = try disk.load()}
        test("corrupt source preserved",try String(contentsOf:disk.url,encoding:.utf8) == "corrupt")
        throwsTest("disk failure propagated"){try LocalDisk(url:folder).save(snapshot)}
        let report: [String:Any] = ["checksPassed":passed.count,"checks":passed,"installedUIVerified":false,"scope":"own arithmetic, validation, import/export and persistence; not an installed UI result"]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]))
        print("")
    }
}

import SwiftUI
import AppKit

enum Screen: String, CaseIterable {
    case purchase = "Закупка", offers = "Предложения", comparison = "Сравнение"
}
struct Entry: View {
    let title: String
    @Binding var text: String
    var hint = ""
    init(_ title: String, text: Binding<String>, hint: String = "") {
        self.title = title; self._text = text; self.hint = hint
    }
    var body: some View {
        HStack(alignment:.firstTextBaseline,spacing:12) {
            Text(title).frame(width:205,alignment:.leading).foregroundStyle(.secondary)
            TextField(hint,text:$text).textFieldStyle(.roundedBorder).accessibilityLabel(title)
        }
    }
}
struct ContentView: View {
    @StateObject private var store = CompareStore()
    @State private var screen: Screen = .comparison
    @State private var supplierID: UUID?
    @State private var importing = false
    @State private var removeKind = ""
    @State private var removeID: UUID?
    @State private var removeName = ""
    @State private var comparisonDay = Dates.string(Date())

    var body: some View {
        VStack(spacing:0) {
            header
            Divider()
            HSplitView {
                sidebar
                VStack(spacing:0) {
                    if let p = store.current {
                        HStack {
                            Text(p.name).font(.title2.bold()).lineLimit(2)
                            Spacer()
                            Picker("Раздел",selection:$screen) {
                                ForEach(Screen.allCases,id:\.self) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.segmented).frame(width:355)
                        }.padding(18)
                        Divider()
                        switch screen {
                        case .purchase: PurchaseView(store:store,purchase:p,remove:requestRemoveProduct)
                        case .offers: offers(p)
                        case .comparison: ComparisonView(store:store,purchase:p,asOf:comparisonDay,openSupplier:{ id in supplierID = id; screen = .offers })
                        }
                    } else { welcome }
                }.frame(minWidth:850)
            }
            Divider()
            HStack {
                Text(store.blocked ? "Сохранение заблокировано; исходный файл не изменён" : store.saved.isEmpty ? "Локальное хранение · без сетевого доступа" : store.saved)
                Spacer(); Text(comparisonDay+" · ANODHAS AI · 1.0.0")
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal,16).padding(.vertical,8)
        }
        .frame(minWidth:1080,minHeight:720).tint(.orange)
        .alert("Не удалось выполнить действие",isPresented:Binding(get:{!store.error.isEmpty},set:{if !$0 { store.error = "" }})) {
            Button("Понятно") { store.error = "" }
        } message: { Text(store.error) }
        .confirmationDialog("Удалить «\(removeName)»?",isPresented:Binding(get:{!removeKind.isEmpty},set:{if !$0 { removeKind = "" }}),titleVisibility:.visible) {
            Button("Удалить",role:.destructive) {
                switch removeKind {
                case "product": if let id = removeID { store.removeProduct(id) }
                case "supplier": if let id = removeID { store.removeSupplier(id); supplierID = nil }
                case "purchase": store.removeCurrent()
                default: break
                }
                removeKind = ""
            }
            Button("Отмена",role:.cancel) { removeKind = "" }
        } message: { Text("Будут удалены связанные строки и выбор поставщика. Перед удалением можно сохранить закупку в JSON.") }
        .sheet(isPresented:$importing) {
            if let p = store.current, let s = selectedSupplier(p) {
                ImportView(store:store,purchase:p,supplier:s)
            }
        }
        .onChange(of:store.data.selected) { _ in supplierID = nil }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in comparisonDay = Dates.string(Date()) }
    }
    private var header: some View {
        HStack(spacing:12) {
            Image(systemName:"square.grid.3x3.fill").font(.system(size:26)).foregroundStyle(.orange)
            VStack(alignment:.leading,spacing:3) {
                Text("Сравнение поставщиков").font(.title2.bold())
                Text("Товары, условия и стоимость всей закупки").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Новая закупка") { store.create(); screen = .purchase }.buttonStyle(.borderedProminent)
            Button("Пример закупки") { store.addDemo(); screen = .comparison }.accessibilityIdentifier("load-example")
            Button("Открыть закупку…") { store.openProject() }
        }.padding(18).disabled(store.blocked)
    }
    private var sidebar: some View {
        VStack(alignment:.leading,spacing:0) {
            Text("Закупки · \(store.data.purchases.count)").font(.headline).padding(14)
            List(selection:Binding(get:{store.data.selected},set:{store.select($0)})) {
                ForEach(store.data.purchases) { p in
                    VStack(alignment:.leading,spacing:5) {
                        Text(p.name).lineLimit(3)
                        Text("\(p.products.count) товаров · \(p.suppliers.count) поставщиков").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical,4).tag(p.id)
                }
            }
            if let p = store.current {
                Button("Удалить закупку…") { removeName = p.name; removeKind = "purchase" }.font(.caption).padding(14)
            }
        }.frame(minWidth:185,idealWidth:205,maxWidth:260).disabled(store.blocked)
    }
    private var welcome: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Сравните одинаковую закупку").font(.largeTitle.bold())
            Text("Задайте товары и характеристики, внесите предложения и проверьте итог вместе с доставкой. Программа подходит для разных категорий товаров: единицы и условия задаёте вы.")
            Text("Создайте закупку и добавьте предложения поставщиков. Все данные остаются на этом Mac.").foregroundStyle(.secondary)
            Button("Создать закупку") { store.create(); screen = .purchase }.buttonStyle(.borderedProminent)
        }.padding(45).frame(maxWidth:700,alignment:.leading)
    }
    private func selectedSupplier(_ p: Purchase) -> Supplier? { p.suppliers.first{$0.id == supplierID} ?? p.suppliers.first }
    private func requestRemoveProduct(_ p: Product) { removeID = p.id; removeName = p.name.isEmpty ? "товар без названия" : p.name; removeKind = "product" }
    private func offers(_ p: Purchase) -> some View {
        HSplitView {
            VStack(alignment:.leading,spacing:10) {
                Button("Добавить поставщика") { supplierID = store.addSupplier() }
                List(selection:Binding(get:{selectedSupplier(p)?.id},set:{supplierID = $0})) {
                    ForEach(p.suppliers) { s in
                        Text(s.name.isEmpty ? "Без названия" : s.name).lineLimit(3).tag(s.id)
                    }
                }
            }.padding(12).frame(minWidth:170,idealWidth:190,maxWidth:240)
            if let s = selectedSupplier(p) {
                SupplierView(store:store,purchase:p,supplier:s,asOf:comparisonDay,importAction:{importing = true},remove:{
                    removeID = s.id; removeName = s.name.isEmpty ? "поставщика без названия" : s.name; removeKind = "supplier"
                })
            } else {
                Text("Добавьте поставщика и заполните его предложение.").foregroundStyle(.secondary).padding(30).frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }.disabled(store.blocked)
    }
}

struct PurchaseView: View {
    @ObservedObject var store: CompareStore
    let purchase: Purchase
    let remove: (Product) -> Void
    private func field(_ key: WritableKeyPath<Purchase,String>) -> Binding<String> {
        Binding(get:{store.current?[keyPath:key] ?? ""},set:{ v in store.update{$0[keyPath:key] = v} })
    }
    private func field(_ id: UUID, _ key: WritableKeyPath<Product,String>) -> Binding<String> {
        Binding(get:{store.current?.products.first{$0.id == id}?[keyPath:key] ?? ""},set:{v in store.updateProduct(id){$0[keyPath:key] = v}})
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                GroupBox("Условия закупки") {
                    VStack(spacing:10) {
                        Entry("Название",text:field(\.name))
                        Entry("Валюта сравнения",text:field(\.currency),hint:"RUB, USD, EUR…")
                        Entry("Получить не позднее",text:field(\.deadline),hint:"ГГГГ-ММ-ДД; пусто — без ограничения")
                        Entry("Предоплата не выше, %",text:field(\.maxAdvance),hint:"0–100")
                        Stepper("Денежных знаков после запятой: \(purchase.precision)",value:Binding(get:{store.current?.precision ?? 2},set:{v in store.update{$0.precision = v}}),in:0...4)
                    }.padding(10)
                }
                HStack { Text("Товары · \(purchase.products.count)").font(.title3.bold()); Spacer(); Button("Добавить товар"){store.addProduct()} }
                ForEach(purchase.products) { item in
                    GroupBox {
                        VStack(alignment:.leading,spacing:10) {
                            Entry("Товар",text:field(item.id,\.name),hint:"Любая категория")
                            Entry("Свой артикул",text:field(item.id,\.sku),hint:"Необязательно")
                            Entry("Характеристики",text:field(item.id,\.specification),hint:"Размер, марка, сорт, модель…")
                            Entry("Необходимое количество",text:field(item.id,\.quantity),hint:"Например, 100 или 2,5")
                            Entry("Базовая единица",text:field(item.id,\.unit),hint:"шт., кг, л, м, м²…")
                            HStack {
                                Text("Изменение потребности возвращает строки предложений на проверку.").font(.caption).foregroundStyle(.secondary)
                                Spacer(); Button("Удалить товар…"){remove(item)}
                            }
                        }.padding(10)
                    }
                }
                Text("Схожие названия не означают одинаковые товары. Перед сравнением подтвердите соответствие в предложениях.").font(.callout).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth:1000,alignment:.leading)
        }.disabled(store.blocked)
    }
}

struct SupplierView: View {
    @ObservedObject var store: CompareStore
    let purchase: Purchase
    let supplier: Supplier
    let asOf: String
    let importAction: () -> Void
    let remove: () -> Void
    private func field(_ key: WritableKeyPath<Supplier,String>) -> Binding<String> {
        Binding(get:{store.current?.suppliers.first{$0.id == supplier.id}?[keyPath:key] ?? ""},set:{v in store.updateSupplier(supplier.id){$0[keyPath:key] = v}})
    }
    private var result: SupplierResult { Engine.supplier(purchase,supplier,asOf:asOf) }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:17) {
                HStack {
                    Text(supplier.name.isEmpty ? "Новое предложение" : supplier.name).font(.title3.bold())
                    Spacer(); Button("Импорт CSV / Excel"){importAction()}.disabled(purchase.products.isEmpty)
                }
                GroupBox("Общие условия предложения") { general.padding(10) }
                Text("Позиции · цены за единицу предложения").font(.headline)
                if purchase.products.isEmpty { Text("Сначала добавьте товары во вкладке «Закупка».").foregroundStyle(.secondary) }
                ForEach(purchase.products) { item in
                    if let line = supplier.lines.first(where:{$0.productID == item.id}) {
                        QuoteLineView(store:store,supplierID:supplier.id,item:item,offer:line,result:result.lines.first{$0.id == item.id},currency:purchase.currency,precision:purchase.precision)
                    }
                }
                GroupBox("Итог предложения") {
                    VStack(alignment:.leading,spacing:8) {
                        Text(Value.money(result.total,currency:Value.currency(purchase.currency),precision:purchase.precision)).font(.title2.bold())
                        if result.eligible { Label("Подходит по введённым условиям",systemImage:"checkmark.circle.fill").foregroundStyle(.green) }
                        else { ForEach(Array(result.reasons.enumerated()),id:\.offset) { _,text in Text("• "+text).foregroundStyle(.orange) } }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(10)
                }
                Button("Удалить поставщика…",action:remove).font(.caption)
            }.padding(18)
        }.frame(minWidth:580)
    }
    private var general: some View {
        VStack(spacing:10) {
            Entry("Поставщик",text:field(\.name))
            Entry("Валюта предложения",text:field(\.currency),hint:"RUB")
            if Value.currency(supplier.currency) != Value.currency(purchase.currency) {
                Entry("Курс за 1 \(supplier.currency)",text:field(\.exchangeRate),hint:"Сколько \(purchase.currency) за 1 \(supplier.currency)")
                Entry("Дата курса",text:field(\.rateDate),hint:"ГГГГ-ММ-ДД")
                Entry("Источник курса",text:field(\.rateSource),hint:"Документ или источник значения")
            }
            Entry("Дата получения",text:field(\.deliveryDate),hint:"ГГГГ-ММ-ДД")
            Entry("КП действует до",text:field(\.validUntil),hint:"ГГГГ-ММ-ДД включительно")
            Entry("Предоплата, %",text:field(\.advance),hint:"0–100; 0 — без предоплаты")
            Entry("Условия оплаты",text:field(\.paymentTerms),hint:"Например, остаток через 30 дней")
            HStack {
                Text("Доставка").foregroundStyle(.secondary).frame(width:205,alignment:.leading)
                Picker("Доставка",selection:Binding(get:{supplier.shipping},set:{v in store.updateSupplier(supplier.id){$0.shipping = v}})) {
                    ForEach(ShippingMode.allCases,id:\.self){Text($0.rawValue).tag($0)}
                }.labelsHidden().frame(maxWidth:.infinity)
            }
            if supplier.shipping == .extra {
                Entry("Доставка итого",text:field(\.shippingAmount),hint:"С налогами, в \(supplier.currency)")
                Entry("Бесплатно от суммы",text:field(\.freeShippingAbove),hint:"Товары с налогами; пусто — без порога")
            }
            Entry("Прочие сборы итого",text:field(\.fees),hint:"С налогами; 0 — сборов нет")
            Entry("Источник / номер КП",text:field(\.source),hint:"Документ, дата или ручной ввод")
            Text("Доставка и общие сборы применяются один раз к заказу этого поставщика.").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
        }
    }
}

struct QuoteLineView: View {
    @ObservedObject var store: CompareStore
    let supplierID: UUID
    let item: Product
    let offer: QuoteLine
    let result: LineResult?
    let currency: String
    let precision: Int
    @State private var expanded = false
    private func field(_ key: WritableKeyPath<QuoteLine,String>) -> Binding<String> {
        Binding(get:{store.current?.suppliers.first{$0.id == supplierID}?.lines.first{$0.productID == item.id}?[keyPath:key] ?? ""},set:{v in store.updateLine(supplierID,product:item.id){$0[keyPath:key] = v}})
    }
    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded:$expanded) {
                VStack(alignment:.leading,spacing:10) {
                    Text(item.specification).foregroundStyle(.secondary)
                    Text("Потребность: \(item.quantity) \(item.unit)").font(.callout)
                    Entry("Цена за единицу",text:field(\.price),hint:"0 допускается, если подтверждено")
                    Entry("Единица цены",text:field(\.unit),hint:"Например, м, кг или коробка")
                    if Value.unit(item.unit) != Value.unit(offer.unit) {
                        Entry("В 1 единице цены, \(item.unit)",text:field(\.factor),hint:"Подтверждённое содержимое упаковки")
                    }
                    Entry("Минимум единиц цены",text:field(\.minimum),hint:"0 — минимума нет")
                    Entry("Шаг единиц цены",text:field(\.step),hint:"0 — любой дробный объём")
                    Entry("Скидка, %",text:field(\.discount),hint:"0–100")
                    HStack {
                        Text("НДС").foregroundStyle(.secondary).frame(width:205,alignment:.leading)
                        Picker("НДС",selection:Binding(get:{offer.tax},set:{v in store.updateLine(supplierID,product:item.id){$0.tax = v}})) {
                            ForEach(TaxMode.allCases,id:\.self){Text($0.rawValue).tag($0)}
                        }.labelsHidden().frame(maxWidth:.infinity)
                    }
                    if offer.tax == .extra || offer.tax == .included {
                        Entry("Ставка НДС, %",text:field(\.taxRate),hint:offer.tax == .extra ? "Обязательно, 0–100" : "Необязательно: НДС уже в цене")
                    }
                    Entry("Остаток, \(item.unit)",text:field(\.stock),hint:"Если указан в КП")
                    Entry("Источник / примечание",text:field(\.source))
                    Toggle("Товар, объём и условия проверены",isOn:Binding(get:{offer.checked},set:{v in store.updateLine(supplierID,product:item.id){$0.checked = v}}))
                    if let result {
                        Text("Стоимость позиции: "+Value.money(result.total,currency:Value.currency(currency),precision:precision)).font(.headline)
                        if let qty = result.purchasedBase, let surplus = result.surplus {
                            Text("Закупаем \(Value.display(qty)) \(item.unit), излишек \(Value.display(surplus)) \(item.unit)").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(Array(result.issues.enumerated()),id:\.offset) { _,issue in Text("• "+issue).font(.caption).foregroundStyle(.orange) }
                    }
                }.padding(.top,12)
            } label: {
                HStack {
                    Text(item.name.isEmpty ? "Товар без названия" : item.name).font(.headline)
                    Spacer()
                    Text(offer.price.isEmpty ? "Цена не указана" : offer.price+" / "+offer.unit).foregroundStyle(.secondary)
                    Image(systemName:offer.checked ? "checkmark.circle.fill" : "circle").foregroundStyle(offer.checked ? Color.green : Color.secondary)
                }.padding(.vertical,5)
            }
        }
    }
}

enum SortOrder: String, CaseIterable { case cost = "По стоимости", date = "По сроку", advance = "По предоплате" }
struct ComparisonView: View {
    @ObservedObject var store: CompareStore
    let purchase: Purchase
    let asOf: String
    let openSupplier: (UUID) -> Void
    @State private var suitableOnly = false
    @State private var order: SortOrder = .cost
    private var results: [SupplierResult] { Engine.all(purchase,asOf:asOf) }
    private var visible: [SupplierResult] {
        results.filter{!suitableOnly || $0.eligible}.sorted { a,b in
            if a.eligible != b.eligible { return a.eligible }
            switch order {
            case .cost:
                if a.total != b.total { return (a.total ?? Decimal(9_000_000_000_000_000 as Int64)) < (b.total ?? Decimal(9_000_000_000_000_000 as Int64)) }
            case .date: if a.delivery != b.delivery { return a.delivery < b.delivery }
            case .advance: if a.advance != b.advance { return (a.advance ?? 101) < (b.advance ?? 101) }
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
    private func money(_ d: Decimal?) -> String { Value.money(d,currency:Value.currency(purchase.currency),precision:purchase.precision) }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                leaders
                HStack {
                    Text("Выгрузить:").foregroundStyle(.secondary)
                    ForEach(ExportKind.allCases,id:\.self) { kind in
                        Button(kind.rawValue) { store.export(kind) }
                    }
                    Spacer()
                }
                HStack {
                    Picker("Сортировка",selection:$order){ForEach(SortOrder.allCases,id:\.self){Text($0.rawValue).tag($0)}}.frame(width:245)
                    Toggle("Только подходящие",isOn:$suitableOnly)
                    Spacer()
                    Text("Подходит \(results.filter(\.eligible).count) из \(results.count)").font(.caption).foregroundStyle(.secondary)
                }
                if purchase.products.isEmpty || purchase.suppliers.isEmpty {
                    Text("Добавьте товары и предложения. В заполненном примере можно посмотреть сравнение и причины исключения.").foregroundStyle(.secondary).padding(.vertical,25)
                } else { matrix }
                manual
                Text("Сравнение по введённым условиям. Нет автоматической покупки, оценки репутации или скрытого общего балла.").font(.caption).foregroundStyle(.secondary)
            }.padding(18)
        }.disabled(store.blocked)
    }
    private var leaders: some View {
        let eligible = results.filter(\.eligible)
        let cheapest = Engine.cheapest(results)
        let fastestDate = eligible.map(\.delivery).min()
        let smallestAdvance = eligible.compactMap(\.advance).min()
        return GroupBox("Лидеры среди подходящих предложений") {
            VStack(alignment:.leading,spacing:8) {
                Text(cheapest.isEmpty ? "Пока нет подходящих предложений" : "Минимальная стоимость: "+cheapest.map(\.name).joined(separator:", ")+" · "+money(cheapest.first?.total)).font(.headline)
                if let date = fastestDate {
                    Text("Раньше получение: "+eligible.filter{$0.delivery == date}.map(\.name).joined(separator:", ")+" · "+date)
                }
                if let advance = smallestAdvance {
                    Text("Меньше предоплата: "+eligible.filter{$0.advance == advance}.map(\.name).joined(separator:", ")+" · "+Value.display(advance)+"%")
                }
                if eligible.isEmpty { Text("Причины и незаполненные условия указаны в таблице.").foregroundStyle(.secondary) }
            }.frame(maxWidth:.infinity,alignment:.leading).padding(10)
        }
    }
    private var matrix: some View {
        ScrollView(.horizontal) {
            VStack(alignment:.leading,spacing:0) {
                HStack(alignment:.top,spacing:0) {
                    Text("Потребность\nСуммы позиций").font(.headline).frame(width:190,alignment:.leading).padding(10)
                    ForEach(visible) { r in
                        VStack(alignment:.leading,spacing:6) {
                            Button(r.name.isEmpty ? "Без названия" : r.name){openSupplier(r.id)}.lineLimit(3).help(r.name)
                            Label(r.eligible ? "Подходит" : "Проверить",systemImage:r.eligible ? "checkmark.circle" : "exclamationmark.circle").font(.caption).foregroundStyle(r.eligible ? Color.green : Color.orange)
                        }.frame(width:155,alignment:.leading).padding(10)
                    }
                }.background(.quaternary)
                ForEach(purchase.products) { item in
                    Divider()
                    HStack(alignment:.top,spacing:0) {
                        VStack(alignment:.leading,spacing:5) {
                            Text(item.name).font(.headline).lineLimit(3)
                            Text(item.quantity+" "+item.unit).font(.caption).foregroundStyle(.secondary)
                        }.frame(width:190,alignment:.leading).padding(10)
                        ForEach(visible) { r in
                            let line = r.lines.first{$0.id == item.id}
                            VStack(alignment:.leading,spacing:5) {
                                Text(money(line?.total)).monospacedDigit()
                                if let qty = line?.purchasedBase { Text("Закупаем "+Value.display(qty)+" "+item.unit).font(.caption).foregroundStyle(.secondary) }
                                if let reason = line?.issues.first { Text(reason).font(.caption).foregroundStyle(.orange) }
                            }.frame(width:155,alignment:.leading).padding(10)
                        }
                    }
                }
                moneyRow("Доставка",values:visible.map(\.shipping))
                moneyRow("Прочие сборы",values:visible.map(\.fees))
                moneyRow("Всего по закупке",values:visible.map(\.total),bold:true)
                HStack(alignment:.top,spacing:0) {
                    Text("Получение / проверка").font(.caption).frame(width:190,alignment:.leading).padding(10)
                    ForEach(visible) { r in
                        VStack(alignment:.leading,spacing:6) {
                            Text(r.delivery.isEmpty ? "Дата не указана" : r.delivery).font(.caption)
                            ForEach(Array(r.reasons.enumerated()),id:\.offset) { _,reason in Text(reason).font(.caption).foregroundStyle(.orange) }
                        }.frame(width:155,alignment:.leading).padding(10)
                    }
                }
            }
        }
    }
    private func moneyRow(_ title: String, values: [Decimal?], bold: Bool = false) -> some View {
        VStack(spacing:0) {
            Divider()
            HStack(alignment:.top,spacing:0) {
                Text(title).frame(width:190,alignment:.leading).padding(10)
                ForEach(Array(values.enumerated()),id:\.offset) { _,value in Text(money(value)).monospacedDigit().frame(width:155,alignment:.leading).padding(10) }
            }.font(bold ? .headline : .body)
        }
    }
    private var manual: some View {
        let mixed = Engine.mixed(purchase,asOf:asOf)
        return GroupBox("Ручной вариант · по одному поставщику на позицию") {
            VStack(alignment:.leading,spacing:12) {
                Text("Доставка, пороги и общие сборы пересчитываются для каждого выбранного поставщика.").font(.caption).foregroundStyle(.secondary)
                ForEach(purchase.products) { item in
                    HStack {
                        Text(item.name).frame(width:205,alignment:.leading).lineLimit(3)
                        Picker("Поставщик для \(item.name)",selection:Binding(get:{purchase.choices[item.id.uuidString] ?? ""},set:{value in
                            store.update { p in if value.isEmpty { p.choices.removeValue(forKey:item.id.uuidString) } else { p.choices[item.id.uuidString] = value } }
                        })) {
                            Text("Не выбран").tag("")
                            ForEach(purchase.suppliers) { s in Text(s.name.isEmpty ? "Без названия" : s.name).tag(s.id.uuidString) }
                        }.labelsHidden().frame(maxWidth:.infinity)
                    }
                }
                Text("Итог ручного варианта: "+money(mixed.total)).font(.title3.bold())
                ForEach(mixed.groups) { group in
                    Text(group.name+": "+money(group.total)+" · доставка "+money(group.shipping)+" · сборы "+money(group.fees)).font(.caption)
                }
                ForEach(Array(mixed.issues.enumerated()),id:\.offset) { _,issue in Text("• "+issue).font(.caption).foregroundStyle(.orange) }
                Text("Почему выбран этот вариант").font(.caption).foregroundStyle(.secondary)
                TextEditor(text:Binding(get:{store.current?.decision ?? ""},set:{v in store.update{$0.decision = v}})).frame(minHeight:70).font(.body).border(Color.secondary.opacity(0.25))
            }.padding(10)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@main struct SupplierCompareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("Сравнение поставщиков") { ContentView() }.defaultSize(width:1320,height:850)
            .commands { CommandGroup(replacing:.newItem) {} }
    }
}

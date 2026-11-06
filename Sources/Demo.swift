import Foundation

enum Demo {
    static func purchase(today: Date = Date()) -> Purchase {
        func date(_ offset: Int) -> String { Dates.string(Calendar.current.date(byAdding:.day,value:offset,to:today)!) }
        let cable = Product(name:"Кабель монтажный", sku:"CAB-01", specification:"Медный, 3×2,5 мм²", unit:"м", quantity:"100")
        let light = Product(name:"Светильник", sku:"LGT-01", specification:"LED, 4000 К, IP54", unit:"шт.", quantity:"20")
        var p = Purchase(name:"Материалы и оборудование", deadline:date(7), maxAdvance:"50", products:[cable,light], isDemo:true)
        func supplier(_ name: String, cablePrice: String, lightPrice: String, days: Int, shipping: ShippingMode, freight: String, advance: String) -> Supplier {
            var s = Supplier.blank(products:p.products,currency:p.currency)
            s.name = name; s.deliveryDate = date(days); s.validUntil = date(30)
            s.advance = advance; s.shipping = shipping; s.shippingAmount = freight; s.fees = "0"
            s.paymentTerms = advance == "0" ? "Оплата после получения" : "Остаток после получения"
            s.source = "Пример закупки"
            for i in s.lines.indices {
                s.lines[i].price = s.lines[i].productID == cable.id ? cablePrice : lightPrice
                s.lines[i].tax = .exempt; s.lines[i].checked = true
                s.lines[i].source = "Пример позиции"
            }
            return s
        }
        let a = supplier("А · Стандарт",cablePrice:"500",lightPrice:"700",days:3,shipping:.extra,freight:"3000",advance:"50")
        let b = supplier("Б · Комплект",cablePrice:"520",lightPrice:"650",days:2,shipping:.included,freight:"",advance:"0")
        let c = supplier("В · Поздняя поставка",cablePrice:"480",lightPrice:"620",days:12,shipping:.extra,freight:"2000",advance:"0")
        let d = supplier("Г · Уточнить доставку",cablePrice:"490",lightPrice:"630",days:1,shipping:.unknown,freight:"",advance:"30")
        let e = supplier("Д · Полная предоплата",cablePrice:"510",lightPrice:"640",days:4,shipping:.extra,freight:"2500",advance:"100")
        p.suppliers = [a,b,c,d,e]
        p.choices = [cable.id.uuidString:a.id.uuidString,light.id.uuidString:b.id.uuidString]
        p.decision = "Сравните целые предложения и ручной вариант. При выборе разных поставщиков учитывается доставка каждого заказа."
        return p
    }
}

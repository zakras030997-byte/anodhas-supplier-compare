import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImportView: View {
    @ObservedObject var store: CompareStore
    let purchase: Purchase
    let supplier: Supplier
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var source = "Вставка таблицы"
    @State private var table: CSVTable?
    @State private var columns = ColumnMap()
    @State private var overrides: [Int:String] = [:]
    @State private var error = ""
    private var rows: [ImportRow] {
        guard let table else { return [] }
        return ImportPlan.rows(table,map:columns,purchase:purchase,overrides:overrides)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text("Импорт позиций").font(.title2.bold())
                    Text("Получатель: "+(supplier.name.isEmpty ? "поставщик без названия" : supplier.name)).foregroundStyle(.secondary)
                }
                Spacer(); Button("Открыть CSV / TSV…"){openFile()}
            }
            Text("Вставьте таблицу из Excel или текст CSV с заголовками. Выберите колонки товара/артикула, цены и единицы. До 200 записей, UTF-8.")
            TextEditor(text:$text).font(.system(.body,design:.monospaced)).frame(height:130).border(Color.secondary.opacity(0.3)).accessibilityLabel("Исходная таблица")
            HStack {
                Text(source).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(); Button("Прочитать таблицу"){parse()}.disabled(text.isEmpty)
            }
            if let table {
                HStack(spacing:16) {
                    columnPicker("Товар / артикул",selection:$columns.product,headers:table.headers)
                    columnPicker("Цена",selection:$columns.price,headers:table.headers)
                    columnPicker("Единица",selection:$columns.unit,headers:table.headers)
                }
                Divider()
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:14) {
                        ForEach(rows) { row in
                            VStack(alignment:.leading,spacing:7) {
                                Text("Запись \(row.id): \(row.sourceName) · \(row.price) / \(row.unit)").font(.headline)
                                Picker("Товар закупки для записи \(row.id)",selection:Binding(get:{row.productID},set:{overrides[row.id] = $0})) {
                                    Text("Выберите товар").tag("")
                                    ForEach(purchase.products) { item in
                                        Text((item.sku.isEmpty ? "" : item.sku+" · ")+item.name).tag(item.id.uuidString)
                                    }
                                }
                                ForEach(Array(row.issues.enumerated()),id:\.offset) { _,issue in Text("• "+issue).font(.caption).foregroundStyle(.orange) }
                            }
                            Divider()
                        }
                    }
                }.frame(minHeight:170)
                Text("Будут заменены строки этих \(rows.count) товаров. Остальные позиции останутся. НДС, упаковки и соответствие потребуется проверить заново.").font(.caption).foregroundStyle(.secondary)
            } else {
                Spacer()
            }
            if !error.isEmpty { Text(error).foregroundStyle(.orange).font(.callout) }
            HStack {
                Button("Отмена"){dismiss()}.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Применить \(rows.count) записей") {
                    if store.importRows(rows,purchase:purchase.id,supplier:supplier.id,source:source) { dismiss() }
                    else { error = store.error }
                }.buttonStyle(.borderedProminent).disabled(rows.isEmpty || rows.contains{!$0.issues.isEmpty})
            }
        }.padding(24).frame(width:850,height:720)
        .onChange(of:text) { _ in table = nil; overrides = [:]; error = "" }
        .onChange(of:columns.product) { _ in overrides = [:] }
    }
    private func columnPicker(_ title: String, selection: Binding<Int>, headers: [String]) -> some View {
        Picker(title,selection:selection) {
            ForEach(headers.indices,id:\.self) { i in Text("\(i+1). "+headers[i]).tag(i) }
        }.frame(maxWidth:.infinity)
    }
    private func parse() {
        do {
            let parsed = try Delimited.parse(text)
            columns = ColumnMap.guess(parsed.headers); overrides = [:]; error = ""; table = parsed
        } catch { self.error = error.localizedDescription; table = nil }
    }
    private func openFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.commaSeparatedText,.tabSeparatedText,.plainText]; panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                guard size <= 1_048_576 else { throw ImportError.message("Файл больше 1 МиБ.") }
                guard let raw = String(data:try Data(contentsOf:url),encoding:.utf8) else { throw ImportError.message("Сохраните таблицу в UTF-8 CSV или вставьте её из Excel.") }
                text = raw; source = url.lastPathComponent; table = nil; error = ""
            } catch { self.error = error.localizedDescription }
        }
    }
}

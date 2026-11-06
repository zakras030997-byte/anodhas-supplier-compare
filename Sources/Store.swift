import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ExportKind: String, CaseIterable {
    case summary = "Сводка CSV", lines = "Позиции CSV", html = "Отчёт HTML", project = "Закупка JSON"
    var ext: String { switch self { case .summary,.lines:return "csv"; case .html:return "html"; case .project:return "json" } }
    var type: UTType { switch self { case .summary,.lines:return .commaSeparatedText; case .html:return .html; case .project:return .json } }
}
@MainActor final class CompareStore: ObservableObject {
    @Published private(set) var data = Workspace()
    @Published var error = ""
    @Published private(set) var blocked = false
    @Published private(set) var saved = ""
    private let disk: LocalDisk
    private var savePanel: NSSavePanel?
    private var openPanel: NSOpenPanel?
    init() {
        let folder = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("SupplierCompare",isDirectory:true)
        disk = LocalDisk(url:folder.appendingPathComponent("workspace-v1.json"))
        do {
            let loaded = try disk.load()
            var refreshed = loaded; refreshed.refreshExampleLabels()
            if refreshed != loaded { try disk.save(refreshed) }
            data = refreshed
        }
        catch { blocked = true; self.error = "Не удалось прочитать сохранённые закупки. Файл не перезаписан. Сохраните его копию и проверьте: \(disk.url.path)" }
    }
    var current: Purchase? { data.purchases.first { $0.id == data.selected } }
    @discardableResult func commit(_ candidate: Workspace) -> Bool {
        guard !blocked else { return false }
        do {
            try disk.save(candidate); data = candidate
            saved = "Сохранено на Mac · " + Date().formatted(date:.omitted,time:.shortened)
            return true
        } catch { self.error = "Изменение не сохранено. Прежние данные оставлены; проверьте место и доступ к диску."; return false }
    }
    func select(_ id: UUID?) { var d = data; d.selected = id; _ = commit(d) }
    func update(_ edit: (inout Purchase) -> Void) {
        guard let id = data.selected else { return }
        update(id,edit)
    }
    func update(_ id: UUID, _ edit: (inout Purchase) -> Void) {
        var d = data
        guard let i = d.purchases.firstIndex(where:{$0.id == id}) else { return }
        edit(&d.purchases[i]); _ = commit(d)
    }
    func updateProduct(_ id: UUID, _ edit: (inout Product) -> Void) {
        update { p in
            guard let i = p.products.firstIndex(where:{$0.id == id}) else { return }
            let previous = p.products[i]; edit(&p.products[i])
            if previous != p.products[i] {
                for s in p.suppliers.indices {
                    for line in p.suppliers[s].lines.indices where p.suppliers[s].lines[line].productID == id {
                        p.suppliers[s].lines[line].checked = false
                    }
                }
            }
        }
    }
    func updateSupplier(_ id: UUID, _ edit: (inout Supplier) -> Void) {
        update { p in
            guard let i = p.suppliers.firstIndex(where:{$0.id == id}) else { return }
            let currency = p.suppliers[i].currency; edit(&p.suppliers[i])
            if currency != p.suppliers[i].currency {
                p.suppliers[i].exchangeRate = ""; p.suppliers[i].rateDate = ""; p.suppliers[i].rateSource = ""
            }
        }
    }
    func updateLine(_ supplier: UUID, product: UUID, _ edit: (inout QuoteLine) -> Void) {
        updateSupplier(supplier) { s in
            guard let i = s.lines.firstIndex(where:{$0.productID == product}) else { return }
            edit(&s.lines[i])
        }
    }
    func create() {
        guard data.purchases.count < 100 else { error = "Доступно до 100 закупок в рабочем пространстве."; return }
        var d = data; let p = Purchase(products:[Product()])
        d.purchases.append(p); d.selected = p.id; _ = commit(d)
    }
    func addDemo() {
        if let demo = data.purchases.first(where:\.isDemo) { select(demo.id); return }
        guard data.purchases.count < 100 else { error = "Сначала освободите место в списке закупок."; return }
        var d = data; let p = Demo.purchase()
        d.purchases.append(p); d.selected = p.id; _ = commit(d)
    }
    func addProduct() {
        if current?.products.count ?? 0 >= 200 { error = "В закупке доступно до 200 товаров."; return }
        update { p in
            let item = Product(); p.products.append(item)
            for i in p.suppliers.indices { p.suppliers[i].lines.append(QuoteLine(productID:item.id,unit:item.unit)) }
        }
    }
    func removeProduct(_ id: UUID) {
        update { p in
            p.products.removeAll{$0.id == id}; p.choices.removeValue(forKey:id.uuidString)
            for i in p.suppliers.indices { p.suppliers[i].lines.removeAll{$0.productID == id} }
        }
    }
    func addSupplier() -> UUID? {
        guard let p = current else { return nil }
        guard p.suppliers.count < 50 else { error = "В закупке доступно до 50 поставщиков."; return nil }
        let s = Supplier.blank(products:p.products,currency:Value.currency(p.currency))
        update { $0.suppliers.append(s) }; return s.id
    }
    func removeSupplier(_ id: UUID) {
        update { p in
            p.suppliers.removeAll{$0.id == id}
            p.choices = p.choices.filter { $0.value != id.uuidString }
        }
    }
    func removeCurrent() {
        guard let id = data.selected else { return }
        var d = data; d.purchases.removeAll{$0.id == id}; d.selected = d.purchases.first?.id; _ = commit(d)
    }
    @discardableResult func importRows(_ rows: [ImportRow], purchase: UUID, supplier: UUID, source: String) -> Bool {
        guard let p = data.purchases.first(where:{$0.id == purchase}),
              let s = p.suppliers.first(where:{$0.id == supplier}) else { error = "Получатель импорта больше не доступен."; return false }
        do {
            let next = try ImportPlan.apply(rows,to:s,source:source)
            var copy = data
            guard let i = copy.purchases.firstIndex(where:{$0.id == purchase}),
                  let j = copy.purchases[i].suppliers.firstIndex(where:{$0.id == supplier}) else { return false }
            copy.purchases[i].suppliers[j] = next
            return commit(copy)
        } catch { self.error = error.localizedDescription; return false }
    }
    func export(_ kind: ExportKind) {
        guard let p = current, savePanel == nil else { return }
        do {
            let bytes: Data
            switch kind {
            case .summary: bytes = Report.csv(p)
            case .lines: bytes = Report.linesCSV(p)
            case .html: bytes = Report.html(p)
            case .project:
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
                bytes = try encoder.encode(ProjectFile(purchase:p))
            }
            let panel = NSSavePanel(); panel.nameFieldStringValue = "supplier-comparison-" + Dates.string(Date()) + "." + kind.ext
            panel.allowedContentTypes = [kind.type]
            savePanel = panel
            let completion: (NSApplication.ModalResponse) -> Void = { response in
                self.savePanel = nil
                guard response == .OK, let url = panel.url else { return }
                do { try bytes.write(to:url,options:.atomic) }
                catch { self.error = "Не удалось сохранить файл. Выберите доступную папку." }
            }
            if let window = NSApp.keyWindow ?? NSApp.mainWindow { panel.beginSheetModal(for:window,completionHandler:completion) }
            else { panel.begin(completionHandler:completion) }
        } catch { self.error = "Не удалось сформировать файл закупки." }
    }
    func openProject() {
        guard !blocked, openPanel == nil else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        openPanel = panel
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            self.openPanel = nil
            guard response == .OK, let url = panel.url else { return }
            do {
                guard try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0 <= 4_000_000 else { throw DataError.tooLarge }
                let doc = try JSONDecoder().decode(ProjectFile.self,from:Data(contentsOf:url))
                guard doc.version == 1, self.data.purchases.count < 100 else { throw DataError.invalid }
                try ProjectFile.validate(doc.purchase)
                var copy = doc.purchase; copy.id = UUID()
                copy.name += " · копия"
                var d = self.data; d.purchases.append(copy); d.selected = copy.id; _ = self.commit(d)
            } catch { self.error = "Файл не открыт: проверьте формат закупки 1.0 и размер до 4 МБ. Текущие закупки не изменены." }
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow { panel.beginSheetModal(for:window,completionHandler:completion) }
        else { panel.begin(completionHandler:completion) }
    }
}

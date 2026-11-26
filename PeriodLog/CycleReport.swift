import UIKit

enum CycleReport {
    @MainActor static func export(data: AppData, cycles: Int) throws -> URL {
        let page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let periods = CycleCore.periods(data.logs)
        let selected = Array(periods.suffix(cycles))
        let cutoff = selected.first?.start ?? Day()
        let stats = CycleCore.statistics(logs: data.logs.filter { $0.day >= cutoff })
        let pdf = renderer.pdfData { context in
            var y: CGFloat = 44
            func begin() {
                context.beginPage(); y = 44
                let footer = L.disclaimer as NSString
                footer.draw(in: CGRect(x: 40, y: 790, width: page.width - 80, height: 36), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray])
            }
            func line(_ text: String, bold: Bool = false, size: CGFloat = 12) {
                let p = NSMutableParagraphStyle(); p.lineBreakMode = .byWordWrapping
                let attributes: [NSAttributedString.Key: Any] = [.font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black, .paragraphStyle: p]
                let width = page.width - 80
                let height = max(20, (text as NSString).boundingRect(with: CGSize(width: width, height: 500), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height + 8)
                if y + height > 768 { begin() }
                (text as NSString).draw(in: CGRect(x: 40, y: y, width: width, height: height), withAttributes: attributes); y += height
            }
            begin()
            line(L.t("经期记录 · 周期汇总"), bold: true, size: 22)
            line(L.f("导出日期 %@", L.day(Day())))
            line(L.t("开始日 / 周期长度 / 经期天数"), bold: true)
            for p in selected {
                let index = periods.firstIndex { $0.id == p.id } ?? 0
                let length = index + 1 < periods.count ? String(p.start.distance(to: periods[index + 1].start)) : "—"
                line(L.day(p.start) + "     " + length + "     " + String(p.duration))
            }
            y += 12; line(L.t("症状统计"), bold: true, size: 17)
            for stage in SymptomStage.allCases {
                line(stage.title, bold: true)
                let values = stats.symptoms[stage] ?? []
                if values.isEmpty { line(L.t("暂无记录")) }
                for value in values { line(RecordOptions.title(value.key) + " · " + L.f("%@ 次", String(value.count))) }
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PeriodLog-" + UUID().uuidString + ".pdf")
        try pdf.write(to: url, options: [.atomic, .completeFileProtection]); return url
    }
}

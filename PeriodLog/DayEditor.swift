import SwiftUI

struct DayEditor: View {
    let day: Day
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var log = DayLog(day: Day())
    @State private var temperature = ""
    @State private var custom = ""
    @State private var loaded = false
    @State private var error: String?
    @State private var showPaywall = false
    @State private var deleteHealth = false
    private let columns = [GridItem(.adaptive(minimum: 85), spacing: 8)]
    var body: some View {
        SheetFrame(title: L.day(day, weekday: true)) {
            Form {
                if day > model.today { Text(L.t("未来日期只能查看预测。")) }
                Group {
                    Section(L.t("流量")) {
                        Picker(L.t("流量"), selection: $log.flow) {
                            Text(L.t("未记录")).tag(Flow?.none)
                            ForEach(Flow.allCases, id: \.rawValue) { Text($0.title).tag(Optional($0)) }
                        }.accessibilityIdentifier("editorFlow")
                    }
                    Section(L.t("身体")) {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                            ForEach(RecordOptions.symptoms + model.data.settings.customSymptoms, id: \.self) { key in
                                Chip(title: RecordOptions.title(key), selected: log.symptoms.contains(key), id: "editor-symptom-" + key) { toggle(key, symptoms: true) }
                            }
                        }
                        HStack {
                            TextField(L.t("自定义症状"), text: $custom).accessibilityIdentifier("customSymptom")
                            Button(L.t("添加")) {
                                guard model.premium else { showPaywall = true; return }
                                let value = String(custom.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
                                guard !value.isEmpty, !RecordOptions.symptoms.contains(value), !model.data.settings.customSymptoms.contains(value), model.data.settings.customSymptoms.count < 50 else { return }
                                model.data.settings.customSymptoms.append(value); log.symptoms.insert(value); custom = ""; model.save()
                            }.accessibilityIdentifier("addCustomSymptom")
                        }
                    }
                    Section(L.t("心情")) {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                            ForEach(RecordOptions.moods, id: \.self) { key in Chip(title: RecordOptions.title(key), selected: log.moods.contains(key), id: "editor-mood-" + key) { toggle(key, symptoms: false) } }
                        }
                    }
                    Section(L.t("更多记录")) {
                        Picker(L.t("白带"), selection: $log.discharge) {
                            Text(L.t("未记录")).tag(Discharge?.none)
                            ForEach(Discharge.allCases, id: \.rawValue) { Text($0.title).tag(Optional($0)) }
                        }.accessibilityIdentifier("editorDischarge")
                        TextField(L.t("基础体温（°C）"), text: $temperature).keyboardType(.decimalPad).accessibilityIdentifier("editorBBT")
                        Picker(L.t("排卵试纸"), selection: $log.ovulationTest) {
                            Text(L.t("未记录")).tag(OvulationTest?.none)
                            ForEach(OvulationTest.allCases, id: \.rawValue) { Text($0.title).tag(Optional($0)) }
                        }.accessibilityIdentifier("editorOvulation")
                        Picker(L.t("验孕结果"), selection: $log.pregnancyTest) {
                            Text(L.t("未记录")).tag(PregnancyTest?.none)
                            ForEach(PregnancyTest.allCases, id: \.rawValue) { Text($0.title).tag(Optional($0)) }
                        }.accessibilityIdentifier("editorPregnancy")
                        if model.data.settings.showSex || model.data.settings.purpose == .conceive {
                            Picker(L.t("同房"), selection: $log.sex) {
                                Text(L.t("未记录")).tag(Sex?.none)
                                ForEach(Sex.allCases, id: \.rawValue) { Text($0.title).tag(Optional($0)) }
                            }.accessibilityIdentifier("editorSex")
                        }
                        Picker(L.t("吃药"), selection: $log.pillTaken) {
                            Text(L.t("未记录")).tag(Bool?.none)
                            Text(L.t("已吃")).tag(Optional(true)); Text(L.t("未吃")).tag(Optional(false))
                        }.accessibilityIdentifier("editorPill")
                    }
                    Section(L.t("备注")) { TextField(L.t("写下今天的感受"), text: $log.note, axis: .vertical).lineLimit(3...8).accessibilityIdentifier("editorNote") }
                    if let error = error { Text(error).foregroundStyle(Design.primary) }
                    Button(L.t("保存记录")) { save() }.buttonStyle(PrimaryButtonStyle()).listRowBackground(Color.clear).accessibilityIdentifier("saveDay")
                    if model.log(on: day).hasRecord {
                        Section {
                            if model.data.settings.healthEnabled { Toggle(L.t("同时删除苹果健康里本 App 写入的这一天"), isOn: $deleteHealth).accessibilityIdentifier("deleteHealthToo") }
                            Button(L.t("删除这一天的记录"), role: .destructive) { model.deleteLog(day: day, deleteHealth: deleteHealth); dismiss() }.accessibilityIdentifier("deleteDay")
                        }
                    }
                }.disabled(day > model.today)
            }.scrollContentBackground(.hidden)
        }.onAppear {
            guard !loaded else { return }; loaded = true; log = model.log(on: day)
            temperature = log.bbt.map { String(format: "%.2f", Double($0) / 100) } ?? ""
        }.sheet(isPresented: $showPaywall) { PaywallView().environmentObject(model) }
    }
    private func toggle(_ key: String, symptoms: Bool) {
        if symptoms { if log.symptoms.contains(key) { log.symptoms.remove(key) } else { log.symptoms.insert(key) } }
        else { if log.moods.contains(key) { log.moods.remove(key) } else { log.moods.insert(key) } }
    }
    private func save() {
        if temperature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { log.bbt = nil }
        else {
            guard let n = Double(temperature.replacingOccurrences(of: ",", with: ".")), n.isFinite, (30...45).contains(n) else { error = L.t("请输入 30–45 °C 之间的体温。"); return }
            log.bbt = Int((n * 100).rounded())
        }
        log.note = String(log.note.prefix(4000)); model.update(log); dismiss()
    }
}

import SwiftUI
import LocalAuthentication
import UniformTypeIdentifiers

extension UTType { static let periodBackup = UTType(exportedAs: "com.hgsldswk.periodlog.backup", conformingTo: .json) }
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var deleteFirst = false
    @State private var deleteSecond = false
    @State private var showPaywall = false
    var body: some View {
        SheetFrame(title: L.t("设置")) {
            Form {
                if !Launch.isFree && !model.premium && !model.data.expiryNoticeShown {
                    Section {
                        Text(L.t("高级体验已结束。记录永远免费，已建吃药提醒照常。"))
                        Button(L.t("知道了")) { model.data.expiryNoticeShown = true; model.save() }.accessibilityIdentifier("dismissExpiry")
                    }
                }
                cycleSettings
                privacySettings
                storageSettings
                Section(L.t("分享")) {
                    Button(L.t("和闺蜜一起记")) { model.page = .shareFriend }.accessibilityIdentifier("settingsShareFriend")
                    Button(L.t("给伴侣")) { model.page = .sharePartner }.accessibilityIdentifier("settingsSharePartner")
                    Button(L.t("推荐给朋友")) { model.page = .invite }.accessibilityIdentifier("settingsInvite")
                }
                if !Launch.isFree {
                    Section(L.t("高级功能")) {
                        Button(L.t("一次买断")) { showPaywall = true }.accessibilityIdentifier("openPaywall")
                        Button(L.t("恢复购买")) { Task { await model.restorePurchases() } }.accessibilityIdentifier("settingsRestorePurchases")
                    }
                }
                Section(L.t("关于")) {
                    Text(L.t("预测仅供参考，不能用于避孕。"))
                    Text(L.t("数据只在你的手机，我们没有服务器。开启备份后，副本保存在你自己的 iCloud。"))
                    Text(L.t("无账号、无广告、不收集数据。"))
                    Text("1.0 (v1)").foregroundStyle(Design.secondary)
                }
                Section {
                    Button(L.t("删除全部数据"), role: .destructive) { deleteFirst = true }.accessibilityIdentifier("deleteAll")
                    Text(L.t("会删除本机记录、亲友、提醒和本 App 的 iCloud 备份。不会删除苹果健康中的记录。可先导出备份文件。")) .font(.caption).foregroundStyle(Design.secondary)
                }
            }.scrollContentBackground(.hidden)
        }.sheet(isPresented: $showPaywall) { PaywallView().environmentObject(model) }
            .alert(L.t("删除全部数据？"), isPresented: $deleteFirst) {
                Button(L.t("继续删除"), role: .destructive) { deleteSecond = true }
                Button(L.t("取消"), role: .cancel) {}
            } message: { Text(L.t("建议先导出备份文件。")) }
            .alert(L.t("最后确认：永久删除？"), isPresented: $deleteSecond) {
                Button(L.t("永久删除"), role: .destructive) { model.deleteAll() }
                Button(L.t("取消"), role: .cancel) {}
            }
    }
    private var cycleSettings: some View {
        Section(L.t("记录与预测")) {
            Picker(L.t("用途"), selection: Binding(get: { model.data.settings.purpose }, set: { purpose in
                model.data.settings.purpose = purpose
                if purpose == .conceive { model.data.reminders.fertile = true }
                model.save()
            })) { ForEach(Purpose.allCases, id: \.rawValue) { Text($0.title).tag($0) } }.accessibilityIdentifier("settingsPurpose")
            Stepper(L.f("默认周期 %@ 天", String(model.data.settings.cycleDays)), value: model.setting(\.cycleDays), in: 15...90).accessibilityIdentifier("defaultCycleDays")
            Stepper(L.f("默认经期 %@ 天", String(model.data.settings.periodDays)), value: model.setting(\.periodDays), in: 1...14).accessibilityIdentifier("defaultPeriodDays")
            Picker(L.t("暂停预测"), selection: Binding(get: { model.data.settings.pauseReason }, set: { value in
                if model.data.settings.pauseReason != nil && value == nil { model.data.settings.predictionRestart = model.today.adding(1) }
                model.data.settings.pauseReason = value; model.save()
            })) {
                Text(L.t("不暂停")).tag(PauseReason?.none)
                ForEach(PauseReason.allCases, id: \.rawValue) { Text($0.title).tag(Optional($0)) }
            }.accessibilityIdentifier("pausePredictions")
            if model.data.settings.predictionRestart != nil { Text(L.t("恢复预测后，会从下一次经期重新开始计算。")) .font(.caption).foregroundStyle(Design.secondary) }
            Toggle(L.t("只记录，不显示预测"), isOn: model.setting(\.recordOnly)).accessibilityIdentifier("recordOnly")
            Toggle(L.t("显示同房记录"), isOn: model.setting(\.showSex)).accessibilityIdentifier("showSex")
        }
    }
    private var privacySettings: some View {
        Section(L.t("提醒与隐私")) {
            NavigationLink(L.t("提醒")) { RemindersView().environmentObject(model) }.accessibilityIdentifier("openReminders")
            Toggle(L.t("隐晦通知文案"), isOn: model.setting(\.discreetNotifications)).accessibilityIdentifier("discreetNotifications")
            Toggle(L.t("面容 / 触控 / 密码锁"), isOn: Binding(get: { model.data.settings.faceLock }, set: { enabled in
                if enabled && !model.isolated {
                    var error: NSError?
                    guard LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { model.message = L.t("请先在系统设置中设置设备密码。") ; return }
                }
                model.data.settings.faceLock = enabled; model.save()
            })).accessibilityIdentifier("faceLock")
            Toggle(L.t("小组件隐晦样式"), isOn: model.setting(\.discreetWidget)).accessibilityIdentifier("discreetWidget")
            Button(L.t("使用中性日历图标")) { changeIcon("NeutralIcon") }.accessibilityIdentifier("neutralIcon")
            Button(L.t("恢复原图标")) { changeIcon(nil) }.accessibilityIdentifier("defaultIcon")
        }
    }
    private var storageSettings: some View {
        Section(L.t("数据与备份")) {
            Toggle(L.t("苹果健康同步"), isOn: Binding(get: { model.data.settings.healthEnabled }, set: { enabled in
                if enabled { Task { await model.importHealth() } } else { model.data.settings.healthEnabled = false; model.save() }
            })).accessibilityIdentifier("healthSync")
            Button(L.t("从苹果健康导入历史")) { Task { await model.importHealth() } }.accessibilityIdentifier("importHealth")
            Text(model.healthStatus.isEmpty ? L.t(model.data.settings.healthEnabled ? "读取权限由苹果健康保护；可以在系统设置中管理。" : "未授权；不给权限也能正常记录。") : model.healthStatus).font(.caption).foregroundStyle(Design.secondary)
            Toggle(L.t("iCloud 自动备份"), isOn: Binding(get: { model.data.settings.cloudEnabled }, set: { enabled in
                if enabled && !model.premium { showPaywall = true; return }
                model.data.settings.cloudEnabled = enabled; model.save()
            })).accessibilityIdentifier("cloudBackup")
            Text(L.t("默认关闭。开启后存在你自己的 iCloud，我们看不到。")) .font(.caption).foregroundStyle(Design.secondary)
            NavigationLink(L.t("导出 / 导入备份、CSV")) { BackupToolsView().environmentObject(model) }.accessibilityIdentifier("openBackupTools")
        }
    }
    private func changeIcon(_ name: String?) {
        if name != nil && !model.premium { showPaywall = true; return }
        guard !model.isolated, UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(name) { error in
            if error != nil { Task { @MainActor in model.message = L.t("图标暂时无法更换，请稍后重试。") } }
        }
    }
}
struct BackupToolsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var password = ""
    @State private var importPassword = ""
    @State private var importing = false
    @State private var exporting = false
    @State private var document = ExportDocument(Data())
    @State private var fileType = UTType.periodBackup
    @State private var filename = "PeriodLog"
    @State private var incomingBytes: Data?
    @State private var preview: Backup.Preview?
    @State private var error: String?
    var body: some View {
        Form {
            Section(L.t("导出")) {
                SecureField(L.t("备份密码（留空不加密）"), text: $password).accessibilityIdentifier("backupPassword")
                Text(L.t("请保管好密码，忘记后无法恢复加密备份。")) .font(.caption).foregroundStyle(Design.secondary)
                Button(L.t("导出备份文件")) { exportBackup() }.accessibilityIdentifier("exportBackup")
                Button(L.t("导出 CSV")) { document = ExportDocument(Backup.csv(model.data)); fileType = .commaSeparatedText; filename = "PeriodLog-" + model.today.description; exporting = true }.accessibilityIdentifier("exportCSV")
            }
            Section(L.t("导入")) {
                Button(L.t("选择备份文件")) { importing = true }.accessibilityIdentifier("chooseBackup")
                SecureField(L.t("导入密码（如有）"), text: $importPassword).accessibilityIdentifier("importPassword")
                if incomingBytes != nil { Button(L.t("读取预览")) { readPreview() }.accessibilityIdentifier("readBackupPreview") }
                if let preview = preview {
                    Text(L.f("将导入 %@ 天记录", String(preview.count))).font(.headline)
                    if let start = preview.start, let end = preview.end { Text(L.range(start, end)) }
                    Text(L.t("导入会合并记录，同一天以导入文件为准。本机为空时还会恢复设置与提醒；购买、锁和系统权限不会被覆盖。")) .font(.caption)
                    Button(L.t("确认合并导入")) { confirm(preview) }.accessibilityIdentifier("confirmBackupImport")
                }
                if let error = error { Text(error).font(.caption).foregroundStyle(Design.primary) }
            }
        }.scrollContentBackground(.hidden).background(Design.background).navigationTitle(L.t("备份与导出"))
            .fileExporter(isPresented: $exporting, document: document, contentType: fileType, defaultFilename: filename) { result in if case .failure = result { error = L.t("导出未完成，请重新选择保存位置。") } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.periodBackup, .json, .data]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    incomingBytes = try Backup.readFile(url); readPreview()
                } catch { self.error = L.t("无法读取文件，请选择有效的经期备份。") }
            }
    }
    private func exportBackup() {
        do { document = ExportDocument(try Backup.export(model.data, password: password)); fileType = .periodBackup; filename = "PeriodLog-" + model.today.description; exporting = true }
        catch { self.error = L.t("导出失败，请检查剩余空间。") }
    }
    private func readPreview() {
        guard let bytes = incomingBytes else { return }
        do { preview = try Backup.preview(bytes, password: importPassword); error = nil }
        catch DataError.wrongPassword { preview = nil; error = L.t("密码不正确，或文件已损坏。") }
        catch { preview = nil; self.error = L.t("无法读取这个备份，文件可能已损坏或版本不支持。") }
    }
    private func confirm(_ preview: Backup.Preview) {
        if model.loadFailed && !model.isolated {
            do { try FileManager.default.copyItem(at: model.store.url, to: model.store.url.deletingLastPathComponent().appendingPathComponent("unreadable-" + UUID().uuidString + ".json")) }
            catch { self.error = L.t("未能保留原文件，暂未导入。") ; return }
        }
        model.loadFailed = false; model.data.mergeBackup(preview.data); model.save()
        self.preview = nil; incomingBytes = nil; error = L.t("备份已合并导入。")
    }
}

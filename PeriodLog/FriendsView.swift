import SwiftUI

struct FriendsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        SheetFrame(title: L.t("亲友")) {
            List {
                if model.data.friends.isEmpty { Text(L.t("添加对方的口令，就能在这里看到大约日期。")) .foregroundStyle(Design.secondary) }
                ForEach(model.data.friends) { friend in
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(friend.nickname).font(.headline); Text(L.t(friend.kind == .partner ? "伴侣" : "朋友")).font(.caption).foregroundStyle(Design.secondary) }
                            if let next = friend.next(on: model.today) { Text(L.f("下次大约 %@", L.range(next.rangeStart, next.rangeEnd))).font(.subheadline) }
                            if friend.isStale(on: model.today) { Text(L.t("这份口令比较旧了，可以请对方重新发一份。")) .font(.caption).foregroundStyle(Design.primary) }
                            Text(L.f("生成于 %@", L.day(friend.generated))).font(.caption2).foregroundStyle(Design.secondary)
                            if friend.partnerTips { Text(L.t("这几天可能比较累，多一点耐心。")) .font(.caption).foregroundStyle(Design.secondary) }
                        }.accessibilityIdentifier("friend-" + friend.sourceID.uuidString)
                        Toggle(L.t("经期前提醒我"), isOn: Binding(get: { friend.remindDaysBefore != nil }, set: { enabled in edit(friend.id) { $0.remindDaysBefore = enabled ? 1 : nil }; if enabled { Task { await model.askNotifications() } } })).accessibilityIdentifier("friendReminder-" + friend.id.uuidString)
                        if let days = friend.remindDaysBefore {
                            Stepper(L.f("提前 %@ 天", String(days)), value: Binding(get: { days }, set: { days in edit(friend.id) { $0.remindDaysBefore = days } }), in: 0...7).accessibilityIdentifier("friendReminderDays-" + friend.id.uuidString)
                        }
                        Button(L.t("删除"), role: .destructive) { model.data.friends.removeAll { $0.id == friend.id }; model.save() }.accessibilityIdentifier("deleteFriend-" + friend.id.uuidString)
                    }
                }
                Section {
                    Button(L.t("和闺蜜一起记")) { model.page = .shareFriend }.accessibilityIdentifier("shareFriend")
                    Button(L.t("给伴侣")) { model.page = .sharePartner }.accessibilityIdentifier("sharePartner")
                    PasteButton(payloadType: String.self) { strings in if let text = strings.first { model.receiveCode(text) } }.accessibilityIdentifier("pasteFriendCode")
                }
                if model.notificationDenied { Link(L.t("通知未开启 · 去设置"), destination: URL(string: UIApplication.openSettingsURLString)!) }
            }.scrollContentBackground(.hidden)
        }
    }
    private func edit(_ id: UUID, _ change: (inout Friend) -> Void) {
        guard let index = model.data.friends.firstIndex(where: { $0.id == id }) else { return }
        change(&model.data.friends[index]); model.save()
    }
}
struct ImportCodeView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        SheetFrame(title: L.t("添加亲友")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let p = model.incoming {
                        if model.importedFriendID != nil {
                            Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(Design.primary)
                            Text(L.t("已添加到亲友")).font(.title2.bold()).accessibilityIdentifier("friendImported")
                            if p.wantsReply { Button(L.t("把我的也发给对方？")) { model.page = p.kind == .partner ? .sharePartner : .shareFriend }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("returnMyCode") }
                            Button(L.t("查看亲友")) { model.page = .friends }.accessibilityIdentifier("viewImportedFriend")
                        } else {
                            Text(p.nickname ?? L.t("朋友")).font(.title.bold()).accessibilityIdentifier("incomingNickname")
                            Text(L.f("生成于 %@", L.day(p.generated))).font(.caption).foregroundStyle(Design.secondary)
                            ForEach(p.predictions) { f in Text(L.f("下次大约 %@", L.range(f.rangeStart, f.rangeEnd))).card() }
                            Text(L.t("只添加大约日期，不会导入对方的历史健康记录。")) .font(.subheadline).foregroundStyle(Design.secondary)
                            if p.sourceID == model.data.settings.sourceID { Text(L.t("这是你自己的口令，可以把它发给朋友。")) .foregroundStyle(Design.primary).accessibilityIdentifier("ownCodeNotice") }
                            else {
                                if p.predictions.last.map({ $0.rangeEnd < model.today }) == true { Text(L.t("这份口令比较旧了，可以请对方重新发一份。")) }
                                Button(L.t("确认添加")) { model.confirmIncoming() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("confirmImportCode")
                            }
                        }
                    } else {
                        Text(L.t("请粘贴对方的完整口令。"))
                        PasteButton(payloadType: String.self) { if let text = $0.first { model.receiveCode(text) } }.accessibilityIdentifier("pasteImportCode")
                    }
                }.padding(20)
            }
        }
    }
}

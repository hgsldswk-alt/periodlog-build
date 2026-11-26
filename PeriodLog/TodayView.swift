import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var feedback = 0
    private var cycleDay: Int { CycleCore.cycleDay(logs: model.data.logs, on: model.selectedDay) ?? 1 }
    private var selectedPhase: CyclePhase { CycleCore.phase(logs: model.data.logs, settings: model.data.settings, on: model.selectedDay, prediction: model.prediction) }
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                week
                if model.pasteAvailable { pasteHint }
                ringCard
                Button(L.t(model.phase == .period ? "经期结束了" : "经期开始了")) { model.page = .start }
                    .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("periodAction")
                quickRecords
                notices
                Disclaimer()
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
        }.background(Design.background).sensoryFeedback(.selection, trigger: feedback)
            .onChange(of: model.pendingMilestone, initial: true) { _, milestone in
                if let milestone = milestone { model.considerReview(matched: false, milestone: milestone) }
            }
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(L.day(model.selectedDay, weekday: true)).font(.caption).foregroundStyle(Design.secondary)
                Text(L.t(model.selectedDay == model.today ? "今天" : "这一天")).font(.system(size: 28, weight: .bold)).foregroundStyle(Design.ink)
            }
            Spacer()
            circleButton("person.2", title: L.t("亲友"), id: "openFriends") { model.page = .friends }
            circleButton("gearshape", title: L.t("设置"), id: "openSettings") { model.page = .settings }
        }
    }
    private func circleButton(_ image: String, title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: image).font(.system(size: 18, weight: .regular)).frame(width: 40, height: 40).foregroundStyle(Design.ink).background(Design.card, in: Circle()).overlay(Circle().stroke(Design.line, lineWidth: 1)) }.accessibilityLabel(title).accessibilityIdentifier(id)
    }
    private var week: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroll in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(-28..<8, id: \.self) { offset in
                            let day = model.today.adding(offset)
                            Button {
                                model.selectedDay = day; feedback += 1
                            } label: {
                                VStack(spacing: 5) {
                                    Text(day.localDate().formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(Design.tertiary)
                                    Text(String(day.day)).font(.subheadline.weight(.medium)).frame(width: 34, height: 34).foregroundStyle(day == model.today ? Design.card : Design.ink).background(day == model.today ? Design.ink : (day == model.selectedDay ? Design.faint : Color.clear), in: Circle())
                                    Circle().fill(model.log(on: day).hasRecord ? Design.primary : .clear).frame(width: 4, height: 4)
                                }.frame(width: proxy.size.width / 7)
                            }.buttonStyle(.plain).id(offset).accessibilityIdentifier("week-" + day.description).accessibilityLabel(L.day(day, weekday: true))
                        }
                    }
                }.onAppear { scroll.scrollTo(0, anchor: .trailing) }
            }
        }.frame(height: 68)
    }
    private var ringCard: some View {
        VStack(spacing: 10) {
            if typeSize.isAccessibilitySize {
                ring.frame(width: 180, height: 180)
                ringText
            } else {
                ZStack { ring; ringText.padding(25) }.frame(width: 214, height: 214)
            }
            if let p = model.prediction {
                Text(L.f("预计 %@", L.range(p.rangeStart, p.rangeEnd))).font(.subheadline).foregroundStyle(Design.primary).padding(.horizontal, 14).padding(.vertical, 7).background(Design.faint, in: Capsule()).accessibilityIdentifier("predictionRange")
            }
            Legend().padding(.top, 3)
        }.frame(maxWidth: .infinity).padding(.vertical, 14).background(Design.card, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(Design.line, lineWidth: 1))
    }
    private var ring: some View {
        CycleRing(cycleDays: model.prediction?.cycleDays ?? model.data.settings.cycleDays, periodDays: model.prediction?.periodDays ?? model.data.settings.periodDays, currentDay: cycleDay, ovulationDay: model.prediction.map { $0.cycleDays - 14 } ?? 14)
    }
    @ViewBuilder private var ringText: some View {
        VStack(spacing: 3) {
            if model.data.settings.pauseReason != nil || model.data.settings.recordOnly {
                Image(systemName: "pause.circle").font(.title).foregroundStyle(Design.primary)
                Text(L.t("已暂停预测")).font(.headline)
            } else if selectedPhase == .period {
                Text(L.t("经期中")).font(.caption).foregroundStyle(Design.secondary)
                let start = model.data.settings.openPeriodStart ?? model.periods.last(where: { $0.start <= model.selectedDay })?.start ?? model.selectedDay
                Text(L.f("%@ 天", String(max(1, start.distance(to: model.selectedDay) + 1)))).font(.system(size: 48, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6)
                    .accessibilityIdentifier("periodDay")
            } else if let p = model.prediction {
                Text(L.f("周期第 %@ 天", String(cycleDay))).font(.caption).foregroundStyle(Design.secondary)
                Text(L.f("%@ 天", String(p.isLate ? p.lateDays : max(0, model.selectedDay.distance(to: p.nextStart))))).font(.system(size: 54, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6).accessibilityIdentifier("countdown")
                Text(L.t(p.isLate ? "比预计晚了" : "后预计来经期")).font(.subheadline).foregroundStyle(Design.secondary)
            } else {
                Image(systemName: "circle.dotted").font(.title).foregroundStyle(Design.primary)
                Text(L.t("从一笔记录开始")).font(.headline).multilineTextAlignment(.center)
                Text(L.t("记录越多，预测越有参考价值。")).font(.caption).foregroundStyle(Design.secondary).multilineTextAlignment(.center)
            }
        }.foregroundStyle(Design.ink).accessibilityElement(children: .contain)
    }
    private var quickRecords: some View {
        VStack(spacing: 8) {
            HStack {
                Text(L.t(model.selectedDay == model.today ? "今天的记录" : "这一天的记录")).font(.caption).foregroundStyle(Design.secondary)
                Spacer()
                Button(L.t("更多 ›")) { model.page = .day }.font(.caption).accessibilityIdentifier("openDay")
            }
            VStack(spacing: 8) {
                quickRow(L.t("流量")) {
                    ForEach(Flow.allCases, id: \.rawValue) { flow in
                        Chip(title: flow.title, selected: model.log(on: model.selectedDay).flow == flow, id: "quick-flow-" + flow.rawValue) {
                            var log = model.log(on: model.selectedDay); log.flow = flow; model.update(log); feedback += 1
                        }
                    }
                }
                quickRow(L.t("身体")) {
                    ForEach(["lowerBackPain", "breastPain", "fatigue"], id: \.self) { key in
                        Chip(title: RecordOptions.title(key), selected: model.log(on: model.selectedDay).symptoms.contains(key), id: "quick-symptom-" + key) { toggleSymptom(key) }
                    }
                    Chip(title: "+", selected: false, id: "moreSymptoms") { model.page = .day }
                }
                quickRow(L.t("心情")) {
                    ForEach(["calm", "low", "irritable"], id: \.self) { key in
                        Chip(title: RecordOptions.title(key), selected: model.log(on: model.selectedDay).moods.contains(key), id: "quick-mood-" + key) {
                            var log = model.log(on: model.selectedDay)
                            if log.moods.contains(key) { log.moods.remove(key) } else { log.moods.insert(key) }; model.update(log); feedback += 1
                        }
                    }
                    Chip(title: "+", selected: false, id: "moreMoods") { model.page = .day }
                }
                if model.data.settings.purpose == .conceive {
                    Button { model.page = .day } label: {
                        HStack { Text(L.t("体温 / 试纸")); Spacer(); Text(model.log(on: model.selectedDay).bbt.map { String(format: "%.2f °C", Double($0) / 100) } ?? L.t("记录")); Image(systemName: "chevron.right") }.font(.subheadline)
                    }.accessibilityIdentifier("quickFertility")
                }
                if model.data.reminders.pill {
                    Button {
                        var l = model.log(on: model.selectedDay); l.pillTaken = !(l.pillTaken ?? false); model.update(l)
                    } label: { Label(L.t(model.log(on: model.selectedDay).pillTaken == true ? "已记录吃药" : "记录已吃药"), systemImage: model.log(on: model.selectedDay).pillTaken == true ? "checkmark.circle.fill" : "circle").font(.subheadline) }.accessibilityIdentifier("quickPill")
                    if model.selectedDay == model.today,
                       model.data.reminders.pillMode.isActive(offset: model.data.reminders.pillStart.distance(to: model.today)),
                       model.now > model.today.localDate(hour: model.data.reminders.pillHour, minute: model.data.reminders.pillMinute).addingTimeInterval(7200),
                       model.log(on: model.today).pillTaken != true {
                        Text(L.t("还没有记录已吃，记得看看。")).font(.caption).foregroundStyle(Design.secondary)
                    }
                }
            }.padding(12).background(Design.card, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(Design.line, lineWidth: 1)).disabled(model.selectedDay > model.today)
        }
    }
    private func quickRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(Design.ink).frame(minWidth: 36, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { content() } }
        }
    }
    private func toggleSymptom(_ key: String) {
        var log = model.log(on: model.selectedDay)
        if log.symptoms.contains(key) { log.symptoms.remove(key) } else { log.symptoms.insert(key) }; model.update(log); feedback += 1
    }
    private var pasteHint: some View {
        HStack {
            Text(L.t("剪贴板里有亲友口令？")).font(.caption)
            Spacer()
            PasteButton(payloadType: String.self) { strings in if let text = strings.first { model.receiveCode(text) } }.labelStyle(.iconOnly).accessibilityIdentifier("pasteHome")
            Button { model.pasteAvailable = false } label: { Image(systemName: "xmark") }.accessibilityLabel(L.t("关闭")).accessibilityIdentifier("dismissPaste")
        }.padding(12).background(Design.faint, in: RoundedRectangle(cornerRadius: 14))
    }
    @ViewBuilder private var notices: some View {
        if model.loadFailed { Text(L.t("原文件已保留。请先恢复备份，避免覆盖。")) .font(.caption).card() }
        if let period = model.periods.last(where: \.needsConfirmation) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L.t("这是新的经期，还是上次的延续？"))
                HStack {
                    Button(L.t("新的经期")) { model.confirmPeriod(period, continuation: false) }.accessibilityIdentifier("confirmNewPeriod")
                    Button(L.t("上次的延续")) { model.confirmPeriod(period, continuation: true) }.accessibilityIdentifier("confirmContinuation")
                }.font(.subheadline)
            }.card()
        }
        if let p = model.prediction {
            if p.regularity == .irregular { Text(L.t("最近几次周期长短不一，预测范围较宽。")) .font(.caption).foregroundStyle(Design.secondary).card() }
            if p.isLate {
                Text(L.f("比预计晚了 %@ 天", String(p.lateDays))).font(.subheadline)
                Button(L.t("记一次验孕结果")) { model.selectedDay = model.today; model.page = .day }.accessibilityIdentifier("recordPregnancyTest")
                if let last = model.periods.last, last.start.distance(to: model.today) > 60 { Text(L.t("如果一直没来，可以多留意一下自己的状态。")) .font(.caption).foregroundStyle(Design.secondary) }
            }
            let accuracyKey = "accuracy-" + (model.periods.last?.start.description ?? "")
            if p.matchedLastPeriod && !model.data.settings.dismissedCards.contains(accuracyKey) {
                notice(L.t("这次和预测相符"), id: accuracyKey, button: nil, action: {})
            }
            if !model.data.settings.dismissedCards.contains("invite") {
                notice(L.t("觉得好用，可以推荐给朋友"), id: "invite", button: L.t("推荐给朋友")) { model.page = .invite }
            }
        }
        if let m = model.pendingMilestone, !model.data.milestones.contains(m) {
            notice(L.f("已经连续记录 %@ 个周期", String(m)), id: "milestone", button: L.t("分享纪念卡")) { model.showMilestone() }
        }
        if model.cloudRestore != nil {
            notice(L.t("发现 iCloud 里的备份，恢复？"), id: "cloud", button: L.t("恢复")) { model.restoreCloud() }
        }
        if model.data.settings.purpose == .conceive, let p = model.prediction {
            VStack(alignment: .leading, spacing: 6) {
                Text(L.f("预计易孕期 %@", L.range(p.fertileStart, p.fertileEnd)))
                Text(L.f("预计排卵 %@", L.day(p.ovulation)))
                if CycleCore.temperatureRaised(model.data.logs, today: model.today) { Text(L.t("体温已升高")) }
            }.font(.caption).foregroundStyle(Design.secondary).frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }
    private func notice(_ title: String, id: String, button: String?, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.subheadline)
                if let button = button { Button(button, action: action).font(.caption).accessibilityIdentifier("cardAction-" + id) }
            }
            Spacer()
            Button {
                if id == "milestone", let m = model.pendingMilestone { model.data.milestones.insert(m); model.save() }
                else { model.dismissCard(id) }
            } label: { Image(systemName: "xmark").font(.caption).foregroundStyle(Design.tertiary) }.accessibilityLabel(L.t("关闭")).accessibilityIdentifier("dismissCard-" + id)
        }.card()
    }
}

struct PeriodDateView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var ending = false
    var body: some View {
        SheetFrame(title: L.t(ending ? "经期结束了" : "经期开始了")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L.t(ending ? "最后一天是哪天？" : "是哪天开始的？")).font(.title2.bold())
                    DatePicker(L.t("日期"), selection: $date, in: ...model.today.localDate(hour: 23), displayedComponents: .date).datePickerStyle(.graphical).accessibilityIdentifier("periodDate")
                    if !ending { Button(L.t("是前几天开始的")) { date = model.today.adding(-2).localDate() }.accessibilityIdentifier("earlierStart") }
                    Button(L.t("保存")) {
                        if ending { model.endPeriod(on: Day(date: date)) } else { model.beginPeriod(on: Day(date: date)) }; dismiss()
                    }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("savePeriodDate")
                }.padding(20)
            }
        }.onAppear { ending = model.phase == .period; date = model.today.localDate() }
    }
}

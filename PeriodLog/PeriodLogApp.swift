import SwiftUI
import StoreKit

@main struct PeriodLogApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var lock = LockManager()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).environmentObject(lock)
                .modifier(ScreenshotFontSize())
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-dark") ? .dark : nil)
                .task {
                    if model.data.settings.faceLock && !model.isolated { lock.locked = true; await lock.unlock() }
                    await model.startServices()
                }
                .task {
                    while !Task.isCancelled {
                        do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
                        model.refreshClock()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    lock.transition(phase, enabled: model.data.settings.faceLock && !model.isolated)
                    if phase == .active { Task { await model.becomeActive() } }
                }
        }
    }
}
struct ScreenshotFontSize: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if ProcessInfo.processInfo.arguments.contains("-bigtext") { content.dynamicTypeSize(.accessibility5) }
        else { content }
    }
}
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var lock: LockManager
    @Environment(\.requestReview) private var requestReview
    var body: some View {
        ZStack {
            TabView(selection: $model.tab) {
                TodayView().tabItem { Label(L.t("今天"), systemImage: "circle.inset.filled") }.tag(0).accessibilityIdentifier("tabToday")
                CalendarView().tabItem { Label(L.t("日历"), systemImage: "calendar") }.tag(1).accessibilityIdentifier("tabCalendar")
                StatsView().tabItem { Label(L.t("统计"), systemImage: "chart.bar") }.tag(2).accessibilityIdentifier("tabStats")
            }.tint(Design.primary).blur(radius: lock.covered ? 20 : 0).allowsHitTesting(!lock.locked && !lock.covered)
            if lock.covered || lock.locked {
                Design.background.ignoresSafeArea()
                VStack(spacing: 24) {
                    Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(Design.primary)
                    if lock.locked {
                        Button(L.t("解锁")) { Task { await lock.unlock() } }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("unlock")
                        if lock.failure { Text(L.t("未能解锁，请使用系统密码或重新验证。")) }
                    }
                }.padding(40)
            }
        }.background(Design.background)
            .sheet(item: $model.page) { page in
                PageView(page: page).environmentObject(model).privacySensitive()
                    .overlay { PrivacyShield() }
                    .interactiveDismissDisabled(page == .onboarding && !model.data.onboardingComplete)
                    .alert(L.t("提示"), isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
                        Button(L.t("知道了"), role: .cancel) { model.message = nil }
                    } message: { Text(model.message ?? "") }
            }
            .alert(L.t("提示"), isPresented: Binding(get: { model.message != nil && model.page == nil }, set: { if !$0 { model.message = nil } })) {
                Button(L.t("知道了"), role: .cancel) { model.message = nil }
            } message: { Text(model.message ?? "") }
            .reviewAfterCoreAction(when: reviewHome) { requestReview() }
            .task(id: reviewHome && model.reviewCondition != nil) {
                guard reviewHome, model.reviewCondition != nil else { return }
                do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
                guard !Task.isCancelled, reviewHome else { return }
                model.requestMilestoneReview { requestReview() }
            }
    }

    private var reviewHome: Bool {
        !model.isolated && !model.loadFailed && model.data.onboardingComplete
            && !lock.locked && !lock.covered && model.page == nil && model.message == nil && !model.purchasing
    }
}
struct PageView: View {
    let page: Page
    @EnvironmentObject private var model: AppModel
    var body: some View {
        switch page {
        case .day: DayEditor(day: model.selectedDay)
        case .start: PeriodDateView()
        case .friends: FriendsView()
        case .shareFriend: ShareSheetView(kind: .friend)
        case .sharePartner: ShareSheetView(kind: .partner)
        case .invite: InviteCardView()
        case .milestone: MilestoneCardView(count: model.pendingMilestone ?? 3)
        case .importCode: ImportCodeView()
        case .settings: SettingsView()
        case .paywall: PaywallView()
        case .onboarding: OnboardingView()
        case .reminders: SheetFrame(title: L.t("提醒")) { RemindersView() }
        case .backup: SheetFrame(title: L.t("备份与导出")) { BackupToolsView() }
        }
    }
}

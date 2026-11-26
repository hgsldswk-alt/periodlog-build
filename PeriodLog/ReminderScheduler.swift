import Foundation
import UserNotifications

@MainActor final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    var onAction: ((String, Day) async -> Void)?
    private let center = UNUserNotificationCenter.current()
    private var queue: Task<Void, Never>?
    func register() {
        center.delegate = self
        let start = UNNotificationAction(identifier: "PERIOD_STARTED", title: L.t("开始了"), options: [.foreground, .authenticationRequired])
        let no = UNNotificationAction(identifier: "PERIOD_NOT_YET", title: L.t("还没"), options: [.authenticationRequired])
        let pill = UNNotificationAction(identifier: "PILL_TAKEN", title: L.t("已吃"), options: [.authenticationRequired])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "PERIOD_CHECK", actions: [start, no], intentIdentifiers: []),
            UNNotificationCategory(identifier: "PILL", actions: [pill], intentIdentifiers: [])
        ])
    }
    func denied() async -> Bool { await center.notificationSettings().authorizationStatus == .denied }
    func request() async { _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge]); register() }
    func cancelAll() {
        let previous = queue
        queue = Task {
            await previous?.value
            center.removeAllPendingNotificationRequests(); center.removeAllDeliveredNotifications()
        }
    }
    func cancelPill(on day: Day) {
        let ids = ["pill-" + day.description, "pill-followup-" + day.description]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
    func reschedule(data: AppData, now: Date) async {
        let previous = queue
        let task = Task {
            await previous?.value
            await performReschedule(data: data, now: now)
        }
        queue = task
        await task.value
    }
    private func performReschedule(data: AppData, now: Date) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        center.removeAllPendingNotificationRequests()
        for plan in ReminderPlan.make(data: data, now: now) {
            guard !Task.isCancelled else { return }
            let c = UNMutableNotificationContent(); c.title = plan.title; c.body = plan.body; c.sound = .default
            c.categoryIdentifier = plan.category; c.userInfo = ["day": plan.day.description]
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: plan.id, content: c, trigger: trigger))
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let day = (response.notification.request.content.userInfo["day"] as? String).flatMap(Day.init) ?? Day()
        Task { @MainActor in await onAction?(action, day); completionHandler() }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
}

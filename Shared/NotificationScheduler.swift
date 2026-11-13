import Foundation
import UserNotifications

enum NotificationScheduler {
    static let completeAction = "DONCHECK_COMPLETE"
    static let category = "DONCHECK_ITEM"

    static func registerCategories() {
        let complete = UNNotificationAction(
            identifier: completeAction,
            title: "입금 완료",
            options: []
        )
        let notificationCategory = UNNotificationCategory(
            identifier: category,
            actions: [complete],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([notificationCategory])
    }

    static func requestAuthorization() async -> Bool {
        registerCategories()
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func rescheduleAll(_ data: ChecklistData, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        let ownIDs = existing.map(\.identifier).filter { $0.hasPrefix(AppConfig.notificationPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ownIDs)

        let calendar = Calendar.current
        let currentKey = CycleDate.key(for: now, calendar: calendar)
        var candidates: [(Date, UNNotificationRequest)] = []

        for item in data.items {
            if !data.isComplete(item.id, cycleKey: currentKey) {
                candidates += requests(for: item, month: now, includeFollowUps: true, now: now, calendar: calendar)
            }

            let nextMonth = CycleDate.offset(1, from: now, calendar: calendar)
            let nextKey = CycleDate.key(for: nextMonth, calendar: calendar)
            if !data.isComplete(item.id, cycleKey: nextKey) {
                candidates += requests(for: item, month: nextMonth, includeFollowUps: false, now: now, calendar: calendar)
            }
        }

        // iOS retains a limited number of pending local alerts. Keep the nearest ones.
        for (_, request) in candidates.sorted(by: { $0.0 < $1.0 }).prefix(60) {
            try? await center.add(request)
        }

        let key = CycleDate.key(for: now)
        let remaining = data.items.filter { !data.isComplete($0.id, cycleKey: key) }.count
        try? await center.setBadgeCount(remaining)
    }

    static func cancel(itemID: UUID, cycleKey: String) async {
        let center = UNUserNotificationCenter.current()
        let prefix = identifierPrefix(itemID: itemID, cycleKey: cycleKey)
        let pending = await center.pendingNotificationRequests()
        let pendingIDs = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        let delivered = await center.deliveredNotifications()
        let deliveredIDs = delivered.map { $0.request.identifier }.filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
    }

    private static func requests(
        for item: SavingsItem,
        month: Date,
        includeFollowUps: Bool,
        now: Date,
        calendar: Calendar
    ) -> [(Date, UNNotificationRequest)] {
        let due = CycleDate.dueDate(for: item, monthContaining: month, calendar: calendar)
        let key = CycleDate.key(for: month, calendar: calendar)
        var dates: [(String, Date, String)] = []

        if item.leadDays > 0,
           let early = calendar.date(byAdding: .day, value: -item.leadDays, to: due) {
            dates.append(("early", early, "출금 전에 입금할 때예요"))
        }
        dates.append(("due", due, "오늘 출금 예정이에요"))

        if includeFollowUps && item.followUpCount > 0 {
            for day in 1...item.followUpCount {
                if let followUp = calendar.date(byAdding: .day, value: day, to: due) {
                    dates.append(("followup-\(day)", followUp, "아직 완료하지 않은 저축 항목이에요"))
                }
            }
        }

        return dates.compactMap { kind, date, body in
            guard date > now else { return nil }
            let content = UNMutableNotificationContent()
            content.title = item.name
            content.body = body
            content.sound = .default
            content.categoryIdentifier = category
            content.threadIdentifier = item.id.uuidString
            content.interruptionLevel = kind == "early" ? .active : .timeSensitive
            content.userInfo = ["itemID": item.id.uuidString, "cycleKey": key]

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifierPrefix(itemID: item.id, cycleKey: key) + kind,
                content: content,
                trigger: trigger
            )
            return (date, request)
        }
    }

    private static func identifierPrefix(itemID: UUID, cycleKey: String) -> String {
        "\(AppConfig.notificationPrefix)\(itemID.uuidString).\(cycleKey)."
    }
}

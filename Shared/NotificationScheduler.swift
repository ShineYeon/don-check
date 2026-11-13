import Foundation
import UserNotifications

enum NotificationScheduler {
    static let depositCompleteAction = "DONCHECK_DEPOSIT_COMPLETE"
    static let automaticTransferCompleteAction = "DONCHECK_TRANSFER_COMPLETE"
    static let depositCategory = "DONCHECK_DEPOSIT_ITEM"
    static let automaticTransferCategory = "DONCHECK_TRANSFER_ITEM"
    static let legacyCompleteAction = "DONCHECK_COMPLETE"
    static let legacyCategory = "DONCHECK_ITEM"

    static func registerCategories() {
        let depositComplete = UNNotificationAction(
            identifier: depositCompleteAction,
            title: "입금 완료",
            options: []
        )
        let automaticTransferComplete = UNNotificationAction(
            identifier: automaticTransferCompleteAction,
            title: "저축 완료",
            options: []
        )
        let legacyComplete = UNNotificationAction(
            identifier: legacyCompleteAction,
            title: "입금 완료",
            options: []
        )
        let depositNotificationCategory = UNNotificationCategory(
            identifier: depositCategory,
            actions: [depositComplete],
            intentIdentifiers: [],
            options: []
        )
        let automaticTransferNotificationCategory = UNNotificationCategory(
            identifier: automaticTransferCategory,
            actions: [automaticTransferComplete],
            intentIdentifiers: [],
            options: []
        )
        let legacyNotificationCategory = UNNotificationCategory(
            identifier: legacyCategory,
            actions: [legacyComplete],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([
            depositNotificationCategory,
            automaticTransferNotificationCategory,
            legacyNotificationCategory
        ])
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
        let currentCycleStart = CycleDate.start(for: now, payday: data.payday, calendar: calendar)
        let nextCycleStart = CycleDate.nextBoundary(after: now, payday: data.payday, calendar: calendar)
        var candidates: [(Date, UNNotificationRequest)] = []

        for item in data.items {
            let currentDue = CycleDate.dueDate(
                for: item,
                cycleStarting: currentCycleStart,
                calendar: calendar
            )
            let currentKey = data.cycleKey(for: currentDue, calendar: calendar)
            if !data.isStepComplete(item.id, cycleKey: currentKey, step: .deposit) {
                candidates += requests(
                    for: item,
                    due: currentDue,
                    payday: data.payday,
                    step: .deposit,
                    includeFollowUps: true,
                    now: now,
                    calendar: calendar
                )
            }
            if item.requiresAutomaticTransferConfirmation,
               !data.isStepComplete(item.id, cycleKey: currentKey, step: .automaticTransfer) {
                candidates += requests(
                    for: item,
                    due: currentDue,
                    payday: data.payday,
                    step: .automaticTransfer,
                    includeFollowUps: true,
                    now: now,
                    calendar: calendar
                )
            }

            let nextDue = CycleDate.dueDate(
                for: item,
                cycleStarting: nextCycleStart,
                calendar: calendar
            )
            let nextKey = data.cycleKey(for: nextDue, calendar: calendar)
            if !data.isStepComplete(item.id, cycleKey: nextKey, step: .deposit) {
                candidates += requests(
                    for: item,
                    due: nextDue,
                    payday: data.payday,
                    step: .deposit,
                    includeFollowUps: false,
                    now: now,
                    calendar: calendar
                )
            }
            if item.requiresAutomaticTransferConfirmation,
               !data.isStepComplete(item.id, cycleKey: nextKey, step: .automaticTransfer) {
                candidates += requests(
                    for: item,
                    due: nextDue,
                    payday: data.payday,
                    step: .automaticTransfer,
                    includeFollowUps: false,
                    now: now,
                    calendar: calendar
                )
            }
        }

        // iOS retains a limited number of pending local alerts. Keep the nearest ones.
        for (_, request) in candidates.sorted(by: { $0.0 < $1.0 }).prefix(60) {
            try? await center.add(request)
        }

        let key = data.cycleKey(for: now)
        let remaining = data.items.filter { !data.isComplete($0.id, cycleKey: key) }.count
        try? await center.setBadgeCount(remaining)
    }

    static func cancel(itemID: UUID, cycleKey: String, step: CompletionStep) async {
        let center = UNUserNotificationCenter.current()
        let prefix = identifierPrefix(itemID: itemID, cycleKey: cycleKey, step: step)
        let pending = await center.pendingNotificationRequests()
        let pendingIDs = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        let delivered = await center.deliveredNotifications()
        let deliveredIDs = delivered.compactMap { notification -> String? in
            let request = notification.request
            if request.identifier.hasPrefix(prefix) {
                return request.identifier
            }
            let rawStep = request.content.userInfo["step"] as? String
            if step == .deposit,
               rawStep == nil,
               request.identifier.hasPrefix(itemCyclePrefix(itemID: itemID, cycleKey: cycleKey)) {
                return request.identifier
            }
            return nil
        }
        center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
    }

    static func removeAllDeliveredNotifications() async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let ownIDs = delivered
            .map { $0.request.identifier }
            .filter { $0.hasPrefix(AppConfig.notificationPrefix) }
        center.removeDeliveredNotifications(withIdentifiers: ownIDs)
    }

    private static func requests(
        for item: SavingsItem,
        due: Date,
        payday: Int,
        step: CompletionStep,
        includeFollowUps: Bool,
        now: Date,
        calendar: Calendar
    ) -> [(Date, UNNotificationRequest)] {
        let key = CycleDate.key(for: due, payday: payday, calendar: calendar)
        var dates: [(String, Date, String)] = []

        if step == .deposit,
           item.leadDays > 0,
           let early = calendar.date(byAdding: .day, value: -item.leadDays, to: due) {
            dates.append(("early", early, "출금 전에 입금할 때예요"))
        }
        let dueBody = step == .deposit
            ? "자동이체 계좌의 입금을 확인하세요"
            : "자동이체가 완료됐는지 확인하세요"
        dates.append(("due", due, dueBody))

        if includeFollowUps && item.followUpCount > 0 {
            for day in 1...item.followUpCount {
                if let followUp = calendar.date(byAdding: .day, value: day, to: due) {
                    let body = step == .deposit
                        ? "아직 입금 완료하지 않은 항목이에요"
                        : "아직 저축 완료를 확인하지 않은 항목이에요"
                    dates.append(("followup-\(day)", followUp, body))
                }
            }
        }

        return dates.compactMap { kind, date, body in
            guard date > now else { return nil }
            let content = UNMutableNotificationContent()
            content.title = item.name
            content.body = body
            content.sound = .default
            content.categoryIdentifier = step == .deposit
                ? depositCategory
                : automaticTransferCategory
            content.threadIdentifier = item.id.uuidString
            content.interruptionLevel = kind == "early" ? .active : .timeSensitive
            content.userInfo = [
                "itemID": item.id.uuidString,
                "cycleKey": key,
                "step": step.rawValue
            ]

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifierPrefix(itemID: item.id, cycleKey: key, step: step) + kind,
                content: content,
                trigger: trigger
            )
            return (date, request)
        }
    }

    private static func identifierPrefix(itemID: UUID, cycleKey: String, step: CompletionStep) -> String {
        itemCyclePrefix(itemID: itemID, cycleKey: cycleKey) + "\(step.rawValue)."
    }

    private static func itemCyclePrefix(itemID: UUID, cycleKey: String) -> String {
        "\(AppConfig.notificationPrefix)\(itemID.uuidString).\(cycleKey)."
    }
}

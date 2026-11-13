import ActivityKit
import Foundation

struct LiveChecklistItem: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var amount: Int
    var requiresAutomaticTransferConfirmation: Bool
    var isDepositComplete: Bool
    var isAutomaticTransferComplete: Bool

    var isComplete: Bool {
        isDepositComplete &&
            (!requiresAutomaticTransferConfirmation || isAutomaticTransferComplete)
    }

    init(
        id: UUID,
        name: String,
        amount: Int,
        requiresAutomaticTransferConfirmation: Bool,
        isDepositComplete: Bool,
        isAutomaticTransferComplete: Bool
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.requiresAutomaticTransferConfirmation = requiresAutomaticTransferConfirmation
        self.isDepositComplete = isDepositComplete
        self.isAutomaticTransferComplete = isAutomaticTransferComplete
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case amount
        case requiresAutomaticTransferConfirmation
        case isDepositComplete
        case isAutomaticTransferComplete
        case isComplete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decode(Int.self, forKey: .amount)
        requiresAutomaticTransferConfirmation = try container.decodeIfPresent(
            Bool.self,
            forKey: .requiresAutomaticTransferConfirmation
        ) ?? false
        let legacyCompletion = try container.decodeIfPresent(Bool.self, forKey: .isComplete) ?? false
        isDepositComplete = try container.decodeIfPresent(
            Bool.self,
            forKey: .isDepositComplete
        ) ?? legacyCompletion
        isAutomaticTransferComplete = try container.decodeIfPresent(
            Bool.self,
            forKey: .isAutomaticTransferComplete
        ) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(amount, forKey: .amount)
        try container.encode(
            requiresAutomaticTransferConfirmation,
            forKey: .requiresAutomaticTransferConfirmation
        )
        try container.encode(isDepositComplete, forKey: .isDepositComplete)
        try container.encode(isAutomaticTransferComplete, forKey: .isAutomaticTransferComplete)
    }
}

struct SavingsChecklistAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String
        var cycleKey: String
        var items: [LiveChecklistItem]

        var totalCount: Int { items.count }
        var remainingCount: Int { items.filter { !$0.isComplete }.count }
        var completedCount: Int { items.filter(\.isComplete).count }
        var depositCompletedCount: Int { items.filter(\.isDepositComplete).count }
        var automaticTransferItemCount: Int {
            items.filter(\.requiresAutomaticTransferConfirmation).count
        }
        var automaticTransferCompletedCount: Int {
            items.filter {
                $0.requiresAutomaticTransferConfirmation && $0.isAutomaticTransferComplete
            }.count
        }
        var remainingAmount: Int {
            items.filter { !$0.isDepositComplete }.reduce(0) { $0 + $1.amount }
        }

        var stageSummaryText: String {
            var summary = "전체 \(totalCount)개 중 \(depositCompletedCount)개 입금 완료"
            if automaticTransferItemCount > 0 {
                summary += ", \(automaticTransferCompletedCount)개 저축 완료"
            }
            return summary
        }
    }

    var eventKey: String
    // Optional for compatibility with activities created by builds before the
    // relay start time was added to the attributes payload.
    var scheduledStart: Date?
}

enum LiveActivityError: LocalizedError {
    case disabled
    case noIncompleteItems

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "Live Activity가 꺼져 있습니다. iPhone 설정에서 돈 체크의 Live Activity를 허용해 주세요."
        case .noIncompleteItems:
            return "표시할 미완료 저축 항목이 없습니다."
        }
    }
}

@MainActor
enum LiveActivityManager {
    static func startNow(_ data: ChecklistData, subtitle: String = "완료할 항목을 체크하세요") async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw LiveActivityError.disabled }
        let state = contentState(data: data, cycleKey: data.cycleKey(for: .now), subtitle: subtitle)
        guard state.remainingCount > 0 else { throw LiveActivityError.noIncompleteItems }

        let todayKey = dayKey(for: .now)
        if let existing = Activity<SavingsChecklistAttributes>.activities.first(where: { $0.activityState == .active }) {
            await existing.update(ActivityContent(state: state, staleDate: staleDate(from: .now)))
            return
        }

        if #available(iOS 26.0, *) {
            // Pending relay activities count toward the same system limit as an
            // activity that starts now. Clear them first so the visible activity
            // always gets a slot; refresh() recreates successors afterward.
            for activity in Activity<SavingsChecklistAttributes>.activities where activity.activityState == .pending {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        let attributes = SavingsChecklistAttributes(eventKey: todayKey, scheduledStart: .now)
        let content = ActivityContent(state: state, staleDate: staleDate(from: .now))
        _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    static func refresh(_ data: ChecklistData, now: Date = .now) async {
        let activeWindow = attentionWindow(data: data, at: now)

        var hasActiveActivity = false
        for activity in Activity<SavingsChecklistAttributes>.activities where activity.activityState == .active {
            guard let activeWindow else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            hasActiveActivity = true
            let state = contentState(
                data: data,
                cycleKey: activeWindow.cycleKey,
                subtitle: activeWindow.subtitle
            )
            await activity.update(ActivityContent(state: state, staleDate: staleDate(from: now)))
        }

        let windows = attentionWindows(data: data, now: now)
        guard !windows.isEmpty else {
            if #available(iOS 26.0, *) {
                for activity in Activity<SavingsChecklistAttributes>.activities where activity.activityState == .pending {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
            return
        }

        if !hasActiveActivity, let activeWindow {
            do {
                if #available(iOS 26.0, *) {
                    for activity in Activity<SavingsChecklistAttributes>.activities where activity.activityState == .pending {
                        await activity.end(nil, dismissalPolicy: .immediate)
                    }
                }
                let state = contentState(
                    data: data,
                    cycleKey: activeWindow.cycleKey,
                    subtitle: activeWindow.subtitle
                )
                let attributes = SavingsChecklistAttributes(
                    eventKey: dayKey(for: now),
                    scheduledStart: now
                )
                let content = ActivityContent(state: state, staleDate: staleDate(from: now))
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
                hasActiveActivity = true
            } catch {
                // The explicit start button reports errors to the UI. Automatic
                // refresh keeps local notifications working if ActivityKit declines.
            }
        }

        guard #available(iOS 26.0, *), ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Replace pending schedules so edits and completed items are reflected before they appear.
        for activity in Activity<SavingsChecklistAttributes>.activities where activity.activityState == .pending {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let events = relayEvents(data: data, now: now)
        // The current system target limit is five. Keep one slot free whenever
        // an activity is visible so an explicit start can never be crowded out.
        let pendingLimit = hasActiveActivity ? 4 : 5
        for event in events.prefix(pendingLimit) {
            let eventState = contentState(data: data, cycleKey: event.cycleKey, subtitle: event.subtitle)
            guard eventState.remainingCount > 0 else { continue }
            let attributes = SavingsChecklistAttributes(eventKey: event.key, scheduledStart: event.start)
            let content = ActivityContent(state: eventState, staleDate: staleDate(from: event.start))
            let alert = AlertConfiguration(
                title: "저축 체크리스트",
                body: event.subtitle.hasPrefix("자동이체")
                    ? "자동이체가 완료됐는지 확인하세요."
                    : "완료하지 않은 입금 항목을 확인하세요.",
                sound: .default
            )
            _ = try? Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil,
                style: .standard,
                alertConfiguration: alert,
                start: event.start
            )
        }
    }

    private struct ScheduledEvent {
        let key: String
        let cycleKey: String
        let start: Date
        let subtitle: String
    }

    private struct AttentionWindow {
        let cycleKey: String
        let start: Date
        let subtitle: String
    }

    private static func attentionWindow(data: ChecklistData, at date: Date) -> AttentionWindow? {
        attentionWindows(data: data, now: date)
            .filter { $0.start <= date }
            .max { $0.start < $1.start }
    }

    private static func attentionWindows(data: ChecklistData, now: Date) -> [AttentionWindow] {
        let calendar = Calendar.current
        let currentCycleStart = CycleDate.start(
            for: now,
            payday: data.payday,
            holidays: data.holidayDateSet,
            calendar: calendar
        )
        let nextCycleStart = CycleDate.nextBoundary(
            after: now,
            payday: data.payday,
            holidays: data.holidayDateSet,
            calendar: calendar
        )
        var windows: [AttentionWindow] = []

        for cycleStart in [currentCycleStart, nextCycleStart] {
            let cycleKey = data.cycleKey(for: cycleStart, calendar: calendar)
            let hasIncompleteDeposit = data.items.contains {
                !data.isStepComplete($0.id, cycleKey: cycleKey, step: .deposit)
            }
            if hasIncompleteDeposit {
                let start = calendar.date(byAdding: .day, value: -1, to: cycleStart) ?? cycleStart
                windows.append(AttentionWindow(
                    cycleKey: cycleKey,
                    start: calendar.startOfDay(for: start),
                    subtitle: "입금 준비 · 완료할 때까지 표시해요"
                ))
            }

            for item in data.items where item.requiresAutomaticTransferConfirmation {
                guard !data.isStepComplete(
                    item.id,
                    cycleKey: cycleKey,
                    step: .automaticTransfer
                ) else { continue }
                let transferDate = CycleDate.automaticTransferDate(
                    for: item,
                    cycleStarting: cycleStart,
                    holidays: data.holidayDateSet,
                    calendar: calendar
                )
                let previousDay = calendar.date(byAdding: .day, value: -1, to: transferDate) ?? transferDate
                windows.append(AttentionWindow(
                    cycleKey: cycleKey,
                    start: calendar.startOfDay(for: previousDay),
                    subtitle: "자동이체 확인 · 저축 완료까지 표시해요"
                ))
            }
        }
        return windows
    }

    private static func relayEvents(data: ChecklistData, now: Date) -> [ScheduledEvent] {
        let windows = attentionWindows(data: data, now: now)
        let active = Activity<SavingsChecklistAttributes>.activities
            .filter { $0.activityState == .active }
            .max {
                ($0.attributes.scheduledStart ?? .distantPast) <
                ($1.attributes.scheduledStart ?? .distantPast)
            }

        let earliestAttention = windows.map(\.start).min() ?? now
        let base: Date
        if let active {
            base = max(active.attributes.scheduledStart ?? now, now)
        } else if earliestAttention <= now {
            base = now
        } else {
            base = earliestAttention
        }

        // Start the successor just before the eight-hour system limit. Five pending
        // activities provide roughly forty hours of continuous visible coverage.
        let relayInterval: TimeInterval = 7 * 60 * 60 + 55 * 60
        let shouldScheduleAnchor = active == nil && base > now.addingTimeInterval(30)
        let indices = shouldScheduleAnchor ? Array(0...4) : Array(1...5)
        return indices.compactMap { index in
            let start = base.addingTimeInterval(relayInterval * Double(index))
            guard start > now.addingTimeInterval(30) else { return nil }
            let eventWindow = windows
                .filter { $0.start <= start }
                .max { $0.start < $1.start }
                ?? windows.min { $0.start < $1.start }
            guard let eventWindow else { return nil }
            return ScheduledEvent(
                key: "relay-\(Int(start.timeIntervalSince1970))",
                cycleKey: eventWindow.cycleKey,
                start: start,
                subtitle: eventWindow.subtitle
            )
        }
    }

    private static func contentState(data: ChecklistData, cycleKey: String, subtitle: String) -> SavingsChecklistAttributes.ContentState {
        let items = data.items.map {
            LiveChecklistItem(
                id: $0.id,
                name: $0.name,
                amount: $0.amount,
                requiresAutomaticTransferConfirmation: $0.requiresAutomaticTransferConfirmation,
                isDepositComplete: data.isStepComplete($0.id, cycleKey: cycleKey, step: .deposit),
                isAutomaticTransferComplete: data.isStepComplete(
                    $0.id,
                    cycleKey: cycleKey,
                    step: .automaticTransfer
                )
            )
        }
        return SavingsChecklistAttributes.ContentState(
            title: "이번 저축 주기",
            subtitle: subtitle,
            cycleKey: cycleKey,
            items: items
        )
    }

    private static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func staleDate(from date: Date) -> Date {
        date.addingTimeInterval(8 * 60 * 60)
    }
}

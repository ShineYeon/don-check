import ActivityKit
import Foundation

struct LiveChecklistItem: Codable, Hashable, Identifiable {
    var id: UUID
    var cycleKey: String
    var name: String
    var amount: Int
    var requiresAutomaticTransferConfirmation: Bool
    var showsDepositAction: Bool
    var showsAutomaticTransferAction: Bool
    var isDepositComplete: Bool
    var isAutomaticTransferComplete: Bool

    var isComplete: Bool {
        (!showsDepositAction || isDepositComplete) &&
            (!showsAutomaticTransferAction || isAutomaticTransferComplete)
    }

    init(
        id: UUID,
        cycleKey: String = "",
        name: String,
        amount: Int,
        requiresAutomaticTransferConfirmation: Bool,
        showsDepositAction: Bool = true,
        showsAutomaticTransferAction: Bool? = nil,
        isDepositComplete: Bool,
        isAutomaticTransferComplete: Bool
    ) {
        self.id = id
        self.cycleKey = cycleKey
        self.name = name
        self.amount = amount
        self.requiresAutomaticTransferConfirmation = requiresAutomaticTransferConfirmation
        self.showsDepositAction = showsDepositAction
        self.showsAutomaticTransferAction = showsAutomaticTransferAction
            ?? requiresAutomaticTransferConfirmation
        self.isDepositComplete = isDepositComplete
        self.isAutomaticTransferComplete = isAutomaticTransferComplete
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case cycleKey
        case name
        case amount
        case requiresAutomaticTransferConfirmation
        case showsDepositAction
        case showsAutomaticTransferAction
        case isDepositComplete
        case isAutomaticTransferComplete
        case isComplete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        cycleKey = try container.decodeIfPresent(String.self, forKey: .cycleKey) ?? ""
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decode(Int.self, forKey: .amount)
        requiresAutomaticTransferConfirmation = try container.decodeIfPresent(
            Bool.self,
            forKey: .requiresAutomaticTransferConfirmation
        ) ?? false
        showsDepositAction = try container.decodeIfPresent(
            Bool.self,
            forKey: .showsDepositAction
        ) ?? true
        showsAutomaticTransferAction = try container.decodeIfPresent(
            Bool.self,
            forKey: .showsAutomaticTransferAction
        ) ?? requiresAutomaticTransferConfirmation
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
        try container.encode(cycleKey, forKey: .cycleKey)
        try container.encode(name, forKey: .name)
        try container.encode(amount, forKey: .amount)
        try container.encode(
            requiresAutomaticTransferConfirmation,
            forKey: .requiresAutomaticTransferConfirmation
        )
        try container.encode(showsDepositAction, forKey: .showsDepositAction)
        try container.encode(showsAutomaticTransferAction, forKey: .showsAutomaticTransferAction)
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
        var depositItemCount: Int { items.filter(\.showsDepositAction).count }
        var depositCompletedCount: Int {
            items.filter { $0.showsDepositAction && $0.isDepositComplete }.count
        }
        var automaticTransferItemCount: Int {
            items.filter(\.showsAutomaticTransferAction).count
        }
        var automaticTransferCompletedCount: Int {
            items.filter {
                $0.showsAutomaticTransferAction && $0.isAutomaticTransferComplete
            }.count
        }
        var remainingAmount: Int {
            items.filter { $0.showsDepositAction && !$0.isDepositComplete }
                .reduce(0) { $0 + $1.amount }
        }

        var stageSummaryText: String {
            var parts: [String] = []
            if depositItemCount > 0 {
                parts.append("입금 \(depositCompletedCount)/\(depositItemCount)")
            }
            if automaticTransferItemCount > 0 {
                parts.append("저축 \(automaticTransferCompletedCount)/\(automaticTransferItemCount)")
            }
            return parts.joined(separator: ", ")
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
        let state = manualContentState(data: data, subtitle: subtitle)
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
        let activeWindows = activeAttentionWindows(data: data, at: now)

        var hasActiveActivity = false
        for activity in Activity<SavingsChecklistAttributes>.activities where activity.activityState == .active {
            guard !activeWindows.isEmpty else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            hasActiveActivity = true
            let state = contentState(
                data: data,
                windows: activeWindows,
                subtitle: subtitle(for: activeWindows)
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

        if !hasActiveActivity, !activeWindows.isEmpty {
            do {
                if #available(iOS 26.0, *) {
                    for activity in Activity<SavingsChecklistAttributes>.activities where activity.activityState == .pending {
                        await activity.end(nil, dismissalPolicy: .immediate)
                    }
                }
                let state = contentState(
                    data: data,
                    windows: activeWindows,
                    subtitle: subtitle(for: activeWindows)
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
            let eventWindows = activeAttentionWindows(data: data, at: event.start)
            guard !eventWindows.isEmpty else { continue }
            let eventSubtitle = subtitle(for: eventWindows)
            let eventState = contentState(data: data, windows: eventWindows, subtitle: eventSubtitle)
            guard eventState.remainingCount > 0 else { continue }
            let attributes = SavingsChecklistAttributes(eventKey: event.key, scheduledStart: event.start)
            let content = ActivityContent(state: eventState, staleDate: staleDate(from: event.start))
            let alert = AlertConfiguration(
                title: "저축 체크리스트",
                body: eventSubtitle.hasPrefix("자동이체")
                    ? "자동이체가 완료됐는지 확인하세요."
                    : "오늘 입금 목표를 확인하세요.",
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
        let start: Date
    }

    private struct WindowItemKey: Hashable {
        let itemID: UUID
        let cycleKey: String
    }

    private static func activeAttentionWindows(
        data: ChecklistData,
        at date: Date
    ) -> [ChecklistAttentionWindow] {
        data.activeAttentionWindows(at: date)
    }

    private static func attentionWindows(
        data: ChecklistData,
        now: Date
    ) -> [ChecklistAttentionWindow] {
        data.attentionWindows(around: now)
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
            return ScheduledEvent(
                key: "relay-\(Int(start.timeIntervalSince1970))",
                start: start
            )
        }
    }

    private static func manualContentState(
        data: ChecklistData,
        subtitle: String
    ) -> SavingsChecklistAttributes.ContentState {
        let cycleKey = data.cycleKey(for: .now)
        let items = data.items.compactMap { item -> LiveChecklistItem? in
            let depositComplete = data.isStepComplete(
                item.id,
                cycleKey: cycleKey,
                step: .deposit
            )
            let transferComplete = data.isStepComplete(
                item.id,
                cycleKey: cycleKey,
                step: .automaticTransfer
            )
            let showsDeposit = !depositComplete
            let showsTransfer = item.requiresAutomaticTransferConfirmation && !transferComplete
            guard showsDeposit || showsTransfer else { return nil }
            return LiveChecklistItem(
                id: item.id,
                cycleKey: cycleKey,
                name: item.name,
                amount: item.amount,
                requiresAutomaticTransferConfirmation: item.requiresAutomaticTransferConfirmation,
                showsDepositAction: showsDeposit,
                showsAutomaticTransferAction: showsTransfer,
                isDepositComplete: depositComplete,
                isAutomaticTransferComplete: transferComplete
            )
        }
        return SavingsChecklistAttributes.ContentState(
            title: "이번 저축 주기",
            subtitle: subtitle,
            cycleKey: cycleKey,
            items: items
        )
    }

    private static func contentState(
        data: ChecklistData,
        windows: [ChecklistAttentionWindow],
        subtitle: String
    ) -> SavingsChecklistAttributes.ContentState {
        let grouped = Dictionary(grouping: windows) {
            WindowItemKey(itemID: $0.itemID, cycleKey: $0.cycleKey)
        }
        let orderedGroups = grouped.sorted { lhs, rhs in
            let lhsStart = lhs.value.map(\.start).min() ?? .distantFuture
            let rhsStart = rhs.value.map(\.start).min() ?? .distantFuture
            if lhsStart != rhsStart { return lhsStart < rhsStart }
            let lhsIndex = data.items.firstIndex { $0.id == lhs.key.itemID } ?? .max
            let rhsIndex = data.items.firstIndex { $0.id == rhs.key.itemID } ?? .max
            return lhsIndex < rhsIndex
        }
        let items = orderedGroups.compactMap { key, itemWindows -> LiveChecklistItem? in
            guard let item = data.items.first(where: { $0.id == key.itemID }) else { return nil }
            let steps = Set(itemWindows.map(\.step))
            return LiveChecklistItem(
                id: item.id,
                cycleKey: key.cycleKey,
                name: item.name,
                amount: item.amount,
                requiresAutomaticTransferConfirmation: item.requiresAutomaticTransferConfirmation,
                showsDepositAction: steps.contains(.deposit),
                showsAutomaticTransferAction: steps.contains(.automaticTransfer),
                isDepositComplete: data.isStepComplete(
                    item.id,
                    cycleKey: key.cycleKey,
                    step: .deposit
                ),
                isAutomaticTransferComplete: data.isStepComplete(
                    item.id,
                    cycleKey: key.cycleKey,
                    step: .automaticTransfer
                )
            )
        }
        let fallbackCycleKey = windows.max { $0.start < $1.start }?.cycleKey
            ?? data.cycleKey(for: .now)
        return SavingsChecklistAttributes.ContentState(
            title: "확인할 저축 일정",
            subtitle: subtitle,
            cycleKey: fallbackCycleKey,
            items: items
        )
    }

    private static func subtitle(for windows: [ChecklistAttentionWindow]) -> String {
        let steps = Set(windows.map(\.step))
        if steps == Set(CompletionStep.allCases) {
            return "입금·자동이체 확인 · 체크할 때까지 표시해요"
        }
        if steps.contains(.automaticTransfer) {
            return "자동이체 확인 · 체크할 때까지 표시해요"
        }
        return "입금 목표 확인 · 체크할 때까지 표시해요"
    }

    private static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func staleDate(from date: Date) -> Date {
        date.addingTimeInterval(8 * 60 * 60)
    }
}

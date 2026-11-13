import ActivityKit
import Foundation

struct LiveChecklistItem: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var amount: Int
    var isComplete: Bool
}

struct SavingsChecklistAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String
        var cycleKey: String
        var items: [LiveChecklistItem]

        var remainingCount: Int { items.filter { !$0.isComplete }.count }
        var completedCount: Int { items.filter(\.isComplete).count }
        var remainingAmount: Int {
            items.filter { !$0.isComplete }.reduce(0) { $0 + $1.amount }
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
        let currentKey = data.cycleKey(for: now)
        let state = contentState(data: data, cycleKey: currentKey, subtitle: "완료할 항목을 체크하세요")

        var hasActiveActivity = false
        for activity in Activity<SavingsChecklistAttributes>.activities where activity.activityState == .active {
            hasActiveActivity = true
            if state.remainingCount == 0 {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else {
                await activity.update(ActivityContent(state: state, staleDate: staleDate(from: now)))
            }
        }

        guard state.remainingCount > 0 else {
            if #available(iOS 26.0, *) {
                for activity in Activity<SavingsChecklistAttributes>.activities where activity.activityState == .pending {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
            return
        }

        guard #available(iOS 26.0, *), ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Replace pending schedules so edits and completed items are reflected before they appear.
        for activity in Activity<SavingsChecklistAttributes>.activities where activity.activityState == .pending {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        if !hasActiveActivity && shouldStartImmediately(data: data, now: now) {
            do {
                try await startNow(data, subtitle: "고정 유지 모드 · 완료할 때까지 표시해요")
                hasActiveActivity = true
            } catch {
                // The explicit start button reports errors to the UI. Automatic
                // refresh keeps local notifications working if ActivityKit declines.
            }
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
                body: "완료하지 않은 입금 항목을 확인하세요.",
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

    private static func shouldStartImmediately(data: ChecklistData, now: Date) -> Bool {
        let calendar = Calendar.current
        let cycleKey = data.cycleKey(for: now, calendar: calendar)
        let cycleStart = CycleDate.start(for: now, payday: data.payday, calendar: calendar)
        return data.items.contains { item in
            guard !data.isComplete(item.id, cycleKey: cycleKey) else { return false }
            let due = CycleDate.dueDate(
                for: item,
                cycleStarting: cycleStart,
                calendar: calendar
            )
            let attention = calendar.date(byAdding: .day, value: -item.leadDays, to: due) ?? due
            return attention <= now
        }
    }

    private static func relayEvents(data: ChecklistData, now: Date, anchor overrideAnchor: Date? = nil) -> [ScheduledEvent] {
        let calendar = Calendar.current
        var attentionDates: [Date] = []

        let currentCycleStart = CycleDate.start(for: now, payday: data.payday, calendar: calendar)
        let cycleStarts = [
            currentCycleStart,
            CycleDate.nextBoundary(after: now, payday: data.payday, calendar: calendar)
        ]
        for cycleStart in cycleStarts {
            let cycleKey = data.cycleKey(for: cycleStart, calendar: calendar)
            for item in data.items {
                guard !data.isComplete(item.id, cycleKey: cycleKey) else { continue }
                let due = CycleDate.dueDate(
                    for: item,
                    cycleStarting: cycleStart,
                    calendar: calendar
                )
                var dates: [Date] = [due]
                if item.leadDays > 0,
                   let early = calendar.date(byAdding: .day, value: -item.leadDays, to: due) {
                    dates.append(early)
                }
                attentionDates.append(contentsOf: dates)
            }
        }

        let active = Activity<SavingsChecklistAttributes>.activities
            .filter { $0.activityState == .active }
            .max {
                ($0.attributes.scheduledStart ?? .distantPast) <
                ($1.attributes.scheduledStart ?? .distantPast)
            }

        let earliestAttention = attentionDates.min() ?? now
        let base: Date
        if let overrideAnchor {
            base = overrideAnchor
        } else if let active {
            base = active.attributes.scheduledStart ?? now
        } else if earliestAttention <= now {
            base = now
        } else {
            base = earliestAttention
        }

        // Start the successor just before the eight-hour system limit. Five pending
        // activities provide roughly forty hours of continuous visible coverage.
        let relayInterval: TimeInterval = 7 * 60 * 60 + 55 * 60
        let shouldScheduleAnchor = active == nil && overrideAnchor == nil && base > now.addingTimeInterval(30)
        let indices = shouldScheduleAnchor ? Array(0...4) : Array(1...5)
        return indices.compactMap { index in
            let start = base.addingTimeInterval(relayInterval * Double(index))
            guard start > now.addingTimeInterval(30) else { return nil }
            return ScheduledEvent(
                key: "relay-\(Int(start.timeIntervalSince1970))",
                cycleKey: data.cycleKey(for: start, calendar: calendar),
                start: start,
                subtitle: "고정 유지 모드 · 완료할 때까지 표시해요"
            )
        }
    }

    private static func contentState(data: ChecklistData, cycleKey: String, subtitle: String) -> SavingsChecklistAttributes.ContentState {
        let items = data.items.map {
            LiveChecklistItem(
                id: $0.id,
                name: $0.name,
                amount: $0.amount,
                isComplete: data.isComplete($0.id, cycleKey: cycleKey)
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

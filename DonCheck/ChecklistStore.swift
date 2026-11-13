import EventKit
import Foundation
import SwiftUI
import UserNotifications
import WidgetKit

@MainActor
final class ChecklistStore: ObservableObject {
    @Published private(set) var data = ChecklistData()
    @Published var notificationAuthorized = false
    @Published var liveActivityMessage: String?
    @Published private(set) var holidaySyncMessage: String?

    private let repository: ChecklistRepository

    init(repository: ChecklistRepository = .shared) {
        self.repository = repository
        reload()
        Task {
            await refreshNotificationStatus()
            await NotificationScheduler.rescheduleAll(data)
            await LiveActivityManager.refresh(data)
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-startLiveChecklist") {
                await showLiveChecklistNow()
            }
#endif
        }
    }

    var cycleKey: String { data.cycleKey(for: .now) }
    var completedCount: Int { data.completedCount(cycleKey: cycleKey) }
    var depositCompletedCount: Int { data.depositCompletedCount(cycleKey: cycleKey) }
    var automaticTransferCompletedCount: Int { data.automaticTransferCompletedCount(cycleKey: cycleKey) }
    var automaticTransferItemCount: Int { data.automaticTransferItemCount }
    var remainingAmount: Int { data.remainingAmount(cycleKey: cycleKey) }

    func isComplete(_ item: SavingsItem) -> Bool {
        data.isComplete(item.id, cycleKey: cycleKey)
    }

    func isStepComplete(_ item: SavingsItem, step: CompletionStep) -> Bool {
        data.isStepComplete(item.id, cycleKey: cycleKey, step: step)
    }

    func reload() {
        data = repository.load()
    }

    func save(_ item: SavingsItem) {
        if let index = data.items.firstIndex(where: { $0.id == item.id }) {
            data.items[index] = item
        } else {
            data.items.append(item)
        }
        persist()
    }

    func updatePayday(_ day: Int) {
        let validDay = ChecklistData.validPayday(day)
        guard data.payday != validDay else { return }
        data.payday = validDay
        persist(removeDeliveredNotifications: true)
    }

    func syncHolidayCalendar() async {
        let eventStore = EKEventStore()
        do {
            let granted: Bool
            if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
                granted = true
            } else {
                granted = try await eventStore.requestFullAccessToEvents()
            }
            guard granted else {
                holidaySyncMessage = "캘린더 접근이 허용되지 않아 공휴일을 동기화하지 못했습니다."
                return
            }

            let keywords = ["공휴일", "holiday", "holidays"]
            let holidayCalendars = eventStore.calendars(for: .event).filter { calendar in
                let title = calendar.title.lowercased()
                return keywords.contains { title.contains($0) }
            }
            guard !holidayCalendars.isEmpty else {
                holidaySyncMessage = "구독 중인 공휴일 캘린더를 찾지 못했습니다. iPhone 캘린더에서 대한민국 공휴일을 활성화해 주세요."
                return
            }

            let calendar = Calendar.current
            let currentYear = calendar.component(.year, from: .now)
            let start = calendar.date(from: DateComponents(year: currentYear - 1, month: 1, day: 1)) ?? .now
            let end = calendar.date(from: DateComponents(year: currentYear + 3, month: 1, day: 1)) ?? .now
            let predicate = eventStore.predicateForEvents(
                withStart: start,
                end: end,
                calendars: holidayCalendars
            )
            let events = eventStore.events(matching: predicate).filter(\.isAllDay)
            var holidayKeys = Set<String>()
            for event in events {
                var date = calendar.startOfDay(for: event.startDate)
                let eventEnd = calendar.startOfDay(for: event.endDate)
                while date < eventEnd {
                    holidayKeys.insert(CycleDate.dayKey(for: date, calendar: calendar))
                    guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
                    date = next
                }
            }

            let previousHolidayKeys = data.holidayDateSet
            data.completions = data.completions.map { record in
                return CompletionRecord(
                    itemID: record.itemID,
                    cycleKey: CycleDate.remapCycleKey(
                        record.cycleKey,
                        payday: data.payday,
                        from: previousHolidayKeys,
                        to: holidayKeys
                    ),
                    step: record.step,
                    completedAt: record.completedAt
                )
            }
            data.holidayDates = holidayKeys.sorted()
            persist(removeDeliveredNotifications: true)
            holidaySyncMessage = "공휴일 \(holidayKeys.count)개를 동기화했습니다."
        } catch {
            holidaySyncMessage = "공휴일 동기화에 실패했습니다: \(error.localizedDescription)"
        }
    }

    func delete(at offsets: IndexSet) {
        let deletedIDs = offsets.map { data.items[$0].id }
        data.items.remove(atOffsets: offsets)
        data.completions.removeAll { deletedIDs.contains($0.itemID) }
        persist()
    }

    func toggle(_ item: SavingsItem, step: CompletionStep) {
        let next = !isStepComplete(item, step: step)
        data.completions.removeAll {
            $0.itemID == item.id && $0.cycleKey == cycleKey && $0.step == step
        }
        if next {
            data.completions.append(CompletionRecord(
                itemID: item.id,
                cycleKey: cycleKey,
                step: step,
                completedAt: .now
            ))
        }
        persist()
    }

    func requestNotifications() async {
        notificationAuthorized = await NotificationScheduler.requestAuthorization()
        if notificationAuthorized {
            await NotificationScheduler.rescheduleAll(data)
        }
    }

    func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    func rescheduleNotifications() async {
        await NotificationScheduler.rescheduleAll(data)
        await LiveActivityManager.refresh(data)
    }

    func showLiveChecklistNow() async {
        do {
            try await LiveActivityManager.startNow(data, subtitle: "고정 유지 모드 · 완료할 때까지 표시해요")
            await LiveActivityManager.refresh(data)
            liveActivityMessage = "잠금화면 체크리스트를 시작했습니다."
        } catch {
            liveActivityMessage = error.localizedDescription
        }
    }

    private func persist(removeDeliveredNotifications: Bool = false) {
        repository.pruneHistory(in: &data)
        repository.save(data)
        WidgetCenter.shared.reloadAllTimelines()
        Task {
            if removeDeliveredNotifications {
                await NotificationScheduler.removeAllDeliveredNotifications()
            }
            await NotificationScheduler.rescheduleAll(data)
            await LiveActivityManager.refresh(data)
        }
    }
}

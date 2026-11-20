import EventKit
import Foundation
import SwiftUI
import UserNotifications
import WidgetKit

enum HolidaySyncState: Equatable {
    case notStarted
    case syncing
    case synced(count: Int, sources: [String], period: String)
    case permissionDenied
    case calendarNotFound(availableCalendarCount: Int)
    case noEvents(sources: [String], period: String)
    case failed(String)

    var isSyncing: Bool { self == .syncing }

    func valueText(cachedCount: Int) -> String {
        switch self {
        case .notStarted:
            return cachedCount > 0 ? "\(cachedCount)일 저장됨" : "동기화 전"
        case .syncing:
            return "확인 중"
        case .synced(let count, _, _):
            return "\(count)일 저장됨"
        case .permissionDenied:
            return cachedCount > 0 ? "\(cachedCount)일 유지 중" : "권한 필요"
        case .calendarNotFound:
            return cachedCount > 0 ? "\(cachedCount)일 유지 중" : "캘린더 없음"
        case .noEvents:
            return cachedCount > 0 ? "\(cachedCount)일 유지 중" : "일정 없음"
        case .failed:
            return cachedCount > 0 ? "\(cachedCount)일 유지 중" : "동기화 실패"
        }
    }

    func message(cachedCount: Int) -> String? {
        let preserved = cachedCount > 0 ? " 기존 \(cachedCount)일은 유지했습니다." : ""
        switch self {
        case .notStarted, .syncing:
            return nil
        case .synced(let count, let sources, let period):
            return "\(sources.joined(separator: ", "))에서 \(period) 공휴일 \(count)일을 동기화했습니다."
        case .permissionDenied:
            return "캘린더 전체 접근 권한이 없어 공휴일을 읽을 수 없습니다. iPhone 설정에서 DonCheck의 캘린더 접근을 허용해 주세요.\(preserved)"
        case .calendarNotFound(let availableCount):
            return "확인한 캘린더 \(availableCount)개 중 이름에 공휴일·휴일·Holiday가 포함된 캘린더를 찾지 못했습니다. iPhone 캘린더에서 대한민국 공휴일을 활성화해 주세요.\(preserved)"
        case .noEvents(let sources, let period):
            return "\(sources.joined(separator: ", ")) 캘린더는 찾았지만 \(period) 범위에 일정이 없습니다. 캘린더 앱에서 공휴일 일정이 실제로 표시되는지 확인해 주세요.\(preserved)"
        case .failed(let description):
            return "공휴일 동기화에 실패했습니다: \(description)\(preserved)"
        }
    }
}

@MainActor
final class ChecklistStore: ObservableObject {
    @Published private(set) var data = ChecklistData()
    @Published var notificationAuthorized = false
    @Published var liveActivityMessage: String?
    @Published private(set) var holidaySyncState: HolidaySyncState = .notStarted

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
        holidaySyncState = .syncing
        let authorizationStore = EKEventStore()
        do {
            let authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            let granted: Bool
            if authorizationStatus == .fullAccess {
                granted = true
            } else if authorizationStatus == .denied || authorizationStatus == .restricted {
                granted = false
            } else {
                granted = try await authorizationStore.requestFullAccessToEvents()
            }
            guard granted else {
                holidaySyncState = .permissionDenied
                return
            }

            // Create a fresh store after the permission prompt so its sources
            // reflect the authorization decision made in this session.
            let eventStore = EKEventStore()
            let allCalendars = eventStore.calendars(for: .event)
            let holidayCalendars = allCalendars.filter { eventCalendar in
                HolidayDateImport.matchesCalendar(
                    title: eventCalendar.title,
                    sourceTitle: eventCalendar.source.title
                )
            }
            guard !holidayCalendars.isEmpty else {
                holidaySyncState = .calendarNotFound(availableCalendarCount: allCalendars.count)
                return
            }

            let calendar = Calendar.current
            let currentYear = calendar.component(.year, from: .now)
            let start = calendar.date(from: DateComponents(year: currentYear - 1, month: 1, day: 1)) ?? .now
            let end = calendar.date(from: DateComponents(year: currentYear + 3, month: 1, day: 1)) ?? .now
            let period = "\(currentYear - 1)~\(currentYear + 2)년"
            let sourceNames = Array(Set(holidayCalendars.map(\.title))).sorted()
            let predicate = eventStore.predicateForEvents(
                withStart: start,
                end: end,
                calendars: holidayCalendars
            )
            let events = eventStore.events(matching: predicate)
            var holidayKeys = Set<String>()
            for event in events {
                holidayKeys.formUnion(HolidayDateImport.dateKeys(
                    startDate: event.startDate,
                    endDate: event.endDate,
                    calendar: calendar
                ))
            }
            guard !holidayKeys.isEmpty else {
                holidaySyncState = .noEvents(sources: sourceNames, period: period)
                return
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
            holidaySyncState = .synced(
                count: holidayKeys.count,
                sources: sourceNames,
                period: period
            )
        } catch {
            holidaySyncState = .failed(error.localizedDescription)
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

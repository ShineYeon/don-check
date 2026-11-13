import Foundation
import SwiftUI
import UserNotifications
import WidgetKit

@MainActor
final class ChecklistStore: ObservableObject {
    @Published private(set) var data = ChecklistData()
    @Published var notificationAuthorized = false
    @Published var liveActivityMessage: String?

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
    var remainingAmount: Int { data.remainingAmount(cycleKey: cycleKey) }

    func isComplete(_ item: SavingsItem) -> Bool {
        data.isComplete(item.id, cycleKey: cycleKey)
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

    func delete(at offsets: IndexSet) {
        let deletedIDs = offsets.map { data.items[$0].id }
        data.items.remove(atOffsets: offsets)
        data.completions.removeAll { deletedIDs.contains($0.itemID) }
        persist()
    }

    func toggle(_ item: SavingsItem) {
        let next = !isComplete(item)
        data.completions.removeAll { $0.itemID == item.id && $0.cycleKey == cycleKey }
        if next {
            data.completions.append(CompletionRecord(itemID: item.id, cycleKey: cycleKey, completedAt: .now))
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

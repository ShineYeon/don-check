import ActivityKit
import AppIntents
import Foundation
import WidgetKit

struct ToggleSavingsItemIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "저축 항목 완료 변경"
    static var description = IntentDescription("현재 저축 주기 항목의 완료 상태를 변경합니다.")

    @Parameter(title: "항목 ID") var itemID: String
    @Parameter(title: "주기") var cycleKey: String
    @Parameter(title: "완료") var nextValue: Bool

    init() {}

    init(itemID: String, cycleKey: String, nextValue: Bool) {
        self.itemID = itemID
        self.cycleKey = cycleKey
        self.nextValue = nextValue
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: itemID) else { return .result() }
        let data = ChecklistRepository.shared.setCompletion(itemID: id, cycleKey: cycleKey, isComplete: nextValue)
        if nextValue {
            await NotificationScheduler.cancel(itemID: id, cycleKey: cycleKey)
        }
        await NotificationScheduler.rescheduleAll(data)
        await LiveActivityManager.refresh(data)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

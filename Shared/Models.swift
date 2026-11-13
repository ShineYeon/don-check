import Foundation

struct SavingsItem: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var amount: Int
    var debitDay: Int
    var reminderHour: Int
    var reminderMinute: Int
    var leadDays: Int
    var followUpCount: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        amount: Int,
        debitDay: Int,
        reminderHour: Int = 8,
        reminderMinute: Int = 0,
        leadDays: Int = 1,
        followUpCount: Int = 3,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.debitDay = debitDay
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.leadDays = leadDays
        self.followUpCount = followUpCount
        self.createdAt = createdAt
    }
}

struct CompletionRecord: Codable, Hashable {
    var itemID: UUID
    var cycleKey: String
    var completedAt: Date
}

struct ChecklistData: Codable {
    var items: [SavingsItem] = []
    var completions: [CompletionRecord] = []
}

enum CycleDate {
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    static func date(for key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 1))
    }

    static func offset(_ months: Int, from date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: months, to: date) ?? date
    }

    static func dueDate(for item: SavingsItem, monthContaining date: Date, calendar: Calendar = .current) -> Date {
        let monthRange = calendar.range(of: .day, in: .month, for: date)
        let day = min(item.debitDay, monthRange?.count ?? item.debitDay)
        let month = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: month.year,
            month: month.month,
            day: day,
            hour: item.reminderHour,
            minute: item.reminderMinute
        )) ?? date
    }
}

extension ChecklistData {
    func isComplete(_ itemID: UUID, cycleKey: String) -> Bool {
        completions.contains { $0.itemID == itemID && $0.cycleKey == cycleKey }
    }

    func remainingAmount(cycleKey: String) -> Int {
        items.filter { !isComplete($0.id, cycleKey: cycleKey) }.reduce(0) { $0 + $1.amount }
    }

    func completedCount(cycleKey: String) -> Int {
        items.filter { isComplete($0.id, cycleKey: cycleKey) }.count
    }
}

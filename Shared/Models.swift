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
    var requiresAutomaticTransferConfirmation: Bool
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
        requiresAutomaticTransferConfirmation: Bool = false,
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
        self.requiresAutomaticTransferConfirmation = requiresAutomaticTransferConfirmation
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case amount
        case debitDay
        case reminderHour
        case reminderMinute
        case leadDays
        case followUpCount
        case requiresAutomaticTransferConfirmation
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decode(Int.self, forKey: .amount)
        debitDay = try container.decode(Int.self, forKey: .debitDay)
        reminderHour = try container.decode(Int.self, forKey: .reminderHour)
        reminderMinute = try container.decode(Int.self, forKey: .reminderMinute)
        leadDays = try container.decode(Int.self, forKey: .leadDays)
        followUpCount = try container.decode(Int.self, forKey: .followUpCount)
        requiresAutomaticTransferConfirmation = try container.decodeIfPresent(
            Bool.self,
            forKey: .requiresAutomaticTransferConfirmation
        ) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

enum CompletionStep: String, Codable, CaseIterable, Hashable {
    case deposit
    case automaticTransfer
}

struct CompletionRecord: Codable, Hashable {
    var itemID: UUID
    var cycleKey: String
    var step: CompletionStep = .deposit
    var completedAt: Date

    init(itemID: UUID, cycleKey: String, step: CompletionStep = .deposit, completedAt: Date) {
        self.itemID = itemID
        self.cycleKey = cycleKey
        self.step = step
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey {
        case itemID
        case cycleKey
        case step
        case completedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemID = try container.decode(UUID.self, forKey: .itemID)
        cycleKey = try container.decode(String.self, forKey: .cycleKey)
        step = try container.decodeIfPresent(CompletionStep.self, forKey: .step) ?? .deposit
        completedAt = try container.decode(Date.self, forKey: .completedAt)
    }
}

struct ChecklistData: Codable {
    var items: [SavingsItem] = []
    var completions: [CompletionRecord] = []
    var payday: Int = 1

    init(items: [SavingsItem] = [], completions: [CompletionRecord] = [], payday: Int = 1) {
        self.items = items
        self.completions = completions
        self.payday = Self.validPayday(payday)
    }

    private enum CodingKeys: String, CodingKey {
        case items
        case completions
        case payday
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([SavingsItem].self, forKey: .items) ?? []
        completions = try container.decodeIfPresent([CompletionRecord].self, forKey: .completions) ?? []
        payday = Self.validPayday(try container.decodeIfPresent(Int.self, forKey: .payday) ?? 1)
    }

    static func validPayday(_ day: Int) -> Int {
        min(max(day, 1), 31)
    }
}

enum CycleDate {
    static func key(for date: Date, payday: Int = 1, calendar: Calendar = .current) -> String {
        let start = start(for: date, payday: payday, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day], from: start)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func date(for key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: parts[0],
            month: parts[1],
            day: parts.count == 3 ? parts[2] : 1
        ))
    }

    static func start(for date: Date, payday: Int, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: date)
        let thisMonthBoundary = boundary(
            monthContaining: today,
            payday: payday,
            calendar: calendar
        )
        guard today < thisMonthBoundary else { return thisMonthBoundary }

        let previousMonth = offset(-1, from: firstDayOfMonth(containing: today, calendar: calendar), calendar: calendar)
        return boundary(monthContaining: previousMonth, payday: payday, calendar: calendar)
    }

    static func nextBoundary(after date: Date, payday: Int, calendar: Calendar = .current) -> Date {
        let currentStart = start(for: date, payday: payday, calendar: calendar)
        let nextMonth = offset(1, from: firstDayOfMonth(containing: currentStart, calendar: calendar), calendar: calendar)
        return boundary(monthContaining: nextMonth, payday: payday, calendar: calendar)
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

    static func dueDate(
        for item: SavingsItem,
        cycleStarting cycleStart: Date,
        calendar: Calendar = .current
    ) -> Date {
        let start = calendar.startOfDay(for: cycleStart)
        let sameMonthDue = dueDate(for: item, monthContaining: start, calendar: calendar)
        if sameMonthDue >= start {
            return sameMonthDue
        }

        let nextMonth = offset(1, from: firstDayOfMonth(containing: start, calendar: calendar), calendar: calendar)
        return dueDate(for: item, monthContaining: nextMonth, calendar: calendar)
    }

    private static func boundary(monthContaining date: Date, payday: Int, calendar: Calendar) -> Date {
        let validPayday = ChecklistData.validPayday(payday)
        let monthRange = calendar.range(of: .day, in: .month, for: date)
        let day = min(validPayday, monthRange?.count ?? validPayday)
        let month = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: month.year,
            month: month.month,
            day: day
        )) ?? calendar.startOfDay(for: date)
    }

    private static func firstDayOfMonth(containing date: Date, calendar: Calendar) -> Date {
        let month = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: month.year,
            month: month.month,
            day: 1
        )) ?? date
    }
}

extension ChecklistData {
    func cycleKey(for date: Date, calendar: Calendar = .current) -> String {
        CycleDate.key(for: date, payday: payday, calendar: calendar)
    }

    func isStepComplete(_ itemID: UUID, cycleKey: String, step: CompletionStep) -> Bool {
        completions.contains {
            $0.itemID == itemID && $0.cycleKey == cycleKey && $0.step == step
        }
    }

    func isComplete(_ itemID: UUID, cycleKey: String) -> Bool {
        guard let item = items.first(where: { $0.id == itemID }) else { return false }
        guard isStepComplete(itemID, cycleKey: cycleKey, step: .deposit) else { return false }
        return !item.requiresAutomaticTransferConfirmation ||
            isStepComplete(itemID, cycleKey: cycleKey, step: .automaticTransfer)
    }

    func remainingAmount(cycleKey: String) -> Int {
        items
            .filter { !isStepComplete($0.id, cycleKey: cycleKey, step: .deposit) }
            .reduce(0) { $0 + $1.amount }
    }

    func completedCount(cycleKey: String) -> Int {
        items.filter { isComplete($0.id, cycleKey: cycleKey) }.count
    }

    func depositCompletedCount(cycleKey: String) -> Int {
        items.filter { isStepComplete($0.id, cycleKey: cycleKey, step: .deposit) }.count
    }

    func automaticTransferCompletedCount(cycleKey: String) -> Int {
        items.filter {
            $0.requiresAutomaticTransferConfirmation &&
                isStepComplete($0.id, cycleKey: cycleKey, step: .automaticTransfer)
        }.count
    }

    var automaticTransferItemCount: Int {
        items.filter(\.requiresAutomaticTransferConfirmation).count
    }
}

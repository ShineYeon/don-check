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
    var automaticTransferDay: Int
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
        automaticTransferDay: Int? = nil,
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
        self.automaticTransferDay = min(max(automaticTransferDay ?? debitDay, 1), 31)
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
        case automaticTransferDay
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
        automaticTransferDay = min(max(
            try container.decodeIfPresent(Int.self, forKey: .automaticTransferDay) ?? debitDay,
            1
        ), 31)
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
    var holidayDates: [String] = []

    init(
        items: [SavingsItem] = [],
        completions: [CompletionRecord] = [],
        payday: Int = 1,
        holidayDates: [String] = []
    ) {
        self.items = items
        self.completions = completions
        self.payday = Self.validPayday(payday)
        self.holidayDates = Array(Set(holidayDates)).sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case items
        case completions
        case payday
        case holidayDates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([SavingsItem].self, forKey: .items) ?? []
        completions = try container.decodeIfPresent([CompletionRecord].self, forKey: .completions) ?? []
        payday = Self.validPayday(try container.decodeIfPresent(Int.self, forKey: .payday) ?? 1)
        holidayDates = Array(Set(
            try container.decodeIfPresent([String].self, forKey: .holidayDates) ?? []
        )).sorted()
    }

    static func validPayday(_ day: Int) -> Int {
        min(max(day, 1), 31)
    }
}

enum CycleDate {
    static func key(
        for date: Date,
        payday: Int = 1,
        holidays: Set<String> = [],
        calendar: Calendar = .current
    ) -> String {
        let start = start(for: date, payday: payday, holidays: holidays, calendar: calendar)
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

    static func start(
        for date: Date,
        payday: Int,
        holidays: Set<String> = [],
        calendar: Calendar = .current
    ) -> Date {
        let today = calendar.startOfDay(for: date)
        let month = firstDayOfMonth(containing: today, calendar: calendar)
        let candidates = (-1...1).map { monthOffset in
            let candidateMonth = offset(monthOffset, from: month, calendar: calendar)
            return boundary(
                monthContaining: candidateMonth,
                payday: payday,
                holidays: holidays,
                calendar: calendar
            )
        }
        return candidates.filter { $0 <= today }.max() ?? today
    }

    static func nextBoundary(
        after date: Date,
        payday: Int,
        holidays: Set<String> = [],
        calendar: Calendar = .current
    ) -> Date {
        let today = calendar.startOfDay(for: date)
        let month = firstDayOfMonth(containing: today, calendar: calendar)
        let candidates = (0...2).map { monthOffset in
            let candidateMonth = offset(monthOffset, from: month, calendar: calendar)
            return boundary(
                monthContaining: candidateMonth,
                payday: payday,
                holidays: holidays,
                calendar: calendar
            )
        }
        return candidates.filter { $0 > today }.min() ?? offset(1, from: today, calendar: calendar)
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

    static func automaticTransferDate(
        for item: SavingsItem,
        cycleStarting cycleStart: Date,
        holidays: Set<String> = [],
        calendar: Calendar = .current
    ) -> Date {
        let scheduled = scheduledDate(
            day: item.automaticTransferDay,
            hour: item.reminderHour,
            minute: item.reminderMinute,
            cycleStarting: cycleStart,
            calendar: calendar
        )
        return nextBusinessDay(onOrAfter: scheduled, holidays: holidays, calendar: calendar)
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func remapCycleKey(
        _ key: String,
        payday: Int,
        from oldHolidays: Set<String>,
        to newHolidays: Set<String>,
        calendar: Calendar = .current
    ) -> String {
        guard let oldCycleStart = date(for: key, calendar: calendar) else { return key }
        let referenceMonth = firstDayOfMonth(containing: oldCycleStart, calendar: calendar)
        let nominalMonth = (-1...2)
            .map { offset($0, from: referenceMonth, calendar: calendar) }
            .first { candidateMonth in
                dayKey(
                    for: boundary(
                        monthContaining: candidateMonth,
                        payday: payday,
                        holidays: oldHolidays,
                        calendar: calendar
                    ),
                    calendar: calendar
                ) == key
            }

        guard let nominalMonth else {
            return self.key(
                for: oldCycleStart,
                payday: payday,
                holidays: newHolidays,
                calendar: calendar
            )
        }
        return dayKey(
            for: boundary(
                monthContaining: nominalMonth,
                payday: payday,
                holidays: newHolidays,
                calendar: calendar
            ),
            calendar: calendar
        )
    }

    private static func boundary(
        monthContaining date: Date,
        payday: Int,
        holidays: Set<String>,
        calendar: Calendar
    ) -> Date {
        let validPayday = ChecklistData.validPayday(payday)
        let monthRange = calendar.range(of: .day, in: .month, for: date)
        let day = min(validPayday, monthRange?.count ?? validPayday)
        let month = calendar.dateComponents([.year, .month], from: date)
        let nominal = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: month.year,
            month: month.month,
            day: day
        )) ?? calendar.startOfDay(for: date)
        return previousBusinessDay(onOrBefore: nominal, holidays: holidays, calendar: calendar)
    }

    private static func previousBusinessDay(
        onOrBefore date: Date,
        holidays: Set<String>,
        calendar: Calendar
    ) -> Date {
        var candidate = calendar.startOfDay(for: date)
        while calendar.isDateInWeekend(candidate) || holidays.contains(dayKey(for: candidate, calendar: calendar)) {
            candidate = calendar.date(byAdding: .day, value: -1, to: candidate) ?? candidate
        }
        return candidate
    }

    private static func nextBusinessDay(
        onOrAfter date: Date,
        holidays: Set<String>,
        calendar: Calendar
    ) -> Date {
        var candidate = date
        while calendar.isDateInWeekend(candidate) || holidays.contains(dayKey(for: candidate, calendar: calendar)) {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }

    private static func scheduledDate(
        day: Int,
        hour: Int,
        minute: Int,
        cycleStarting cycleStart: Date,
        calendar: Calendar
    ) -> Date {
        let start = calendar.startOfDay(for: cycleStart)
        let sameMonth = date(
            day: day,
            hour: hour,
            minute: minute,
            monthContaining: start,
            calendar: calendar
        )
        if sameMonth >= start { return sameMonth }
        let nextMonth = offset(1, from: firstDayOfMonth(containing: start, calendar: calendar), calendar: calendar)
        return date(day: day, hour: hour, minute: minute, monthContaining: nextMonth, calendar: calendar)
    }

    private static func date(
        day: Int,
        hour: Int,
        minute: Int,
        monthContaining date: Date,
        calendar: Calendar
    ) -> Date {
        let monthRange = calendar.range(of: .day, in: .month, for: date)
        let validDay = min(max(day, 1), monthRange?.count ?? day)
        let month = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: month.year,
            month: month.month,
            day: validDay,
            hour: hour,
            minute: minute
        )) ?? date
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
    var holidayDateSet: Set<String> { Set(holidayDates) }

    func cycleKey(for date: Date, calendar: Calendar = .current) -> String {
        CycleDate.key(
            for: date,
            payday: payday,
            holidays: holidayDateSet,
            calendar: calendar
        )
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

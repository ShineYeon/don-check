import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case mismatch(String)

    var description: String {
        switch self {
        case .mismatch(let message): return message
        }
    }
}

@main
enum ModelRegressionTests {
    static func main() throws {
        try testMonthEndDates()
        try testLegacyAutomaticTransferData()
        try testV4RepositoryMigration()
        try testHolidayCalendarMatching()
        try testHolidayEventDateExpansion()
        print("Model regression tests passed")
    }

    private static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private static func dayKey(_ date: Date) -> String {
        CycleDate.dayKey(for: date, calendar: calendar)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure.mismatch(message) }
    }

    private static func monthEndItem() -> SavingsItem {
        SavingsItem(
            name: "말일 자동이체",
            amount: 100_000,
            debitDay: 1,
            reminderHour: 8,
            reminderMinute: 30,
            requiresAutomaticTransferConfirmation: true,
            automaticTransferDay: 15,
            automaticTransferUsesMonthEnd: true
        )
    }

    private static func testMonthEndDates() throws {
        let item = monthEndItem()

        let leapFebruary = CycleDate.automaticTransferDate(
            for: item,
            cycleStarting: date(2028, 2, 1),
            calendar: calendar
        )
        try expect(dayKey(leapFebruary) == "2028-02-29", "윤년 2월 말일은 29일이어야 합니다.")

        let april = CycleDate.automaticTransferDate(
            for: item,
            cycleStarting: date(2026, 4, 1),
            calendar: calendar
        )
        try expect(dayKey(april) == "2026-04-30", "4월 말일은 30일이어야 합니다.")

        let weekendFebruary = CycleDate.automaticTransferDate(
            for: item,
            cycleStarting: date(2026, 2, 1),
            calendar: calendar
        )
        try expect(dayKey(weekendFebruary) == "2026-03-02", "주말인 2월 말일은 다음 영업일이어야 합니다.")
        try expect(calendar.component(.hour, from: weekendFebruary) == 8, "영업일 보정 후 알림 시각을 유지해야 합니다.")
        try expect(calendar.component(.minute, from: weekendFebruary) == 30, "영업일 보정 후 알림 분을 유지해야 합니다.")

        let holidayAdjusted = CycleDate.automaticTransferDate(
            for: item,
            cycleStarting: date(2026, 2, 1),
            holidays: ["2026-03-02"],
            calendar: calendar
        )
        try expect(dayKey(holidayAdjusted) == "2026-03-03", "말일 이후 공휴일도 건너뛰어야 합니다.")
    }

    private static func testLegacyAutomaticTransferData() throws {
        let legacyItem = SavingsItem(
            name: "기존 항목",
            amount: 50_000,
            debitDay: 5,
            requiresAutomaticTransferConfirmation: true,
            automaticTransferDay: 10
        )
        let encoded = try JSONEncoder().encode(legacyItem)
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        object.removeValue(forKey: "automaticTransferUsesMonthEnd")
        let legacyPayload = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SavingsItem.self, from: legacyPayload)

        try expect(decoded.automaticTransferSchedule == .day(10), "기존 숫자 자동이체일은 그대로 복원되어야 합니다.")
        try expect(!decoded.automaticTransferUsesMonthEnd, "기존 데이터는 말일 옵션이 기본으로 꺼져야 합니다.")

        let monthEndDecoded = try JSONDecoder().decode(
            SavingsItem.self,
            from: JSONEncoder().encode(monthEndItem())
        )
        try expect(monthEndDecoded.automaticTransferSchedule == .monthEnd, "말일 옵션은 저장 후 복원되어야 합니다.")
    }

    private static func testV4RepositoryMigration() throws {
        let suiteName = "DonCheck.ModelRegressionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyItem = SavingsItem(
            name: "v4 항목",
            amount: 70_000,
            debitDay: 5,
            requiresAutomaticTransferConfirmation: true,
            automaticTransferDay: 12
        )
        let encoded = try JSONEncoder().encode(ChecklistData(items: [legacyItem]))
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        var items = object["items"] as! [[String: Any]]
        items[0].removeValue(forKey: "automaticTransferUsesMonthEnd")
        object["items"] = items
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: "checklist-data-v4")

        let loaded = ChecklistRepository(defaults: defaults).load()

        try expect(loaded.items.first?.automaticTransferSchedule == .day(12), "v4 숫자 자동이체일을 보존해야 합니다.")
        try expect(defaults.data(forKey: "checklist-data-v5") != nil, "migration 결과를 v5 key에 저장해야 합니다.")
    }

    private static func testHolidayCalendarMatching() throws {
        try expect(
            HolidayDateImport.matchesCalendar(title: "대한민국의 휴일"),
            "휴일이라는 한국어 캘린더 이름을 찾아야 합니다."
        )
        try expect(
            HolidayDateImport.matchesCalendar(title: "South Korea Public Holidays"),
            "영문 Public Holidays 캘린더를 찾아야 합니다."
        )
        try expect(
            HolidayDateImport.matchesCalendar(title: "대한민국", sourceTitle: "구독 공휴일"),
            "source 이름도 공휴일 판정에 사용해야 합니다."
        )
        try expect(
            !HolidayDateImport.matchesCalendar(title: "개인 일정"),
            "일반 캘린더를 공휴일로 오인하면 안 됩니다."
        )
    }

    private static func testHolidayEventDateExpansion() throws {
        let timedKeys = HolidayDateImport.dateKeys(
            startDate: date(2026, 5, 5, hour: 9),
            endDate: date(2026, 5, 5, hour: 10),
            calendar: calendar
        )
        try expect(timedKeys == ["2026-05-05"], "종일 플래그가 없는 당일 일정도 날짜를 추출해야 합니다.")

        let multiDayKeys = HolidayDateImport.dateKeys(
            startDate: date(2026, 10, 3),
            endDate: date(2026, 10, 5),
            calendar: calendar
        )
        try expect(
            multiDayKeys == ["2026-10-03", "2026-10-04"],
            "종일 일정의 종료일은 exclusive로 처리해야 합니다."
        )
    }
}

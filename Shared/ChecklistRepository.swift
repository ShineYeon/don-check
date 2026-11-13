import Foundation

final class ChecklistRepository {
    static let shared = ChecklistRepository()

    private let dataKey = "checklist-data-v2"
    private let legacyDataKey = "checklist-data-v1"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppConfig.appGroupIdentifier)) {
        self.defaults = defaults ?? .standard
    }

    func load() -> ChecklistData {
        if let encoded = defaults.data(forKey: dataKey),
           let decoded = try? decoder.decode(ChecklistData.self, from: encoded) {
            return decoded
        }

        guard let legacyEncoded = defaults.data(forKey: legacyDataKey),
              var migrated = try? decoder.decode(ChecklistData.self, from: legacyEncoded) else {
            return ChecklistData()
        }

        migrated.payday = 1
        migrated.completions = migrated.completions.map { record in
            guard record.cycleKey.split(separator: "-").count == 2,
                  let month = CycleDate.date(for: record.cycleKey) else {
                return record
            }
            return CompletionRecord(
                itemID: record.itemID,
                cycleKey: CycleDate.key(for: month, payday: migrated.payday),
                completedAt: record.completedAt
            )
        }
        save(migrated)
        return migrated
    }

    func save(_ data: ChecklistData) {
        guard let encoded = try? encoder.encode(data) else { return }
        defaults.set(encoded, forKey: dataKey)
    }

    @discardableResult
    func setCompletion(itemID: UUID, cycleKey: String, isComplete: Bool) -> ChecklistData {
        var data = load()
        data.completions.removeAll { $0.itemID == itemID && $0.cycleKey == cycleKey }
        if isComplete {
            data.completions.append(CompletionRecord(itemID: itemID, cycleKey: cycleKey, completedAt: .now))
        }
        save(data)
        return data
    }

    func pruneHistory(in data: inout ChecklistData, keepingMonths count: Int = 24) {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .month, value: -count, to: .now) ?? .distantPast
        data.completions.removeAll { record in
            guard let month = CycleDate.date(for: record.cycleKey, calendar: calendar) else { return true }
            return month < cutoff
        }
    }
}

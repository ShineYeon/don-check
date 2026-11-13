import SwiftUI
import WidgetKit

struct ChecklistEntry: TimelineEntry {
    let date: Date
    let data: ChecklistData
    let cycleKey: String
}

struct ChecklistProvider: TimelineProvider {
    func placeholder(in context: Context) -> ChecklistEntry {
        ChecklistEntry(date: .now, data: sampleData, cycleKey: sampleData.cycleKey(for: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (ChecklistEntry) -> Void) {
        let data = context.isPreview ? sampleData : ChecklistRepository.shared.load()
        completion(ChecklistEntry(date: .now, data: data, cycleKey: data.cycleKey(for: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ChecklistEntry>) -> Void) {
        let now = Date.now
        let data = ChecklistRepository.shared.load()
        let entry = ChecklistEntry(date: now, data: data, cycleKey: data.cycleKey(for: now))
        let nextPayday = CycleDate.nextBoundary(
            after: now,
            payday: data.payday,
            holidays: data.holidayDateSet
        )
        completion(Timeline(entries: [entry], policy: .after(nextPayday)))
    }

    private var sampleData: ChecklistData {
        ChecklistData(items: [
            SavingsItem(name: "청약저축", amount: 250_000, debitDay: 2),
            SavingsItem(name: "연금저축", amount: 300_000, debitDay: 25)
        ])
    }
}

struct DonCheckWidget: Widget {
    let kind = "DonCheckWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ChecklistProvider()) { entry in
            ChecklistWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("저축 체크리스트")
        .description("남은 저축 항목을 확인하고 바로 체크합니다.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular])
    }
}

private struct ChecklistWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ChecklistEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: progress) {
                Image(systemName: "checklist")
            } currentValueLabel: {
                Text("\(remainingCount)")
            }
            .gaugeStyle(.accessoryCircular)

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("이번 저축 주기")
                    .font(.headline)
                Text("\(remainingCount)개 · \(remainingAmount.formatted(.number.notation(.compactName)))원 남음")
                    .font(.caption)
                ProgressView(value: progress)
            }

        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                Label("이번 저축 주기", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Text("\(remainingCount)개")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("\(remainingAmount.formatted(.number))원 남음")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: progress)
                    .tint(.mint)
            }

        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("이번 저축 주기", systemImage: "checklist")
                        .font(.headline)
                    Spacer()
                    Text("\(completedCount)/\(entry.data.items.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress)
                    .tint(.mint)

                if entry.data.items.isEmpty {
                    Spacer()
                    Text("앱에서 저축 항목을 추가하세요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(Array(entry.data.items.prefix(family == .systemLarge ? 7 : 3))) { item in
                        let depositComplete = entry.data.isStepComplete(
                            item.id,
                            cycleKey: entry.cycleKey,
                            step: .deposit
                        )
                        let transferComplete = entry.data.isStepComplete(
                            item.id,
                            cycleKey: entry.cycleKey,
                            step: .automaticTransfer
                        )
                        HStack(spacing: 6) {
                            Text(item.name)
                                .lineLimit(1)
                                .strikethrough(entry.data.isComplete(item.id, cycleKey: entry.cycleKey))
                            Spacer(minLength: 2)
                            WidgetStepButton(
                                title: "입금",
                                item: item,
                                cycleKey: entry.cycleKey,
                                step: .deposit,
                                isComplete: depositComplete
                            )
                            if item.requiresAutomaticTransferConfirmation {
                                WidgetStepButton(
                                    title: "저축",
                                    item: item,
                                    cycleKey: entry.cycleKey,
                                    step: .automaticTransfer,
                                    isComplete: transferComplete
                                )
                            }
                        }
                        .font(.caption)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var completedCount: Int { entry.data.completedCount(cycleKey: entry.cycleKey) }
    private var remainingCount: Int { max(entry.data.items.count - completedCount, 0) }
    private var remainingAmount: Int { entry.data.remainingAmount(cycleKey: entry.cycleKey) }
    private var progress: Double {
        entry.data.items.isEmpty ? 0 : Double(completedCount) / Double(entry.data.items.count)
    }
}

private struct WidgetStepButton: View {
    let title: String
    let item: SavingsItem
    let cycleKey: String
    let step: CompletionStep
    let isComplete: Bool

    var body: some View {
        Button(intent: ToggleSavingsItemIntent(
            itemID: item.id.uuidString,
            cycleKey: cycleKey,
            step: step,
            nextValue: !isComplete
        )) {
            VStack(spacing: 1) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                Text(title)
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundStyle(isComplete ? .mint : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(isComplete ? "완료" : "미완료")")
    }
}


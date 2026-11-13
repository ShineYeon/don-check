import ActivityKit
import SwiftUI
import WidgetKit

struct SavingsChecklistLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SavingsChecklistAttributes.self) { context in
            LockScreenChecklistView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.88))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("저축", systemImage: "checkmark.circle")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.remainingCount)개 남음")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 7) {
                        ForEach(Array(context.state.items.filter { !$0.isComplete }.prefix(3))) { item in
                            ChecklistActivityRow(item: item, cycleKey: context.state.cycleKey)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.mint)
            } compactTrailing: {
                Text("\(context.state.remainingCount)")
                    .font(.caption.bold().monospacedDigit())
            } minimal: {
                ZStack {
                    Circle().fill(.mint)
                    Text("\(context.state.remainingCount)")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.black)
                }
            }
            .keylineTint(.mint)
        }
    }
}

private struct LockScreenChecklistView: View {
    let state: SavingsChecklistAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(state.title, systemImage: "checklist")
                        .font(.headline)
                    Text(state.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(state.remainingCount)개 남음")
                        .font(.subheadline.weight(.semibold))
                    Text(state.remainingAmount, format: .currency(code: "KRW").precision(.fractionLength(0)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(state.items.prefix(4))) { item in
                ChecklistActivityRow(item: item, cycleKey: state.cycleKey)
            }

            if state.items.count > 4 {
                Text("외 \(state.items.count - 4)개 · 앱에서 전체 보기")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}

private struct ChecklistActivityRow: View {
    let item: LiveChecklistItem
    let cycleKey: String

    var body: some View {
        Button(intent: ToggleSavingsItemIntent(
            itemID: item.id.uuidString,
            cycleKey: cycleKey,
            nextValue: !item.isComplete
        )) {
            HStack(spacing: 8) {
                Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isComplete ? .mint : .secondary)
                Text(item.name)
                    .lineLimit(1)
                    .strikethrough(item.isComplete)
                Spacer()
                Text(item.amount, format: .number.notation(.compactName))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

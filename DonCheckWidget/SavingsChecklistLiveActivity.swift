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
        HStack(spacing: 8) {
            Text(item.name)
                .lineLimit(1)
                .strikethrough(item.isComplete)
            Spacer(minLength: 4)
            ActivityStepButton(
                title: "입금",
                itemID: item.id,
                cycleKey: cycleKey,
                step: .deposit,
                isComplete: item.isDepositComplete
            )
            if item.requiresAutomaticTransferConfirmation {
                ActivityStepButton(
                    title: "저축",
                    itemID: item.id,
                    cycleKey: cycleKey,
                    step: .automaticTransfer,
                    isComplete: item.isAutomaticTransferComplete
                )
            }
        }
        .font(.caption)
    }
}

private struct ActivityStepButton: View {
    let title: String
    let itemID: UUID
    let cycleKey: String
    let step: CompletionStep
    let isComplete: Bool

    var body: some View {
        Button(intent: ToggleSavingsItemIntent(
            itemID: itemID.uuidString,
            cycleKey: cycleKey,
            step: step,
            nextValue: !isComplete
        )) {
            Label(title, systemImage: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? .mint : .secondary)
        }
        .buttonStyle(.plain)
    }
}

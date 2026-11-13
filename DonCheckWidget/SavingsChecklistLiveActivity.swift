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
                    HStack(spacing: 6) {
                        DonCheckMark(size: 22)
                        Text("DonCheck")
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedStageSummary(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 7) {
                        ForEach(Array(context.state.items.filter { !$0.isComplete }.prefix(3))) { item in
                            ChecklistActivityRow(item: item, cycleKey: context.state.cycleKey)
                        }
                    }
                }
            } compactLeading: {
                DonCheckMark(size: 20)
                    .accessibilityLabel("돈 체크")
            } compactTrailing: {
                CompactStageSummary(state: context.state)
            } minimal: {
                DonCheckMark(size: 20)
                    .accessibilityLabel("돈 체크, \(context.state.stageSummaryText)")
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
                    Text("입금 \(state.depositCompletedCount)/\(state.totalCount)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    if state.automaticTransferItemCount > 0 {
                        Text("저축 \(state.automaticTransferCompletedCount)/\(state.automaticTransferItemCount)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                    }
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

private struct DonCheckMark: View {
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "wonsign.circle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.mint)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white, .black)
                .offset(x: size * 0.08, y: size * 0.08)
        }
        .frame(width: size * 1.08, height: size * 1.08)
    }
}

private struct CompactStageSummary: View {
    let state: SavingsChecklistAttributes.ContentState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 3) {
                CompactMetric(symbol: "list.bullet", value: state.totalCount, color: .primary)
                CompactMetric(
                    symbol: "tray.and.arrow.down.fill",
                    value: state.depositCompletedCount,
                    color: .mint
                )
                if state.automaticTransferItemCount > 0 {
                    CompactMetric(
                        symbol: "banknote.fill",
                        value: state.automaticTransferCompletedCount,
                        color: .orange
                    )
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            Text(compactFallback)
                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                .fixedSize(horizontal: true, vertical: false)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.stageSummaryText)
    }

    private var compactFallback: String {
        if state.automaticTransferItemCount > 0 {
            return "\(state.totalCount)·\(state.depositCompletedCount)·\(state.automaticTransferCompletedCount)"
        }
        return "\(state.totalCount)·\(state.depositCompletedCount)"
    }
}

private struct CompactMetric: View {
    let symbol: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
            Text("\(value)")
                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
        }
        .foregroundStyle(color)
    }
}

private struct ExpandedStageSummary: View {
    let state: SavingsChecklistAttributes.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("전체 \(state.totalCount)개")
                .font(.caption.weight(.semibold).monospacedDigit())
            Text("입금 \(state.depositCompletedCount)개")
                .foregroundStyle(.mint)
            if state.automaticTransferItemCount > 0 {
                Text("저축 \(state.automaticTransferCompletedCount)개")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption2.weight(.semibold).monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.stageSummaryText)
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

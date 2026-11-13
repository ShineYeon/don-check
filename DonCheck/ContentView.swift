import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ChecklistStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var editorItem: SavingsItem?
    @State private var showingNewItem = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SummaryCard(
                        depositCompleted: store.depositCompletedCount,
                        transferCompleted: store.automaticTransferCompletedCount,
                        transferTotal: store.automaticTransferItemCount,
                        fullyCompleted: store.completedCount,
                        total: store.data.items.count,
                        remainingAmount: store.remainingAmount
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("이번 주기") {
                    if store.data.items.isEmpty {
                        ContentUnavailableView(
                            "저축 항목이 없어요",
                            systemImage: "checklist",
                            description: Text("오른쪽 위 + 버튼으로 첫 항목을 추가하세요.")
                        )
                    } else {
                        ForEach(store.data.items) { item in
                            SavingsItemRow(
                                item: item,
                                depositComplete: store.isStepComplete(item, step: .deposit),
                                transferComplete: store.isStepComplete(item, step: .automaticTransfer),
                                toggleDeposit: {
                                    withAnimation(.snappy) { store.toggle(item, step: .deposit) }
                                },
                                toggleTransfer: {
                                    withAnimation(.snappy) { store.toggle(item, step: .automaticTransfer) }
                                },
                                edit: { editorItem = item }
                            )
                        }
                        .onDelete(perform: store.delete)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(monthTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewItem = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewItem) {
                ItemEditorView(item: nil) { store.save($0) }
            }
            .sheet(item: $editorItem) { item in
                ItemEditorView(item: item) { store.save($0) }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    store.reload()
                    Task { await store.refreshNotificationStatus() }
                }
            }
        }
    }

    private var monthTitle: String {
        let start = CycleDate.date(for: store.cycleKey) ?? .now
        return start.formatted(.dateTime.year().month(.wide)) + " 저축"
    }
}

private struct SummaryCard: View {
    let depositCompleted: Int
    let transferCompleted: Int
    let transferTotal: Int
    let fullyCompleted: Int
    let total: Int
    let remainingAmount: Int

    private var progress: Double {
        total == 0 ? 0 : Double(fullyCompleted) / Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("남은 입금액")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(remainingAmount, format: .currency(code: "KRW").precision(.fractionLength(0)))
                        .font(.system(.title, design: .rounded, weight: .bold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("입금 \(depositCompleted)/\(total)")
                    if transferTotal > 0 {
                        Text("저축 \(transferCompleted)/\(transferTotal)")
                    }
                }
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(.mint)
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

private struct SavingsItemRow: View {
    let item: SavingsItem
    let depositComplete: Bool
    let transferComplete: Bool
    let toggleDeposit: () -> Void
    let toggleTransfer: () -> Void
    let edit: () -> Void

    private var isComplete: Bool {
        depositComplete && (!item.requiresAutomaticTransferConfirmation || transferComplete)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: edit) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .strikethrough(isComplete)
                            .foregroundStyle(isComplete ? .secondary : .primary)
                        Text("매월 \(item.debitDay)일 · \(String(format: "%02d:%02d", item.reminderHour, item.reminderMinute))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.amount, format: .currency(code: "KRW").precision(.fractionLength(0)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isComplete ? .secondary : .primary)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 16) {
                StepCheckButton(
                    title: "입금 완료",
                    isComplete: depositComplete,
                    action: toggleDeposit
                )
                if item.requiresAutomaticTransferConfirmation {
                    StepCheckButton(
                        title: "저축 완료",
                        isComplete: transferComplete,
                        action: toggleTransfer
                    )
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct StepCheckButton: View {
    let title: String
    let isComplete: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(isComplete ? .mint : .secondary)
        }
        .buttonStyle(.plain)
    }
}

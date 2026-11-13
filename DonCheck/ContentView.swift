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
                        completed: store.completedCount,
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
                            SavingsItemRow(item: item, isComplete: store.isComplete(item)) {
                                withAnimation(.snappy) { store.toggle(item) }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { editorItem = item }
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
    let completed: Int
    let total: Int
    let remainingAmount: Int

    private var progress: Double {
        total == 0 ? 0 : Double(completed) / Double(total)
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
                Text("\(completed)/\(total)")
                    .font(.headline.monospacedDigit())
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
    let isComplete: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isComplete ? .mint : .secondary)
            }
            .buttonStyle(.plain)

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
        .padding(.vertical, 4)
    }
}

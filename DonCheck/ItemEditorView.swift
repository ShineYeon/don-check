import SwiftUI

struct ItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SavingsItem
    private let isNew: Bool
    private let onSave: (SavingsItem) -> Void

    init(item: SavingsItem?, onSave: @escaping (SavingsItem) -> Void) {
        let initial = item ?? SavingsItem(name: "", amount: 0, debitDay: 1)
        _draft = State(initialValue: initial)
        isNew = item == nil
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("저축 정보") {
                    TextField("예: 청약저축", text: $draft.name)
                    TextField("금액", value: $draft.amount, format: .number)
                        .keyboardType(.numberPad)
                }

                Section("완료 단계") {
                    Toggle("자동이체 후 저축 완료 확인", isOn: $draft.requiresAutomaticTransferConfirmation)
                    if draft.requiresAutomaticTransferConfirmation {
                        Stepper(
                            "자동이체일: 매월 \(draft.automaticTransferDay)일",
                            value: $draft.automaticTransferDay,
                            in: 1...31
                        )
                    }
                    Text(draft.requiresAutomaticTransferConfirmation
                         ? "주말·공휴일을 보정한 실제 자동이체일 하루 전부터 저축 완료 확인이 잠금화면과 Dynamic Island에 표시됩니다."
                         : "입금 완료만 체크하면 이 항목이 완료됩니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("매월 일정") {
                    Stepper("출금일: \(draft.debitDay)일", value: $draft.debitDay, in: 1...31)
                    DatePicker(
                        "알림 시간",
                        selection: reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    Stepper(
                        draft.leadDays == 0 ? "사전 알림 없음" : "\(draft.leadDays)일 전에도 알림",
                        value: $draft.leadDays,
                        in: 0...14
                    )
                }

                Section("완료하지 않았을 때") {
                    Stepper(
                        draft.followUpCount == 0 ? "재알림 없음" : "이후 \(draft.followUpCount)일간 재알림",
                        value: $draft.followUpCount,
                        in: 0...7
                    )
                    Text("각 단계를 체크하면 해당 단계의 남은 알림은 자동으로 취소됩니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isNew ? "저축 항목 추가" : "저축 항목 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.amount <= 0)
                }
            }
        }
    }

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: draft.reminderHour, minute: draft.reminderMinute)) ?? .now
        } set: { value in
            let components = Calendar.current.dateComponents([.hour, .minute], from: value)
            draft.reminderHour = components.hour ?? 8
            draft.reminderMinute = components.minute ?? 0
        }
    }
}

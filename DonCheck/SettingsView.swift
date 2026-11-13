import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ChecklistStore
    @State private var pendingPayday: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section("체크 주기") {
                    Picker("월급일", selection: Binding(
                        get: { store.data.payday },
                        set: { pendingPayday = $0 }
                    )) {
                        ForEach(1...31, id: \.self) { day in
                            Text("매월 \(day)일").tag(day)
                        }
                    }

                    Text("월급일 00:00부터 새 저축 주기가 시작되고 모든 항목이 빈 체크박스로 표시됩니다. 29~31일이 없는 달에는 그 달의 마지막 날을 사용합니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("잠금화면 체크리스트") {
                    Button("지금 Live 체크리스트 띄우기") {
                        Task { await store.showLiveChecklistNow() }
                    }
                    .disabled(store.data.items.isEmpty || store.completedCount == store.data.items.count)

                    Text("일반 알림과 별도로 잠금화면과 Dynamic Island에 표시됩니다. iOS 26 이상에서는 설정한 사전 알림일과 출금일에 자동 시작됩니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("알림") {
                    LabeledContent("권한", value: store.notificationAuthorized ? "허용됨" : "필요함")

                    if store.notificationAuthorized {
                        Button("알림 일정 다시 만들기") {
                            Task { await store.rescheduleNotifications() }
                        }
                    } else {
                        Button("알림 허용하기") {
                            Task { await store.requestNotifications() }
                        }
                    }

                    Button("iPhone 알림 설정 열기") {
                        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                }

                Section("작동 방식") {
                    Text("각 항목의 완료 여부는 월급일로 구분한 주기별로 보관됩니다. 새 주기가 시작되어도 이전 완료 기록은 삭제되지 않습니다.")
                    Text("iOS 정책상 알림을 화면 맨 위에 영구 고정할 수는 없습니다. 홈 화면과 잠금 화면 위젯을 함께 사용하세요.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "월급일을 변경할까요?",
                isPresented: Binding(
                    get: { pendingPayday != nil },
                    set: { if !$0 { pendingPayday = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let pendingPayday {
                    Button("매월 \(pendingPayday)일로 변경") {
                        store.updatePayday(pendingPayday)
                        self.pendingPayday = nil
                    }
                }
                Button("취소", role: .cancel) {
                    pendingPayday = nil
                }
            } message: {
                Text("현재 체크 주기가 달라질 수 있으며, 알림과 잠금화면 체크리스트가 새 일정으로 다시 만들어집니다.")
            }
            .alert("Live Activity", isPresented: Binding(
                get: { store.liveActivityMessage != nil },
                set: { if !$0 { store.liveActivityMessage = nil } }
            )) {
                Button("확인") { store.liveActivityMessage = nil }
            } message: {
                Text(store.liveActivityMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }
}

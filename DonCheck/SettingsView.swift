import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ChecklistStore

    var body: some View {
        NavigationStack {
            Form {
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
                    Text("각 항목의 완료 여부는 월별로 보관됩니다. 달이 바뀌면 새 체크리스트가 자동으로 시작되고 이전 기록은 유지됩니다.")
                    Text("iOS 정책상 알림을 화면 맨 위에 영구 고정할 수는 없습니다. 홈 화면과 잠금 화면 위젯을 함께 사용하세요.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
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

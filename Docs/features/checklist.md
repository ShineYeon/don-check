# 체크리스트와 월별 주기

## 1. 책임

체크리스트 기능은 다음 질문에 답한다.

- 어떤 저축 항목이 존재하는가?
- 이번 달에 어떤 항목이 완료되었는가?
- 현재 남은 금액과 완료 개수는 얼마인가?
- 29~31일 출금 항목을 짧은 달에서 언제 처리할 것인가?

구현은 `Shared/Models.swift`, `DonCheck/ChecklistStore.swift`, `DonCheck/ItemEditorView.swift`에 분산되어 있다.

## 2. 도메인 모델

### 2.1 SavingsItem

```swift
struct SavingsItem: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var amount: Int
    var debitDay: Int
    var reminderHour: Int
    var reminderMinute: Int
    var leadDays: Int
    var followUpCount: Int
    var createdAt: Date
}
```

필드 의미:

| 필드 | 의미 | 현재 UI 범위 |
|---|---|---:|
| `id` | 항목의 영구 식별자 | UUID 자동 생성 |
| `name` | 화면과 알림 제목 | 빈 문자열 저장 불가 |
| `amount` | 월 준비 금액, 원 단위 | 1 이상 |
| `debitDay` | 매월 출금 예정 일자 | 1...31 |
| `reminderHour` | 알림 시 | 0...23 |
| `reminderMinute` | 알림 분 | 0...59 |
| `leadDays` | 출금 전 사전 알림 일수 | 0...14 |
| `followUpCount` | 출금 후 일별 재알림 수 | 0...7 |
| `createdAt` | 생성 시각 | 자동 설정 |

`amount`는 통화 소수점을 사용하지 않는다. 다른 통화를 지원하려면 통화 코드와 minor unit 정책을 모델에 추가해야 한다.

### 2.2 CompletionRecord

```swift
struct CompletionRecord: Codable, Hashable {
    var itemID: UUID
    var cycleKey: String
    var completedAt: Date
}
```

완료 상태를 `SavingsItem` 안의 Boolean으로 저장하지 않는다. 같은 항목이 매월 반복되므로 항목 정의와 월별 실행 기록을 분리한다.

논리적 unique key는 `(itemID, cycleKey)`다. 저장 전에 동일 조합을 제거하므로 정상 경로에서는 한 건만 존재한다.

## 3. 월 키

`CycleDate.key(for:)`는 현재 calendar에서 연도와 월을 가져와 `yyyy-MM` 문자열을 만든다.

```text
2026년 11월 13일 → 2026-11
2027년  1월  1일 → 2027-01
```

완료 판정:

```swift
data.isComplete(item.id, cycleKey: "2026-11")
```

12월에 완료했던 항목도 1월에는 `(같은 itemID, 2027-01)` 기록이 없으므로 미완료다. 별도 reset timer나 background task가 필요하지 않은 이유다.

## 4. 출금일 계산

`CycleDate.dueDate(for:monthContaining:)`는 해당 월의 실제 일수와 `debitDay` 중 작은 값을 사용한다.

| 설정 | 대상 월 | 실제 날짜 |
|---:|---|---:|
| 31일 | 1월 | 31일 |
| 31일 | 2월(평년) | 28일 |
| 31일 | 2월(윤년) | 29일 |
| 31일 | 4월 | 30일 |

시간대는 `Calendar.current.timeZone`을 사용한다. 사용자가 기기 시간대를 바꾸면 다음 재계산부터 새 시간대가 적용된다.

## 5. CRUD 흐름

### 생성

`ItemEditorView`가 새로운 `SavingsItem` draft를 만들고 저장 시 `ChecklistStore.save(_:)`를 호출한다. 기존 ID가 없으므로 `data.items` 끝에 추가한다.

### 수정

목록 row 자체를 탭하면 편집 sheet를 연다. 동일 ID를 가진 항목 index를 찾아 값을 교체한다. 완료 기록은 유지된다.

출금일이나 알림 시각을 바꾸면 `persist()`가 모든 pending notification과 pending Live Activity를 새 설정으로 다시 만든다.

### 삭제

SwiftUI list의 delete gesture가 `ChecklistStore.delete(at:)`를 호출한다. 항목뿐 아니라 해당 `itemID`의 모든 과거 완료 기록도 제거한다.

삭제는 현재 undo를 지원하지 않는다.

## 6. 완료 토글

앱 내부 토글은 현재 월 키를 사용한다.

1. 동일 item/month 완료 기록 제거
2. 다음 상태가 완료라면 새 `CompletionRecord` 추가
3. 저장 및 파생 상태 재구성

위젯과 Live Activity는 렌더링 당시의 `cycleKey`를 intent parameter로 전달한다. notification action도 payload에 들어 있던 `cycleKey`를 사용하므로 알림이 월 경계 후 늦게 눌려도 원래 대상 월을 완료 처리한다.

## 7. 집계 값

`ChecklistData` extension이 다음 값을 계산한다.

- `completedCount(cycleKey:)`: 완료된 항목 수
- `remainingAmount(cycleKey:)`: 미완료 항목 amount 합계
- `isComplete(_:cycleKey:)`: 개별 항목 완료 여부

현재는 호출할 때마다 배열을 순회한다. 개인용 데이터 규모에서는 충분하지만 항목이나 history가 많아지면 completion lookup index를 만들 수 있다.

## 8. history 보존

`ChecklistRepository.pruneHistory(in:keepingMonths:)`는 기본적으로 24개월 이전 completion을 제거한다. 이 정리는 앱이 `persist()`할 때만 발생한다.

따라서 사용자가 2년 이상 앱을 열기만 하고 아무 데이터도 변경하지 않으면 오래된 기록은 그대로 남을 수 있다. 현재 저장 규모에서는 문제되지 않으며, 엄격한 보존 정책이 필요하면 launch 시에도 prune/save해야 한다.

## 9. 경계 조건

수정 시 다음 케이스를 반드시 검증한다.

- 1월 31일 → 2월 말일 보정
- 윤년 2월 29일
- 12월 → 다음 해 1월 cycle 전환
- 출금일 당일 알림 시각 이전/이후
- 월말 사전 알림이 이전 달로 넘어가는 경우
- 지난달 notification action을 이번 달에 누르는 경우
- 완료된 항목의 출금일을 수정하는 경우
- 항목 삭제 후 widget timeline refresh

## 10. 향후 개선

- 월급일을 경계로 한 체크 주기와 항목별 2단계 완료 체크는 [제품 로드맵](../product/roadmap.md)에 요구사항과 migration 방향을 정리한다.
- 월별 history 조회 UI
- 완료 취소 audit 기록
- 항목 순서 재정렬
- 계좌 별칭과 메모
- 휴일/영업일 보정 규칙
- 월별 금액 override
- completion unique constraint를 보장하는 database 도입

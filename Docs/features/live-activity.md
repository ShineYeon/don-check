# Live Activity와 고정 유지 모드

## 1. 목적

일반 notification은 Notification Center에서 다른 앱 알림 아래로 이동할 수 있다. DonCheck는 중요한 저축 준비 기간에 체크리스트를 잠금 화면과 Dynamic Island의 Live Activity 영역에 노출해 가시성을 높인다.

Live Activity는 일반 notification을 영구 고정하는 기능이 아니다. ActivityKit의 별도 시스템 surface이며 표시 시간, 개수, 우선순위는 iOS가 통제한다.

구현 파일:

- `Shared/SavingsChecklistActivity.swift`
- `Shared/ToggleSavingsItemIntent.swift`
- `DonCheckWidget/SavingsChecklistLiveActivity.swift`
- `DonCheck/ChecklistStore.swift`

## 2. Activity 데이터 모델

### 2.1 Attributes

```swift
struct SavingsChecklistAttributes: ActivityAttributes {
    var eventKey: String
    var scheduledStart: Date?
}
```

- `eventKey`: 현재 시작 또는 relay slot을 식별하는 문자열
- `scheduledStart`: relay anchor 계산에 사용하는 시각

`scheduledStart`가 optional인 이유는 이 필드가 추가되기 전 빌드에서 생성한 activity payload를 decode할 수 있게 하기 위해서다. Activity attributes를 변경할 때는 이미 시스템에 남아 있는 activity와의 backward compatibility를 고려해야 한다.

### 2.2 ContentState

```swift
struct ContentState: Codable, Hashable {
    var title: String
    var subtitle: String
    var cycleKey: String
    var items: [LiveChecklistItem]
}
```

Content state에는 렌더링과 체크 intent에 필요한 월급 주기 키와 항목 snapshot을 넣는다. `remainingCount`, `completedCount`, `remainingAmount`는 computed property다.

각 `LiveChecklistItem`은 `requiresAutomaticTransferConfirmation`, `isDepositComplete`, `isAutomaticTransferComplete`를 포함한다. 이전 active payload의 단일 `isComplete` 값은 호환 decoder에서 입금 완료로 해석한다.

ActivityKit content payload에는 크기 제한이 있다. 현재 모든 항목을 payload에 넣지만 UI에는 일부만 표시한다. 항목 수가 커질 경우 미완료 상위 N개와 요약 값만 보내는 방식으로 변경해야 한다.

## 3. Presentation

### Lock Screen

표시 내용:

- `이번 저축 주기` 제목
- 상태 subtitle
- 미완료 개수
- 남은 금액
- 최대 4개 항목 체크 row
- 4개 초과 시 `외 N개 · 앱에서 전체 보기`

현재 `state.items.prefix(4)`를 사용하므로 완료 항목도 앞쪽에 있으면 표시 공간을 차지한다. 미완료 우선 정렬이 필요하면 activity content 생성 또는 view에서 정렬해야 한다.

### Dynamic Island compact

- leading: checkmark icon
- trailing: 미완료 개수

단계별 입금/저축 집계와 DonCheck 전용 leading icon으로 바꾸는 디자인은 [제품 로드맵 NEXT-003](../product/roadmap.md#next-003-dynamic-island-단계별-요약-디자인)에 정의되어 있으며 아직 구현 전이다.

### Dynamic Island minimal

원형 mint background에 미완료 개수를 표시한다. 다른 Live Activity가 동시에 있을 때 시스템이 minimal presentation을 사용할 수 있다.

### Dynamic Island expanded

- leading: `저축`
- trailing: `N개 남음`
- bottom: 미완료 항목 최대 3개

## 4. 사용자 상호작용

각 row는 `입금` 버튼과 필요한 경우 `저축` 버튼을 표시하고, 선택한 단계와 함께 `ToggleSavingsItemIntent`를 실행한다. 이 intent는 `LiveActivityIntent`를 채택하며 다음 작업을 수행한다.

1. repository에서 해당 item/cycle/step 상태 변경
2. 완료 처리라면 해당 월급 주기와 단계의 알림 제거
3. 전체 알림 재예약
4. Live Activity refresh
5. 일반 widget timeline reload

잠긴 기기에서는 시스템이 필요한 authentication을 요구할 수 있다.

## 5. 즉시 시작

`LiveActivityManager.startNow` 동작:

1. `ActivityAuthorizationInfo.areActivitiesEnabled` 확인
2. 미완료 항목 존재 확인
3. 이미 active activity가 있으면 새로 만들지 않고 content update
4. iOS 26 이상이면 pending relay activity를 먼저 종료하여 active slot 확보
5. 새 standard Live Activity request

명시적 시작 실패는 다음 사용자 메시지로 변환한다.

- Live Activity 비활성화
- 미완료 항목 없음
- ActivityKit이 전달하는 기타 localized error

설정 화면의 `지금 Live 체크리스트 띄우기`가 이 경로를 사용한다.

## 6. 자동 시작 조건

iOS 26 이상에서 `refresh`는 현재 월급 주기의 미완료 항목 중 하나라도 주의 시점에 도달했는지 확인한다.

```text
주의 시점 = 출금 예정 시각 - leadDays
```

주의 시점이 현재보다 과거이고 active activity가 없으면 즉시 시작을 시도한다. 아직 미래라면 해당 시점에 시작하도록 scheduled Live Activity를 만든다.

iOS 17~25에는 scheduled start API가 없으므로 자동 미래 시작을 하지 않는다. 로컬 notification을 받고 앱에서 수동 시작할 수 있다.

## 7. 릴레이 유지 알고리즘

### 배경

하나의 Live Activity는 시스템 시간 제한을 받는다. 영구 실행을 요청할 수 없으므로 후속 activity를 미리 예약해 표시 공백을 줄인다.

### 간격

```text
relay interval = 7시간 55분
```

8시간 제한 직전 후속 activity가 시작되도록 5분 overlap을 둔다.

### 개수 관리

실제 진단에서 target별 active + pending 총 5개 한도가 관찰되었다. 초기 구현은 pending 5개로 모든 slot을 점유해 수동 시작이 `targetMaximumExceeded`로 실패했다.

현재 정책:

| 상태 | active | pending 최대 | 총계 |
|---|---:|---:|---:|
| 표시 중 | 1 | 4 | 5 |
| 아직 시작 전 | 0 | 5 | 5 |

수동 시작 전에는 pending을 먼저 종료해 active용 slot을 확보한다. active 1개와 후속 4개를 합치면 이론상 약 39시간 40분의 activity window를 구성한다.

시스템 한도는 OS와 기기 상태에 따라 달라질 수 있으므로 각 scheduled request는 실패 가능성을 허용한다.

## 8. Refresh 동작

`LiveActivityManager.refresh` 순서:

1. 현재 월급 주기 content state 생성
2. 모든 active activity 조회
3. 미완료가 없으면 active를 immediate dismissal로 종료
4. 미완료가 있으면 active content update
5. iOS 26 미만 또는 Live Activity 비활성화면 종료
6. 기존 pending activity 종료
7. 필요하면 현재 activity 즉시 시작
8. relay event 계산
9. active slot을 고려한 개수만 scheduled request 생성

자동 refresh 실패는 알림과 앱 기능을 막지 않도록 삼킨다. 수동 시작은 UI에 오류를 보여 준다.

## 9. 완료 시 종료

현재 월급 주기의 모든 항목이 완료되면:

- active activity를 `.immediate` dismissal policy로 종료
- iOS 26 이상 pending activity도 모두 종료
- 배지는 0으로 변경
- 완료된 item의 notification 제거

## 10. Dynamic Island 우선순위

DonCheck가 다른 앱의 Live Activity보다 항상 우선하도록 만드는 API는 없다.

- Live Activity 하나만 있으면 compact presentation 사용
- 여러 개면 시스템이 minimal presentation을 조합할 수 있음
- 내비게이션, 통화, 타이머 등 다른 활동과의 우선순위는 시스템 결정
- 사용자가 activity를 직접 제거할 수 있음

`relevanceScore`를 사용하더라도 절대 우선권을 보장하지 않는다. 현재 content는 기본 relevance score를 사용한다.

## 11. 진단 로그

시뮬레이터 예시:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun simctl spawn booted log show \
  --last 5m \
  --style compact \
  --predicate '(process == "liveactivitiesd" OR process == "DonCheck" OR process == "DonCheckWidget")'
```

중요 로그:

```text
Starting activity ... state: active
Activity started
Created activity
Cannot create new activity as maximum count for target has been reached
```

`Connection invalidated` 한 줄만으로 실패를 단정하면 안 된다. 앱 재설치, extension 재시작, 프로세스 종료 시에도 나타날 수 있다. activity가 실제로 `active`가 되었는지와 maximum/authorization/visibility 오류를 함께 확인한다.

## 12. 알려진 제한

- 무기한 고정 불가
- 사용자가 제거 가능
- 시스템이 조기 종료할 가능성
- Dynamic Island 우선권 없음
- 앱을 장기간 열지 않으면 로컬 relay horizon 이후 연장 불가
- payload가 큰 체크리스트에 대한 truncation 없음
- APNs push-to-start/update 미구현

## 13. 향후 서버 확장

무기한에 가까운 갱신이 필요하면 APNs 기반 ActivityKit push가 필요하다.

필요 구성:

1. 앱에서 push-to-start/activity push token 수집
2. 안전한 backend로 token 전송
3. APNs signing key 관리
4. 만료 전 update/start/end push 전송
5. token rotation과 앱 삭제 처리

개인용 local-first 목표와 운영 복잡도를 고려해 현재 범위에서는 제외했다.

# 앱 UI와 상태 관리

## 1. 화면 구성

앱은 하나의 `NavigationStack`과 세 개의 주요 화면으로 구성된다.

| 화면 | 구현 | 역할 |
|---|---|---|
| 메인 | `ContentView` | 월 요약, 항목 목록, 완료 토글 |
| 항목 편집 | `ItemEditorView` | 항목 생성과 수정 |
| 설정 | `SettingsView` | 알림 권한, 재예약, Live Activity 시작 |

전역 UI state는 `ChecklistStore`를 `@StateObject`로 생성해 environment object로 전달한다.

## 2. 앱 진입점

`DonCheckApp`은 두 bridge를 설정한다.

```swift
@UIApplicationDelegateAdaptor(AppDelegate.self)
@StateObject private var store = ChecklistStore()
```

SwiftUI lifecycle을 사용하지만 notification delegate callback이 필요하므로 `UIApplicationDelegateAdaptor`로 `AppDelegate`를 연결한다.

`ContentView`는 `.checklistDidChange` notification을 구독한다. notification action처럼 SwiftUI view 바깥에서 저장소가 변경되면 store를 reload한다.

## 3. ChecklistStore

`ChecklistStore`는 `@MainActor ObservableObject`다.

Published state:

- `data`: 현재 메모리 snapshot
- `notificationAuthorized`: 알림 권한 UI 상태
- `liveActivityMessage`: Live Activity 시작 결과 alert

계산 property:

- `cycleKey`: 현재 월 키
- `completedCount`: 현재 월 완료 개수
- `remainingAmount`: 현재 월 미완료 금액

### 초기화

1. repository load
2. 알림 권한 상태 조회
3. local notification 재예약
4. Live Activity refresh
5. Debug argument가 있으면 Live Activity 즉시 시작

초기 비동기 작업은 `Task`에서 실행한다. 앱 launch 시 알림과 pending Live Activity가 최신 저장 데이터에 맞춰 정리되는 효과가 있다.

### Persist

항목 저장, 삭제, 토글은 모두 private `persist()`로 수렴한다.

```text
prune history
→ repository.save
→ widget reload request
→ notification reschedule
→ Live Activity refresh
```

## 4. 메인 화면

### Navigation

- leading toolbar: 설정 gear
- trailing toolbar: 항목 추가 plus
- title: 현재 연도와 월 + `저축`

### Summary card

표시 값:

- 남은 입금액
- 완료 수 / 전체 수
- progress bar

전체 항목이 0개면 progress를 0으로 처리해 division-by-zero를 피한다.

통화 표시는 `KRW` currency format과 fraction digit 0을 사용한다.

### 목록

각 row는 다음을 표시한다.

- 완료 circle/checkmark
- 항목 이름
- 매월 출금일과 알림 시각
- 금액

완료된 항목은 이름에 strikethrough를 적용하고 secondary color로 표시한다.

상호작용:

- 체크 icon 탭: 현재 월 완료 toggle
- row 탭: 편집 sheet
- swipe delete: 항목과 관련 history 삭제

체크 button과 row tap gesture가 같은 row에 있으므로 interaction 변경 시 gesture 충돌을 회귀 테스트해야 한다.

### 빈 상태

항목이 없으면 `ContentUnavailableView`로 첫 항목 추가를 안내한다.

## 5. 항목 편집 화면

`ItemEditorView`는 optional item을 받아 생성/수정 모드를 구분한다.

### 생성 모드

기본값:

```text
name: 빈 문자열
amount: 0
debitDay: 1
reminderHour: 8
reminderMinute: 0
leadDays: 1
followUpCount: 3
```

### 수정 모드

전달받은 item을 local `@State draft`로 복사한다. 취소하면 원본 store를 변경하지 않는다.

### Form sections

`저축 정보`:

- 이름 TextField
- 금액 number TextField와 number pad

`매월 일정`:

- 출금일 Stepper 1...31
- 알림 시간 DatePicker
- 사전 알림 Stepper 0...14

`완료하지 않았을 때`:

- 재알림 Stepper 0...7
- 체크 시 현재 월 남은 알림 취소 안내

### 저장 검증

저장 버튼 비활성 조건:

```swift
trimmedName.isEmpty || amount <= 0
```

현재 금액 상한, 중복 이름, 최대 항목 수 검증은 없다.

### 시간 Binding

모델은 hour/minute integer를 저장하지만 DatePicker는 `Date` binding을 요구한다. computed `reminderTime` binding이 current calendar의 임시 Date와 hour/minute 사이를 변환한다.

## 6. 설정 화면

### 잠금 화면 체크리스트 section

`지금 Live 체크리스트 띄우기` 버튼은 미완료 항목이 있을 때만 활성화된다.

성공 또는 실패 결과는 `liveActivityMessage`를 사용한 alert로 표시한다.

### 알림 section

- 권한 상태 표시
- 권한 미허용: `알림 허용하기`
- 권한 허용: `알림 일정 다시 만들기`
- iOS notification settings deep link

### 작동 방식 section

월별 완료 기록과 iOS의 영구 notification 고정 제한을 설명한다.

## 7. Scene lifecycle

`ContentView`는 `scenePhase`가 `.active`가 될 때 다음을 수행한다.

1. repository에서 최신 data reload
2. notification authorization status refresh

앱이 background에 있는 동안 widget intent나 notification action이 상태를 변경할 수 있으므로 foreground reload가 필요하다.

현재 foreground 복귀만으로 notification/Live Activity 전체 재예약을 다시 호출하지는 않는다. 저장 변경 경로와 앱 초기화가 해당 작업을 담당한다.

## 8. 접근성과 현지화

현재 UI는 system component와 SF Symbols를 사용해 Dynamic Type과 기본 VoiceOver semantics의 도움을 받는다. 하지만 다음 작업은 미완료다.

- icon-only toolbar button의 명시적 accessibility label 검토
- custom summary card의 읽기 순서
- Live Activity row의 완료 상태 accessibility value
- 모든 사용자 문자열의 localization catalog 이전
- KRW 외 locale/통화 지원

앱의 development region은 한국어이며 현재 문자열은 소스에 직접 작성되어 있다.

## 9. UI 확장 시 주의점

- store snapshot과 repository canonical state를 혼동하지 않는다.
- widget/notification 경로 변경을 foreground reload가 반영해야 한다.
- 편집 draft는 저장 전 원본을 바꾸지 않아야 한다.
- 항목 정렬을 추가하면 앱과 widget 표시 순서를 함께 정의한다.
- 금액 숨김 privacy option을 추가하면 앱, 위젯, Live Activity 모두 동일하게 적용한다.
- 화면에서만 완료 처리 로직을 구현하지 말고 repository/system refresh 공통 경로를 사용한다.

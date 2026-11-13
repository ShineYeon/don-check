# 로컬 알림

## 1. 개요

DonCheck의 일반 알림은 `UserNotifications` framework로 기기 내부에서 예약한다. 서버나 APNs가 없어도 앱이 종료된 상태에서 시스템이 지정 시각에 알림을 전달한다.

구현 파일:

- `Shared/NotificationScheduler.swift`
- `DonCheck/DonCheckApp.swift`
- `DonCheck/ChecklistStore.swift`

## 2. 권한

`NotificationScheduler.requestAuthorization()`는 다음 권한을 요청한다.

```swift
[.alert, .sound, .badge]
```

앱 설정 화면의 `알림 허용하기` 버튼에서 호출한다. 권한 요청 전에 notification category도 등록한다.

`ChecklistStore.refreshNotificationStatus()`는 authorization status가 `.authorized` 또는 `.provisional`일 때 앱 내부 상태를 허용으로 표시한다.

### Time Sensitive

출금일과 재알림 content는 `.timeSensitive` interruption level을 사용한다. 별도의 authorization option이 아니라 notification content 속성이다. 사용자는 iOS 설정에서 해당 앱의 time-sensitive notification을 끌 수 있으므로 전달 우선순위를 보장할 수 없다.

## 3. 식별자

### Category와 Action

```text
Category ID: DONCHECK_ITEM
Action ID:   DONCHECK_COMPLETE
Action title: 입금 완료
```

category는 앱 launch 시 `AppDelegate.application(_:didFinishLaunchingWithOptions:)`에서 등록하고, 권한 요청 시에도 다시 등록한다.

### Request ID

알림 request identifier 형식:

```text
doncheck.<itemUUID>.<cycleKey>.<kind>
```

예:

```text
doncheck.6C96...A21.2026-11.early
doncheck.6C96...A21.2026-11.due
doncheck.6C96...A21.2026-11.followup-1
```

`AppConfig.notificationPrefix`는 `doncheck.`다. 전체 재예약 시 이 prefix를 가진 request만 제거하므로 다른 기능의 알림을 실수로 삭제하지 않는다.

## 4. 알림 종류

### 4.1 사전 알림

- 조건: `leadDays > 0`
- 시각: 출금일 기준 `leadDays`일 전, 항목의 reminder hour/minute
- 문구: `출금 전에 입금할 때예요`
- interruption level: `.active`

### 4.2 출금일 알림

- 조건: 현재 시각보다 미래인 출금일 시각
- 문구: `오늘 출금 예정이에요`
- interruption level: `.timeSensitive`

### 4.3 재알림

- 조건: 현재 월 항목이 미완료이며 `followUpCount > 0`
- 시각: 출금일 이후 1일부터 `followUpCount`일까지 같은 시각
- 문구: `아직 완료하지 않은 저축 항목이에요`
- interruption level: `.timeSensitive`

다음 달에 대해서는 사전 알림과 출금일 알림만 미리 만든다. 다음 달 재알림은 그 달이 현재 월이 되어 다시 schedule될 때 생성한다.

## 5. 전체 재예약 알고리즘

`rescheduleAll(_:now:)` 순서:

1. 시스템에서 pending notification request를 조회한다.
2. identifier가 `doncheck.`로 시작하는 request를 제거한다.
3. 현재 월의 미완료 항목에 대해 early/due/follow-up 후보를 생성한다.
4. 다음 월의 미완료 항목에 대해 early/due 후보를 생성한다.
5. 이미 지난 후보를 제거한다.
6. 날짜 오름차순으로 정렬한다.
7. 가장 가까운 60개를 시스템에 등록한다.
8. 현재 월 미완료 개수를 app badge로 설정한다.

재예약은 incremental update보다 비용이 크지만, 삭제·수정·완료 취소를 동일한 코드 경로로 안전하게 처리한다.

## 6. 완료 시 취소

`cancel(itemID:cycleKey:)`는 pending과 delivered notification을 각각 조회한다. 대상 item/month identifier prefix를 가진 알림만 제거한다.

delivered notification은 pending 목록에 존재하지 않기 때문에 두 목록을 모두 조회해야 한다. 이 구분을 제거하면 체크 후에도 Notification Center에 이미 전달된 알림이 남을 수 있다.

이후 `rescheduleAll`을 호출해 다른 항목과 다음 월 알림을 유지한다.

## 7. 알림 액션 처리

notification content의 `userInfo`에는 다음 값이 들어간다.

```swift
[
    "itemID": item.id.uuidString,
    "cycleKey": "2026-11"
]
```

사용자가 `입금 완료`를 누르면 `AppDelegate`가 payload를 검증한 후 다음 순서로 처리한다.

1. repository에 해당 item/month 완료 기록 저장
2. 해당 알림 pending/delivered 제거
3. 전체 알림 재예약
4. Live Activity refresh
5. 실행 중 앱에 `.checklistDidChange` 전파

payload가 없거나 UUID parsing에 실패하면 아무 상태도 바꾸지 않는다.

## 8. 앱이 foreground일 때

기본적으로 앱이 foreground이면 notification UI가 숨겨질 수 있다. `willPresent` delegate는 다음 presentation option을 반환한다.

```swift
[.banner, .sound, .badge, .list]
```

따라서 앱을 보고 있는 중에도 예약 알림이 도착하면 banner와 sound가 표시될 수 있다.

## 9. 제한과 실패 모드

### Pending request 제한

iOS는 앱별 pending local notification 수를 제한한다. 구현은 안전 여유를 두고 60개까지만 등록한다. 항목 수와 재알림 수가 많으면 먼 미래 후보가 잘릴 수 있다.

예를 들어 항목 10개, 항목별 현재 월 early/due/follow-up 7개, 다음 월 early/due를 모두 만들면 100개에 가까워진다. 이 경우 가까운 알림만 남는다.

### 권한 거부

권한이 거부되어도 item CRUD와 위젯은 동작한다. 현재 scheduler의 `add` 오류는 `try?`로 무시하므로 세부 실패는 UI에 노출되지 않는다.

### 집중 모드와 알림 요약

Time Sensitive가 허용된 경우 일부 시스템 제어를 우회할 수 있지만 사용자가 끌 수 있다. Critical Alert entitlement는 사용하지 않는다.

### 기기 시각/시간대 변경

request는 year/month/day/hour/minute DateComponents로 등록된다. 앱이 다시 실행되거나 데이터가 변경되어 재예약되면 현재 calendar/timezone 기준으로 다시 계산된다.

## 10. 검증 체크리스트

- 알림 최초 권한 요청
- 권한 거부 후 설정 앱 이동
- 사전 알림 0일/1일/14일
- 재알림 0일/7일
- 출금일이 지난 상태에서 앱 시작
- 완료 직후 pending request 제거
- 완료 취소 후 미래 알림 복구
- notification action으로 완료
- foreground delivery
- 60개 초과 후보에서 최근 알림 우선 유지

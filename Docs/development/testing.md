# 테스트 전략과 회귀 체크리스트

## 1. 현재 상태

현재 프로젝트에는 XCTest unit test target이나 XCUITest target이 없다. 검증은 다음 세 층으로 수행한다.

1. Swift typecheck/compile
2. app + extension 전체 Xcode build
3. Simulator 또는 실제 기기의 수동 기능 검증

기능이 늘어나면 날짜 계산, repository, scheduler candidate 생성부터 unit test로 분리하는 것이 우선순위다.

## 2. 빌드 검증

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project DonCheck.xcodeproj \
  -scheme DonCheck \
  -sdk iphonesimulator \
  -configuration Debug \
  -derivedDataPath /tmp/DonCheckDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

`BUILD SUCCEEDED`뿐 아니라 warning과 다음 단계를 확인한다.

- `ExtractAppIntentsMetadata`
- `ValidateEmbeddedBinary`
- `ProcessInfoPlistFile`
- `Copy ... DonCheckWidget.appex`

## 3. 정적 파일 검증

```bash
plutil -lint \
  DonCheck/DonCheck.entitlements \
  DonCheckWidget/DonCheckWidget.entitlements \
  DonCheckWidget/Info.plist \
  DonCheck.xcodeproj/project.pbxproj

git diff --check
```

## 4. 체크리스트 기능

### 생성

- 정상 이름/금액 저장
- 빈 이름 저장 버튼 비활성화
- 금액 0 이하 저장 버튼 비활성화
- 출금일 1과 31 경계
- 사전 알림 0과 14 경계
- 재알림 0과 7 경계

### 수정

- 이름과 금액 반영
- 출금일 변경 후 알림 재예약
- 완료된 항목 수정 시 완료 상태 유지

### 삭제

- 목록에서 제거
- widget refresh
- 관련 completion history 제거
- 관련 notification 제거 여부

### 완료

- 비자동이체 항목의 입금 완료/취소
- 자동이체 항목의 입금 완료/취소
- 자동이체 항목의 저축 완료/취소
- 저축 완료를 먼저 체크해도 입금 전에는 최종 미완료
- 남은 금액 업데이트
- 입금/저축/최종 완료 개수 업데이트
- badge 업데이트
- widget과 Live Activity 업데이트

## 5. 날짜와 월급 주기

| 케이스 | 기대 결과 |
|---|---|
| 31일 설정, 4월 | 4월 30일 |
| 31일 설정, 평년 2월 | 2월 28일 |
| 31일 설정, 윤년 2월 | 2월 29일 |
| 12월 완료 후 1월 | 새 cycle에서 미완료 |
| 월급일 25일, 24일 23:59 | 이전 달 25일 시작 cycle |
| 월급일 25일, 25일 00:00 | 현재 달 25일 시작 cycle |
| 월급일 31일, 평년 2월 28일 | 2월 28일 시작 cycle |
| 월급일 31일, 윤년 2월 29일 | 2월 29일 시작 cycle |
| 월급일이 토요일 | 직전 금요일 00:00 시작 cycle |
| 월급일이 일요일 | 직전 금요일 00:00 시작 cycle |
| 월급일 직전 금요일도 공휴일 | 연속 휴일 전 목요일 00:00 시작 cycle |
| 다음 달 월급일 보정일이 현재 달 | 보정된 이전 영업일부터 다음 cycle |
| 월급일 변경 | 현재 cycle 재계산 및 system UI 동기화 |
| 자동이체일 31일, 짧은 달 | 해당 달 말일 이체일 |
| 자동이체일이 일요일, 다음 월요일도 공휴일 | 화요일의 기존 알림 시각으로 이체일 이동 |
| 공휴일 캐시가 없는 기존 v4 payload | decode 성공 및 주말만 보정 |
| 공휴일 재동기화로 cycle 경계 변경 | completion이 새 cycle key로 매핑되어 체크 유지 |
| 월말 사전 알림 | 이전 달 날짜로 예약 |
| 다른 시간대로 이동 | 다음 재예약에서 현지 calendar 적용 |

자동화 시 `Calendar`와 `now`를 주입하고 고정 timezone을 사용해야 재현 가능한 테스트가 된다.

EventKit 통합은 실제 기기에서 대한민국 공휴일 캘린더 활성화, 최초 권한 허용, 권한 거부, 캘린더 미발견을 각각 확인한다. 단위 테스트에서는 EventKit에 의존하지 않고 고정된 `Set<String>`을 `holidays` 인자로 주입한다.

## 6. 알림

- 최초 권한 요청 alert 표시
- 허용/거부 상태 UI
- 설정 앱 링크
- early, due, follow-up request 생성
- 이미 지난 request 미생성
- 완료 시 pending/delivered 제거
- notification action으로 완료
- 입금 완료 action이 입금 단계만 변경
- 저축 완료 action이 저축 단계만 변경
- foreground banner 표시
- time-sensitive 설정 비활성화 상태
- 후보 60개 초과 시 가까운 순서 유지

pending request는 디버거에서 다음 API로 확인할 수 있다.

```swift
let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
```

## 7. 위젯

- App Group 데이터 표시
- small/medium/large family
- accessory circular/rectangular
- 빈 목록 UI
- 표시 개수 truncation
- 위젯 버튼 완료 처리
- 위젯의 입금/저축 단계별 버튼
- 앱으로 복귀했을 때 최신 상태 reload
- 월급일 00:00 이후 cycle 변경
- dark mode와 tinted appearance

## 8. Live Activity

### 시작

- 미완료 항목이 있을 때 수동 시작
- 미완료 항목이 없을 때 사용자 오류
- Live Activity 비활성화 상태 오류
- 이미 active일 때 중복 생성 없이 update
- 실제 월급일 하루 전 입금 window 시작
- 영업일 보정된 실제 자동이체일 하루 전 저축 window 시작
- 입금/저축 완료 후 해당 window 종료 또는 다음 window 전환
- 월급일 전날 next cycle key로 입금 체크 유지

### UI

- 잠금 화면 최대 4개 row
- 4개 초과 요약
- Dynamic Island compact/minimal/expanded
- compactLeading DonCheck 원화+체크 mark
- compactTrailing 전체/입금/저축 symbol과 숫자
- compact 폭 부족 시 `N·M·O` fallback
- 자동이체 확인 항목 0개일 때 저축 metric 숨김
- 두 자릿수 집계와 VoiceOver 전체 문구
- 금액과 미완료 개수
- row 체크 interaction
- row의 입금/저축 단계별 intent

### 릴레이

- active 1개 + pending 최대 4개
- 수동 시작 전 pending 정리
- `targetMaximumExceeded` 미발생
- 모든 항목 완료 시 active/pending 종료
- 이전 build activity의 optional `scheduledStart` decode

### Debug argument

Xcode scheme launch argument:

```text
-startLiveChecklist
```

앱 시작 시 Live Activity 경로를 자동 실행한다. Debug configuration 전용이다.

## 9. ActivityKit 로그 검증

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun simctl spawn booted log show \
  --last 5m \
  --style compact \
  --predicate '(process == "liveactivitiesd" OR process == "DonCheck" OR process == "DonCheckWidget")'
```

성공 신호:

```text
Starting activity ... state: active
Activity started
```

실패 신호:

```text
Cannot create new activity as maximum count for target has been reached
ActivityAuthorizationError
visibility
unentitled
```

`Connection invalidated`는 프로세스 종료에도 나타날 수 있으므로 단독으로 실패 판정에 사용하지 않는다.

## 10. 실제 기기 회귀 테스트

Simulator에서 완전히 검증하기 어려운 항목:

- 실제 잠금/Face ID interaction
- Dynamic Island 하드웨어 presentation
- 집중 모드와 Time Sensitive
- 장시간 8시간 제한 및 relay handoff
- 앱이 시스템에 의해 종료된 뒤 scheduled activity 시작
- 저전력 모드
- 다른 앱 Live Activity와 동시 실행
- 실제 notification delivery timing

릴리스 전 최소 한 대의 Dynamic Island 지원 iPhone에서 위 항목을 검증해야 한다.

## 11. 자동화 우선순위

1. `CycleDate` unit test
2. `ChecklistData` aggregate test
3. repository encode/decode 및 history prune test
4. notification candidate 생성 로직을 pure function으로 분리해 test
5. relay event 계산을 pure function으로 분리해 test
6. App Group integration test
7. 주요 SwiftUI flow XCUITest

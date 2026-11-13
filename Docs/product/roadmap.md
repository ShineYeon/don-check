# 제품 로드맵

이 문서는 합의된 후속 기능을 구현 가능한 단위로 정리하고 진행 상태를 추적한다. 구현이 완료되면 관련 요구사항, 데이터 스키마, 기능 문서와 테스트 문서를 함께 갱신한다.

## 우선순위

| 순서 | ID | 기능 | 상태 |
|---:|---|---|---|
| 1 | NEXT-001 | 월급일 기준 체크 주기 | 구현 완료 |
| 2 | NEXT-002 | 항목별 2단계 완료 체크 | 구현 완료 |
| 3 | NEXT-003 | Dynamic Island 단계별 요약 디자인 | 구현 완료 |
| 4 | NEXT-004 | 일정 기반 Live Activity attention window | 구현 완료 |

NEXT-002의 완료 상태는 NEXT-001에서 정의한 월급 주기에 귀속된다. NEXT-003은 NEXT-002에서 추가한 단계별 집계값을 Dynamic Island compact UI에 노출한다.

## NEXT-001: 월급일 기준 체크 주기

### 목적

사용자가 매월 월급일을 설정하면 해당 날짜부터 새로운 저축 준비 주기를 시작한다. 새 주기가 시작될 때 이전 주기에 체크했던 항목은 화면상 빈 체크박스로 나타나야 한다.

구현은 달력의 1일이 아니라 **설정한 월급일**을 경계로 주기를 계산한다. 기존 `YYYY-MM` 키는 v2 migration에서 기본 월급일인 1일의 `YYYY-MM-01`로 변환한다.

예를 들어 월급일이 매월 25일이면 다음과 같이 동작한다.

- 2026년 11월 24일까지: 2026년 10월 25일에 시작한 주기
- 2026년 11월 25일부터: 2026년 11월 25일에 시작한 새 주기
- 새 주기에서는 모든 활성 항목의 체크 상태가 미완료로 보임
- 이전 주기의 완료 기록은 삭제하지 않고 history로 보존

### 기능 요구사항

| ID | 요구사항 |
|---|---|
| NEXT-001-FR-01 | 설정 화면에서 매월 월급일을 선택할 수 있어야 한다. |
| NEXT-001-FR-02 | 월급일은 1~31 범위로 저장해야 한다. |
| NEXT-001-FR-03 | 해당 월에 설정한 날짜가 없으면 그 달의 마지막 날을 월급일로 사용해야 한다. 예: 31일 설정 시 2월 28일 또는 29일. |
| NEXT-001-FR-04 | 현재 시각이 월급일 경계를 지나면 새로운 `cycleKey`를 계산해야 한다. |
| NEXT-001-FR-05 | 새 주기에서는 이전 주기의 완료 기록을 재사용하지 않아 모든 체크박스가 미완료로 보여야 한다. |
| NEXT-001-FR-06 | 이전 완료 기록을 물리적으로 삭제하지 않아야 한다. |
| NEXT-001-FR-07 | 앱, 위젯, 알림 액션과 Live Activity가 동일한 주기 계산기를 사용해야 한다. |
| NEXT-001-FR-08 | 월급일을 변경하면 현재 주기를 즉시 다시 계산하고 위젯, 알림과 Live Activity를 동기화해야 한다. |

### 구현 결과

- 전역 `ChecklistData`에 `payday: Int`를 추가했다.
- 공유 `CycleDate`가 앱, 위젯, 알림과 Live Activity의 주기를 계산한다.
- 새 `cycleKey`는 주기 시작일을 명확히 표현하는 값(예: `2026-11-25`)을 사용한다.
- 월급일이 되어도 기존 completion을 일괄 삭제하지 않는다. 새 주기 키로 조회 결과가 자연스럽게 비어 있도록 한다.
- 날짜 경계는 사용자의 현재 Calendar와 time zone을 따른다. 월급일 당일 00:00부터 새 주기로 간주하는 것을 기본안으로 한다.
- 앱이 종료된 상태에서도 다음 실행, widget timeline 갱신, notification action 처리 시 현재 주기를 다시 계산한다. 정확히 00:00에 백그라운드 코드를 실행하는 방식에 의존하지 않는다.
- NEXT-001에서 App Group 저장 키를 v2로 올렸고, 현재 v4 migration도 v1~v3의 월급일과 완료 기록을 보존한다.

### 월급일 변경 규칙

월급일 변경은 이미 완료한 항목이 갑자기 미완료로 보이거나 그 반대가 될 수 있는 민감한 작업이다. 구현 시 다음 정책을 적용하는 것을 기본안으로 한다.

1. 저장 전에 “현재 체크 주기가 변경될 수 있음”을 안내한다.
2. 사용자가 확정하면 새 월급일로 현재 주기를 즉시 재계산한다.
3. 기존 기록은 이동하거나 삭제하지 않는다.
4. 새 주기의 알림을 전체 재예약하고 기존 Live Activity를 교체한다.

### 수용 조건

- 월급일 전날 체크한 항목이 당일 00:00 이후 미완료로 표시된다.
- 앱을 월급일에 열지 않아도 이후 처음 앱이나 위젯을 사용할 때 새 상태가 표시된다.
- 29일, 30일, 31일 설정이 짧은 달과 윤년에서 마지막 날로 보정된다.
- 12월에서 다음 해 1월로 넘어가도 주기 키가 충돌하지 않는다.
- 월급일을 변경한 뒤 앱, 위젯, 알림과 Live Activity의 완료 개수가 일치한다.
- 과거 completion history는 보존된다.

## NEXT-002: 항목별 2단계 완료 체크

### 목적

한 저축 항목의 준비 과정을 필요에 따라 두 단계로 관리한다.

1. **입금 완료**: 자동이체가 출금될 연계 통장에 필요한 돈을 넣었음
2. **저축 완료**: 연계 통장에서 실제 저축 통장 또는 금융 상품으로 자동이체가 완료됐음을 확인함

자동이체를 사용하지 않는 항목은 두 번째 단계가 필요 없으므로 `입금 완료` 체크 하나만 표시한다.

### 기능 요구사항

| ID | 요구사항 |
|---|---|
| NEXT-002-FR-01 | 항목 생성/수정 화면에서 자동이체 사용 여부를 설정할 수 있어야 한다. |
| NEXT-002-FR-02 | 자동이체 항목에는 `입금 완료`와 `저축 완료` 체크를 각각 표시해야 한다. |
| NEXT-002-FR-03 | 비자동이체 항목에는 `입금 완료` 체크만 표시해야 한다. |
| NEXT-002-FR-04 | 두 체크 상태는 항목과 주기별로 독립 저장해야 한다. |
| NEXT-002-FR-05 | 자동이체 항목은 두 단계가 모두 체크되어야 최종 완료로 계산해야 한다. |
| NEXT-002-FR-06 | 비자동이체 항목은 입금 단계가 체크되면 최종 완료로 계산해야 한다. |
| NEXT-002-FR-07 | 월급일로 새 주기가 시작되면 필요한 모든 단계가 미완료로 보여야 한다. |
| NEXT-002-FR-08 | 알림, 위젯과 Live Activity에서도 현재 필요한 단계를 구분해 완료할 수 있어야 한다. |

### 상태 모델

항목에는 두 번째 단계의 필요 여부를 나타내는 값을 추가한다.

```swift
struct SavingsItem {
    // 기존 필드
    var requiresAutomaticTransferConfirmation: Bool
}

enum CompletionStep: String, Codable {
    case deposit
    case automaticTransfer
}

struct CompletionRecord {
    var itemID: UUID
    var cycleKey: String
    var step: CompletionStep
    var completedAt: Date
}
```

completion의 논리적 고유 키는 `(itemID, cycleKey, step)`이 된다. 최종 완료 여부는 저장하지 않고 필요한 단계의 completion을 조회해 계산한다.

| 항목 유형 | 입금 완료 | 저축 완료 | 최종 상태 |
|---|---:|---:|---|
| 비자동이체 | 미완료 | 해당 없음 | 미완료 |
| 비자동이체 | 완료 | 해당 없음 | 완료 |
| 자동이체 | 완료 | 미완료 | 진행 중 |
| 자동이체 | 완료 | 완료 | 완료 |

자동이체 항목에서 `저축 완료`를 먼저 체크하는 동작은 데이터상 허용하되, UI에서는 두 단계의 이름을 명확히 보여 준다.

### 알림 동작

- 출금 전 알림의 기본 액션은 `입금 완료`로 유지한다.
- 자동이체 항목은 입금 완료 후에도 최종 완료로 처리하지 않는다.
- 출금일 당일 같은 알림 시각에 `저축 완료` 확인 알림을 별도로 제공한다.
- 각 단계가 체크되면 해당 단계에 관한 pending/delivered notification만 제거한다.
- 필요한 단계가 모두 끝났을 때만 항목의 재알림과 Live Activity row를 최종 완료 처리한다.

현재 저축 완료 알림은 기존 출금일/알림 시각을 공유한다. 별도 확인 시각은 후속 개선 범위다.

### UI 영향

- 앱 row: 자동이체 항목은 두 개의 명명된 체크 컨트롤을 표시한다.
- 편집 화면: `자동이체 후 저축 완료 확인` toggle을 추가한다.
- 위젯: 제한된 공간에서 두 단계가 혼동되지 않도록 축약 label 또는 단계별 symbol을 사용한다.
- Live Activity: 항목별 현재 단계와 최종 완료 여부를 구분한다.
- 진행률: 항목 기준 진행률과 단계 기준 진행률 중 하나를 제품 전체에서 일관되게 사용해야 한다. 기본안은 “최종 완료 항목 수 / 전체 항목 수”다.

### 기존 데이터 migration

NEXT-002에서 App Group 저장 키를 v3로 올렸다. 현재 v4 migration에서도 기존 항목은 `requiresAutomaticTransferConfirmation = false`, 기존 completion은 `step = .deposit`으로 해석한다.

자동이체 확인을 켠 기존 항목은 현재 주기의 입금 완료 상태는 유지하되 저축 완료 상태가 새로 미완료가 된다.

### 수용 조건

- 자동이체 toggle이 꺼진 항목에는 체크가 정확히 하나만 보인다.
- 자동이체 toggle이 켜진 항목에는 두 체크가 독립적으로 동작한다.
- 자동이체 항목은 입금만 체크했을 때 진행 중이며 전체 완료 수에 포함되지 않는다.
- 두 단계를 모두 체크하면 관련 알림이 정리되고 최종 완료로 표시된다.
- 새 월급 주기에는 두 단계가 모두 미완료가 된다.
- 앱에서 체크한 상태가 위젯과 Live Activity에 반영되고, 반대 방향도 동일하게 동작한다.
- 기존 저장 데이터가 migration된 뒤 기존 완료 표시를 잃지 않는다.

## NEXT-003: Dynamic Island 단계별 요약 디자인

### 목적

Dynamic Island가 compact 상태일 때 앱 정체성과 현재 저축 진행 상황을 카메라 양쪽에서 즉시 이해할 수 있게 한다.

### Compact layout

- 전면 카메라 왼쪽(`compactLeading`): DonCheck를 나타내는 작은 아이콘
- 전면 카메라 오른쪽(`compactTrailing`): 전체 항목 수, 입금 완료 수, 저축 완료 수를 압축한 요약
- 확장 상태(`expanded`): 같은 집계의 전체 문구와 항목별 체크리스트
- minimal 상태: 가장 중요한 미완료 수 또는 DonCheck 아이콘 하나로 축약

오른쪽 정보의 의미는 다음과 같다.

```text
전체 N개 중 M개 입금 완료 · O개 저축 완료
```

- `N`: 전체 저축 항목 수
- `M`: `deposit` 단계가 완료된 항목 수
- `O`: 자동이체 확인이 필요한 항목 중 `automaticTransfer` 단계가 완료된 항목 수

compact 영역은 폭이 매우 좁으므로 `ViewThatFits`를 사용한다. 공간이 충분하면 전체·입금·저축을 각각 SF Symbol과 숫자로 표시하고, 부족하면 `N·M·O` 순서의 숫자열로 자동 축약한다. 전체 문장은 expanded 영역과 접근성 label에서 제공한다.

### 아이콘 방향

외부 이미지 asset 없이 SF Symbols를 조합한 앱 전용 mark를 구현했다.

- mint 색상의 `wonsign.circle.fill` 위에 작은 `checkmark.circle.fill`을 겹친다.
- expanded leading에서는 mark 옆에 `DonCheck` 이름을 함께 표시한다.
- compact/minimal에서는 mark만 표시한다.
- emoji는 OS별 렌더링과 정렬 차이가 있어 사용하지 않는다.

실제 custom bitmap 또는 vector asset을 만들 경우 Dynamic Island의 작은 크기, monochrome/tinted rendering과 asset licensing을 함께 검증한다.

### 구현 결과

- `DonCheckMark`: compactLeading, minimal, expanded leading에서 재사용
- `CompactStageSummary`: symbol+숫자와 `N·M·O` fallback 제공
- `ExpandedStageSummary`: 전체/입금/저축 값을 명시적인 한국어 label로 표시
- 자동이체 확인 대상이 없으면 저축 metric을 숨김
- 잠금 화면 우측 요약도 입금/저축 단계별 분수로 통일
- 모든 presentation이 `ContentState`의 동일 computed aggregate를 사용
- compact, expanded, minimal에 축약되지 않은 VoiceOver label 제공

코드 빌드와 App Intents metadata 검증은 완료했다. Dynamic Island의 실제 폭과 카메라 주변 alignment는 지원 iPhone에서 최종 확인해야 한다.

### 기능 요구사항

| ID | 요구사항 |
|---|---|
| NEXT-003-FR-01 | compactLeading에 DonCheck를 식별할 수 있는 아이콘을 표시해야 한다. |
| NEXT-003-FR-02 | compactTrailing에서 전체, 입금 완료, 저축 완료 집계를 구분할 수 있어야 한다. |
| NEXT-003-FR-03 | expanded 영역에서는 `전체 N개 중 M개 입금 완료, O개 저축 완료` 의미를 생략 없이 제공해야 한다. |
| NEXT-003-FR-04 | 자동이체 확인 대상이 0개인 경우 저축 완료 집계를 숨기거나 `해당 없음`으로 표현해야 한다. |
| NEXT-003-FR-05 | 숫자가 두 자릿수 이상이어도 카메라 영역과 겹치거나 잘린 의미가 모호하지 않아야 한다. |
| NEXT-003-FR-06 | VoiceOver label에는 축약되지 않은 전체 진행 상태를 제공해야 한다. |
| NEXT-003-FR-07 | compact, minimal, expanded presentation에서 같은 `ContentState` 집계를 사용해야 한다. |

### 수용 조건

- compactLeading 아이콘이 카메라 왼쪽에서 선명하게 식별된다.
- compactTrailing만 보고 입금 완료와 저축 완료가 서로 다른 값임을 알 수 있다.
- 자동이체 확인 항목이 없을 때 불필요한 `저축 0` 표시로 혼란을 주지 않는다.
- 9개 이하, 10개 이상 항목에서 truncation과 alignment를 실제 Dynamic Island 지원 기기로 확인한다.
- expanded 영역과 잠금 화면의 집계가 앱 메인 화면 값과 일치한다.
- VoiceOver가 전체 항목, 입금 완료, 저축 완료를 자연스러운 순서로 읽는다.

## NEXT-004: 일정 기반 Live Activity attention window

### 구현 내용

- 자동이체 확인 항목에 `automaticTransferDay` 1~31 설정 추가
- 자동이체일이 없는 기존 v3 항목은 기존 `debitDay` 값으로 migration
- 명목 월급일이 주말 또는 동기화한 공휴일이면 연속 휴일을 건너뛴 직전 영업일을 실제 주기 시작일로 사용
- 명목 자동이체일이 주말 또는 동기화한 공휴일이면 연속 휴일을 건너뛴 다음 영업일을 실제 이체일로 사용
- 설정에서 iPhone 구독 공휴일 캘린더를 명시적으로 동기화하고 전년도부터 향후 2년까지의 종일 날짜를 App Group에 캐시
- 실제 월급일 하루 전 00:00부터 입금 미완료 cycle의 Live Activity 시작
- 영업일 보정된 항목별 실제 자동이체일 하루 전 00:00부터 저축 미완료 cycle의 Live Activity 시작
- 입금 또는 저축 단계를 체크하면 해당 attention window가 제거되고 active/pending activity를 재구성
- 월급일 하루 전에는 다음 cycle key를 사용하므로 미리 체크한 입금 상태가 월급일 이후에도 유지
- 공휴일 캐시 변경 시 completion cycle key를 새 실제 월급일 키로 매핑하여 체크 상태 유지
- v1~v3 completion cycle key를 영업일 보정된 실제 월급일 키로 migration

### 플랫폼 동작

- iOS 26 이상: 미래 attention window를 로컬 scheduled Live Activity로 예약하고 릴레이를 구성
- iOS 17~25: 미래 로컬 예약 API가 없으므로 attention window 중 앱이 실행되어 refresh될 때 즉시 시작
- 릴레이는 시스템의 동시 activity 한도 안에서 약 40시간 범위를 선예약하며 무기한 표시는 보장하지 않음

### 수용 조건

- 주말·공휴일 월급일의 cycle이 연속 휴일 전 마지막 영업일 00:00에 시작한다.
- 주말·공휴일 자동이체일은 연속 휴일 후 첫 영업일로 이동한다.
- 입금 Live Activity는 실제 월급일 하루 전 00:00부터 입금 완료까지 표시 대상이다.
- 자동이체 Live Activity는 설정일 하루 전 00:00부터 저축 완료까지 표시 대상이다.
- 서로 다른 자동이체일을 가진 항목들이 각각 올바른 attention window를 생성한다.
- 월말 29~31일 자동이체일은 짧은 달의 마지막 날로 보정된다.
- 공휴일 캘린더 미허용·미발견 상태에서는 안내 문구를 표시하고 주말 보정은 계속 동작한다.
- 기존 v3 데이터의 자동이체일과 완료 상태가 migration 후 유지된다.

## 구현 시 함께 갱신할 문서

- `Docs/product/requirements.md`: 기능 요구사항과 사용자 시나리오
- `Docs/features/checklist.md`: 주기 계산과 단계별 completion
- `Docs/features/app-ui.md`: 설정 및 row interaction
- `Docs/features/notifications.md`: 단계별 알림 identifier와 action
- `Docs/features/widgets.md`: 두 단계 표시 정책
- `Docs/features/live-activity.md`: content state와 intent 변경
- `Docs/data/storage.md`: schema version과 migration
- `Docs/development/testing.md`: 월급일 경계 및 단계별 회귀 테스트


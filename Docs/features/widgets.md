# 홈 화면과 잠금 화면 위젯

## 1. 개요

`DonCheckWidget`은 월별 체크 상태를 glanceable UI로 제공한다. WidgetKit extension은 앱과 별도 프로세스에서 실행되며 App Group 저장소를 직접 읽는다.

구현 파일:

- `DonCheckWidget/DonCheckWidget.swift`
- `DonCheckWidget/DonCheckWidgetBundle.swift`
- `Shared/ToggleSavingsItemIntent.swift`

Live Activity는 같은 widget bundle에 등록되지만 lifecycle과 렌더링 방식이 다르므로 [Live Activity 문서](live-activity.md)에서 별도로 설명한다.

## 2. Timeline 모델

```swift
struct ChecklistEntry: TimelineEntry {
    let date: Date
    let data: ChecklistData
    let cycleKey: String
}
```

entry는 렌더링 시점의 전체 checklist snapshot과 월 키를 포함한다.

### Placeholder

gallery placeholder는 청약저축과 연금저축 sample을 사용한다. 실제 사용자 데이터에 접근하지 않는다.

### Snapshot

- preview context: sample data
- 실제 snapshot: `ChecklistRepository.shared.load()`

### Timeline

현재 entry 한 개를 만들고 다음 자정 이후 reload하도록 `.after(nextMidnight)` policy를 반환한다. 자정 reload는 cycle key가 새 월로 전환되는 데 필요하다.

사용자가 앱 또는 intent로 상태를 변경하면 `WidgetCenter.shared.reloadAllTimelines()`를 별도로 호출하므로 자정까지 기다리지 않는다.

## 3. 지원 family

```swift
[.systemSmall,
 .systemMedium,
 .systemLarge,
 .accessoryRectangular,
 .accessoryCircular]
```

### systemSmall

- 제목과 icon
- 미완료 개수
- 남은 금액
- 진행률

공간 제약 때문에 개별 항목 체크는 표시하지 않는다.

### systemMedium

- 제목, 완료/전체 개수
- 진행률
- 최대 3개 항목 row
- row별 interactive check button

### systemLarge

- medium과 같은 구조
- 최대 7개 항목 row

### accessoryRectangular

- 이번 달 저축 제목
- 미완료 개수와 compact amount
- progress bar

### accessoryCircular

- gauge 형태
- 중앙에 미완료 개수

## 4. Interactive Widget

medium/large row는 다음 intent를 실행한다.

```swift
ToggleSavingsItemIntent(
    itemID: item.id.uuidString,
    cycleKey: entry.cycleKey,
    nextValue: !complete
)
```

intent가 `nextValue`를 명시적으로 받는 이유는 widget view가 일반 SwiftUI binding을 보유하지 못하기 때문이다. 렌더링 snapshot의 현재 상태를 바탕으로 다음 상태를 parameter로 만든다.

intent 완료 후 저장소와 timeline을 갱신하므로 toggle UI가 새 snapshot으로 수렴한다.

## 5. 데이터 공유

앱과 위젯은 모두 다음 App Group을 사용한다.

```text
group.com.heeyeon.DonCheck
```

필수 조건:

- 앱 entitlement에 동일 group 존재
- widget entitlement에 동일 group 존재
- provisioning profile에 capability 포함
- `AppConfig.appGroupIdentifier` 값 일치

repository는 suite 생성 실패 시 `.standard`로 fallback한다. 앱과 widget이 각각 standard defaults를 사용하면 서로 다른 컨테이너가 되므로 화면은 정상처럼 보여도 데이터가 공유되지 않는다. 이 현상은 App Group 구성 오류의 대표 증상이다.

## 6. 새로고침 트리거

위젯은 다음 상황에서 갱신된다.

- 다음 자정 timeline policy 도달
- 앱에서 item 저장/삭제/토글
- 위젯 또는 Live Activity intent 실행
- 시스템이 snapshot/timeline을 다시 요청

WidgetKit refresh 시점은 최종적으로 시스템이 조정한다. `reloadAllTimelines()`는 즉시 화면 redraw를 절대 보장하는 API가 아니라 reload 요청이다.

## 7. UI 제한

- widget은 scroll하지 않는다.
- 표시 개수를 초과한 항목은 생략된다.
- small/accessory family에서는 항목별 체크를 제공하지 않는다.
- 잠긴 상태의 interaction은 시스템 인증 정책을 따른다.
- iPhone widget을 Mac에 표시할 경우 interaction round trip이 길어질 수 있다.

## 8. Widget 추가 방법

### 홈 화면

1. 홈 화면 빈 영역 길게 누르기
2. 위젯 추가
3. `돈 체크` 또는 `이번 달 저축` 검색
4. 원하는 크기 선택

### 잠금 화면

1. 잠금 화면 길게 누르기
2. 사용자화
3. 잠금 화면 선택
4. 위젯 영역에 accessory widget 추가

잠금 화면 accessory widget은 요약용이다. 여러 체크 버튼이 필요한 경우 Live Activity를 사용한다.

## 9. 테스트 포인트

- 빈 데이터 placeholder가 아니라 empty message 표시
- 0/0 progress에서 division-by-zero 없음
- medium 3개, large 7개 truncation
- 자정 전후 cycle key 변경
- 앱 체크 후 widget reload
- widget 체크 후 앱 foreground reload
- App Group capability 제거 시 데이터 불일치 재현
- light/dark/tinted widget appearance
- 잠금 상태 authentication

# 데이터 저장소

## 1. 저장 전략

DonCheck는 App Group `UserDefaults`에 `ChecklistData` 전체를 JSON `Data`로 인코딩해 저장한다.

```text
Suite: group.com.heeyeon.DonCheck
Key:   checklist-data-v1
Value: JSONEncoder로 인코딩한 Data
```

이 전략은 개인용 소규모 데이터, 단일 기기, 단순 배포라는 MVP 조건에 맞춰 선택했다.

## 2. 저장 객체

최상위 객체:

```swift
struct ChecklistData: Codable {
    var items: [SavingsItem]
    var completions: [CompletionRecord]
}
```

개념적 JSON 예시:

```json
{
  "items": [
    {
      "id": "B0E9D05A-8B35-4C34-AE81-CC2D3059C71A",
      "name": "청약저축",
      "amount": 250000,
      "debitDay": 2,
      "reminderHour": 8,
      "reminderMinute": 0,
      "leadDays": 1,
      "followUpCount": 3,
      "createdAt": 815000000
    }
  ],
  "completions": [
    {
      "itemID": "B0E9D05A-8B35-4C34-AE81-CC2D3059C71A",
      "cycleKey": "2026-11",
      "completedAt": 815123456
    }
  ]
}
```

실제 `JSONEncoder`의 `Date` 기본 표현은 Apple reference date 기준 숫자다. 외부 호환 포맷으로 사용할 계획이라면 date encoding strategy를 명시해야 한다.

## 3. Repository API

### load

1. defaults에서 `Data` 조회
2. `JSONDecoder`로 `ChecklistData` decode
3. 값이 없거나 decode가 실패하면 빈 `ChecklistData` 반환

현재 decode 실패 원인을 기록하거나 손상 데이터를 별도 보관하지 않는다. schema migration을 추가할 때 이 silent fallback은 데이터 유실처럼 보일 수 있으므로 개선 대상이다.

### save

1. `JSONEncoder`로 전체 객체 encode
2. defaults의 `checklist-data-v1` key에 저장

encode 실패는 현재 무시한다. 모든 필드가 표준 Codable 타입이므로 일반 상태에서 실패하지 않지만 운영 진단을 위해 logging을 추가할 수 있다.

### setCompletion

위젯과 notification action처럼 `ChecklistStore`를 거치지 않는 경로에서 사용한다.

1. 최신 데이터 load
2. 동일 item/month completion 제거
3. 완료 요청이면 새 record 추가
4. save
5. 변경된 전체 data 반환

## 4. App Group

### 필요한 이유

iOS 앱과 widget extension은 서로 다른 sandbox와 `UserDefaults.standard`를 가진다. App Group suite를 사용해야 두 프로세스가 같은 container에 접근할 수 있다.

### 구성 위치

```text
Shared/AppConfig.swift
DonCheck/DonCheck.entitlements
DonCheckWidget/DonCheckWidget.entitlements
Xcode Signing & Capabilities
Provisioning profiles
```

모든 위치의 group identifier가 정확히 같아야 한다.

### Fallback 동작

```swift
init(defaults: UserDefaults? = UserDefaults(suiteName: AppConfig.appGroupIdentifier)) {
    self.defaults = defaults ?? .standard
}
```

suite를 만들 수 없으면 standard defaults로 fallback한다. 앱 단독 기능은 살아남지만 앱과 widget의 standard defaults는 서로 다르다. production에서 App Group이 필수라면 fallback 대신 assertion 또는 명시적 오류를 사용하는 편이 문제를 빨리 발견하는 데 유리하다.

## 5. 데이터 수명

- 항목은 사용자가 삭제할 때까지 유지한다.
- 항목 삭제 시 해당 item의 모든 completion도 삭제한다.
- completion은 저장 시 기본 24개월 보존한다.
- 앱 삭제 시 local data가 제거될 수 있다.
- iCloud backup/sync 동작은 제품 기능으로 보장하지 않는다.

## 6. Schema version

현재 저장 key suffix가 사실상의 schema version이다.

```text
checklist-data-v1
```

모델 필드를 non-optional로 추가하면 기존 JSON decode가 실패할 수 있다. 안전한 변경 패턴:

- 새 필드를 optional로 추가
- custom `init(from:)`에서 기본값 제공
- `checklist-data-v2`로 migrate
- 이전 payload를 decode한 후 새 schema로 변환

ActivityKit attributes는 `UserDefaults`와 별도로 시스템이 보존할 수 있다. `scheduledStart`를 optional로 둔 이유도 이전 activity payload와의 호환성 때문이다.

## 7. 동시 쓰기 위험

repository는 file lock, database transaction, compare-and-swap을 제공하지 않는다.

위험 시나리오:

1. 앱이 data A를 load
2. widget intent가 data A를 load
3. 앱이 item X를 완료하고 save
4. widget이 item Y를 완료하고 이전 snapshot 기반으로 save
5. item X 변경이 덮일 수 있음

사용 빈도가 낮아 MVP에서는 허용하지만 안정성을 높이려면 SQLite 계열 저장소나 coordination이 필요하다.

## 8. Database로 전환할 조건

다음 중 하나가 필요해지면 `UserDefaults` 전체 snapshot 방식에서 벗어나는 것을 권장한다.

- 수십 개 이상의 항목과 장기 history
- 여러 기기 동기화
- 동시에 여러 extension에서 자주 쓰기
- 완료 audit/history 화면
- 검색, 통계, 월별 aggregate query
- schema migration이 빈번함
- 데이터 export/import

전환 시 `ChecklistRepository` protocol을 먼저 추출하면 UI와 system integration 코드를 유지하기 쉽다.

## 9. 개인정보 및 보안

현재 저장 데이터에는 항목 이름과 금액이 포함된다. 계좌번호는 저장하지 않지만 금융 관련 개인 정보로 간주할 수 있다.

- App Group container는 앱 group sandbox 안에 있다.
- 별도 application-level encryption은 적용하지 않는다.
- 잠금 화면 widget/Live Activity에 금액이 노출될 수 있다.
- 민감 정보 노출 설정 또는 금액 숨김 기능은 현재 없다.

공개 배포 전에는 잠금 화면 privacy mode와 device backup 정책을 검토해야 한다.

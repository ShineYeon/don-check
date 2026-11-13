# 문제 해결 가이드

## 1. 진단 기본 원칙

DonCheck는 앱, WidgetKit extension, `chronod`, `liveactivitiesd`, notification daemon이 함께 동작한다. 콘솔 한 줄보다 다음 세 가지를 함께 확인한다.

1. 앱 저장 데이터가 올바른가?
2. 시스템 request가 생성되었는가?
3. extension이 request를 렌더링할 수 있는가?

## 2. Live Activity가 표시되지 않음

### 2.1 미완료 항목 확인

Live Activity는 미완료 항목이 없으면 시작하지 않는다. 설정 화면 버튼을 누르면 다음 메시지가 나타나야 한다.

```text
표시할 미완료 저축 항목이 없습니다.
```

### 2.2 시스템 설정 확인

실제 iPhone에서 앱의 Live Activities 설정이 켜져 있는지 확인한다. 비활성화 상태에서는 다음 메시지를 표시한다.

```text
Live Activity가 꺼져 있습니다. iPhone 설정에서 돈 체크의 Live Activity를 허용해 주세요.
```

### 2.3 Info.plist 확인

빌드 결과 앱 plist에 다음 값이 있어야 한다.

```bash
plutil -p <DerivedData>/Build/Products/Debug-iphonesimulator/DonCheck.app/Info.plist \
  | rg NSSupportsLiveActivities
```

기대 값:

```text
"NSSupportsLiveActivities" => true
```

### 2.4 Extension embedding 확인

```text
DonCheck.app/PlugIns/DonCheckWidget.appex
```

경로가 없으면 앱 타깃의 Embed App Extensions build phase와 target dependency를 확인한다.

## 3. `[S:1] Error received: Connection invalidated`

이 메시지는 원인 자체가 아니라 XPC 연결이 종료되었다는 결과일 수 있다.

정상적으로도 나타날 수 있는 상황:

- 앱 재설치
- 앱/extension 프로세스 종료
- widget snapshot 요청 종료
- 새 build로 extension 교체

실패로 판단해야 하는 경우:

- Live Activity가 보이지 않음
- 같은 시각에 maximum/authorization/visibility/unentitled 오류 존재
- extension이 반복 crash

### 실제로 발생했던 원인

초기 릴레이 구현이 pending activity 5개를 먼저 생성해 target limit을 모두 사용했다. 이후 수동 시작 request가 여섯 번째 activity가 되어 다음 오류로 거절됐다.

```text
Cannot create new activity as maximum count for target has been reached
```

현재 구현은 다음 방식으로 해결한다.

- 수동 시작 전에 pending activity 정리
- active가 있으면 pending 최대 4개
- active가 없을 때만 pending 최대 5개
- 이전 attributes schema와 호환되도록 `scheduledStart` optional 처리

## 4. ActivityKit 로그 수집

### Simulator

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun simctl spawn booted log show \
  --last 10m \
  --style compact \
  --predicate '(process == "liveactivitiesd" OR process == "DonCheck" OR process == "DonCheckWidget")'
```

필터를 좁히려면:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun simctl spawn booted log show \
  --last 10m \
  --style compact \
  --predicate '(process == "liveactivitiesd" OR process == "DonCheck") AND (eventMessage CONTAINS[c] "maximum" OR eventMessage CONTAINS[c] "Starting activity" OR eventMessage CONTAINS[c] "authorization" OR eventMessage CONTAINS[c] "visibility")'
```

### 실제 기기

Xcode의 Devices and Simulators 또는 macOS Console 앱에서 연결된 iPhone을 선택하고 다음 process/subsystem을 검색한다.

```text
DonCheck
DonCheckWidget
liveactivitiesd
com.apple.activitykit
```

## 5. 앱과 위젯 데이터가 다름

가장 흔한 원인은 App Group 불일치다.

확인 값:

```text
group.com.heeyeon.DonCheck
```

다음 파일을 비교한다.

- `Shared/AppConfig.swift`
- `DonCheck/DonCheck.entitlements`
- `DonCheckWidget/DonCheckWidget.entitlements`

실제 기기에서는 signing profile에도 같은 group이 포함되어야 한다.

repository가 suite 생성 실패 시 standard defaults로 fallback하기 때문에 앱과 위젯이 각각 다른 데이터를 정상적으로 읽는 것처럼 보일 수 있다.

## 6. 위젯이 목록에 나타나지 않음

1. 앱을 한 번 실행한다.
2. widget extension이 앱에 embed되었는지 확인한다.
3. extension Info.plist의 point identifier를 확인한다.
4. 앱/위젯 version과 Bundle ID를 확인한다.
5. 시뮬레이터에서 앱을 삭제하고 다시 설치한다.
6. 전체 `DonCheck` scheme을 build한다.

필수 plist:

```text
NSExtensionPointIdentifier = com.apple.widgetkit-extension
```

## 7. App Intents metadata build 실패

증상:

```text
AppIntentsSSUTraining failed
Unable to parse Info.plist
```

Widget extension 수동 plist에 다음 기본 bundle key가 있는지 확인한다.

- `CFBundleExecutable`
- `CFBundleIdentifier`
- `CFBundleInfoDictionaryVersion`
- `CFBundleName`
- `CFBundlePackageType`
- `CFBundleShortVersionString`
- `CFBundleVersion`

그리고 `plutil -lint DonCheckWidget/Info.plist`를 실행한다.

## 8. 알림이 오지 않음

확인 순서:

1. 설정 화면에서 권한이 `허용됨`인지 확인
2. iOS 설정에서 돈 체크의 잠금 화면/배너/사운드 확인
3. Time Sensitive 허용 여부 확인
4. 항목의 출금일과 알림 시각이 미래인지 확인
5. `알림 일정 다시 만들기` 실행
6. Focus/알림 요약 설정 확인
7. pending request 수가 60개 제한에 의해 잘리지 않았는지 확인

이미 지난 시각은 request를 만들지 않는다. 테스트 시 최소 몇 분 뒤로 설정한다.

## 9. 체크했는데 알림이 남음

완료 시 pending과 delivered notification을 모두 제거한다. 오래된 build에서 생성한 identifier 형식이 다르면 prefix match가 되지 않을 수 있다.

현재 identifier:

```text
doncheck.<UUID>.<yyyy-MM-dd>.<step>.<kind>
```

개발 중 schema를 바꿨다면 Simulator 설정에서 notification을 지우거나 앱을 재설치한다.

## 10. Live Activity는 보이지만 체크가 반영되지 않음

1. App Group 데이터 공유 확인
2. `ToggleSavingsItemIntent`가 앱과 widget target 양쪽 Compile Sources에 포함되었는지 확인
3. App Intents metadata extraction 성공 확인
4. 잠금 상태라면 인증 후 다시 시도
5. `DonCheckWidget` process crash log 확인

intent 성공 후 다음이 모두 실행되어야 한다.

- repository update
- notification reschedule
- Live Activity refresh
- widget timeline reload

## 11. 빌드가 Xcode 라이선스로 차단됨

```bash
sudo xcodebuild -license
```

그 후:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
```

## 12. 완전 초기화

개발 Simulator에서만 사용한다. 앱을 삭제하면 일반 app container는 제거되지만 system activity 상태가 잠시 남을 수 있다.

권장 순서:

1. 실행 중 앱 종료
2. Simulator에서 앱 삭제
3. 필요하면 Simulator 재부팅
4. 최신 build 설치
5. 앱 실행 후 권한 재허용

실제 사용자 기기에서는 데이터 삭제가 복구되지 않으므로 초기화를 안내하기 전에 반드시 데이터 손실을 고지해야 한다.

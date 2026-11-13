# 빌드, 서명, 실제 기기 설치

## 1. 개발 환경

권장 환경:

- macOS에서 실행되는 Xcode 26.6 이상
- iOS 26.x Simulator
- Swift 5 language mode
- 최소 deployment target iOS 17.0

프로젝트는 외부 package dependency가 없으므로 clone 후 package resolution 단계가 필요하지 않다.

## 2. Xcode 프로젝트 열기

```text
DonCheck.xcodeproj
```

scheme은 `DonCheck`를 선택한다. 앱 타깃이 `DonCheckWidget`에 target dependency를 갖고 Embed App Extensions build phase에서 `.appex`를 포함한다.

## 3. Xcode 라이선스와 developer directory

CLI에서 다음 오류가 발생할 수 있다.

```text
You have not agreed to the Xcode license agreements.
```

한 번 다음 명령을 실행한다.

```bash
sudo xcodebuild -license
```

시스템의 `xcode-select`가 Command Line Tools를 가리키는 경우 명령마다 `DEVELOPER_DIR`를 지정하거나 developer directory를 변경한다.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
```

## 4. Simulator 빌드

서명 없이 전체 app + extension을 검증한다.

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

성공 기준:

```text
** BUILD SUCCEEDED **
```

이 빌드는 다음을 함께 검증한다.

- 앱 Swift compile/link
- widget extension compile/link
- App Intents metadata extraction
- Live Activity configuration
- extension embedding
- embedded binary validation
- Info.plist processing

앱 타깃만 typecheck하는 것으로는 extension Info.plist나 App Intents metadata 오류를 발견할 수 없다.

## 5. Simulator 설치와 실행

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun simctl install booted \
/tmp/DonCheckDerivedData/Build/Products/Debug-iphonesimulator/DonCheck.app

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun simctl launch booted com.heeyeon.DonCheck
```

Live Activity debug start:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun simctl launch booted com.heeyeon.DonCheck -startLiveChecklist
```

이 argument는 `#if DEBUG`에서만 처리한다. 미완료 항목이 없으면 activity가 생성되지 않는다.

## 6. 실제 기기 서명

### 앱 타깃

1. `DonCheck` target 선택
2. Signing & Capabilities 열기
3. Automatically manage signing 활성화
4. Team 선택
5. Bundle Identifier가 계정에서 사용 가능한지 확인
6. App Groups capability에 group 등록

### 위젯 타깃

1. `DonCheckWidget` target 선택
2. 앱과 같은 Team 선택
3. Widget Bundle ID 확인
4. 앱과 같은 App Group capability 등록

앱과 extension의 Team이 다르거나 App Group entitlement가 provisioning profile과 일치하지 않으면 설치 또는 데이터 공유가 실패한다.

## 7. Bundle ID 변경 절차

예를 들어 base ID를 `com.example.DonCheck`로 변경한다면:

```text
App:      com.example.DonCheck
Widget:   com.example.DonCheck.Widget
AppGroup: group.com.example.DonCheck
```

수정 위치:

1. Xcode target build settings의 `PRODUCT_BUNDLE_IDENTIFIER`
2. `Shared/AppConfig.swift`
3. 앱 entitlement
4. 위젯 entitlement
5. Apple Developer App ID/App Group configuration

widget bundle ID는 containing app bundle ID의 prefix를 사용하는 것이 안전하다.

## 8. Info.plist 요구사항

앱 Info.plist는 build setting으로 생성하며 다음 key가 필요하다.

```text
NSSupportsLiveActivities = YES
NSCalendarsFullAccessUsageDescription = 월급일과 자동이체일을 공휴일 기준으로 조정하기 위해 공휴일 캘린더를 읽습니다.
```

앱은 EventKit의 full calendar access를 공휴일 동기화 버튼을 누른 경우에만 요청한다. 이 usage description이 없으면 권한 요청 시 앱이 종료되므로 Debug와 Release build configuration에 모두 유지해야 한다. Widget extension은 캘린더에 직접 접근하지 않아 해당 key가 필요 없다.

Widget extension의 `Info.plist`에는 최소 다음 값이 들어간다.

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.widgetkit-extension</string>
</dict>
```

수동 plist를 사용할 때 CFBundleIdentifier, CFBundleExecutable, version key가 빠지면 App Intents metadata 단계가 `Unable to parse Info.plist`로 실패할 수 있다.

## 9. Capability 점검

| Capability | 앱 | 위젯 | 비고 |
|---|---:|---:|---|
| App Groups | 필요 | 필요 | 동일 group 사용 |
| Push Notifications | 불필요 | 불필요 | 현재 APNs 서버 없음 |
| Live Activities | Info key | ActivityConfiguration | 별도 push entitlement 미사용 |

향후 APNs로 Live Activity를 갱신한다면 Push Notifications capability와 APNs environment entitlement가 추가로 필요하다.

## 10. Release 전 확인

- Release configuration 빌드
- 실제 기기에서 알림 권한과 Live Activity 권한 확인
- 앱/위젯 Bundle ID 및 version 일치
- App Group production provisioning 확인
- 앱 아이콘 및 privacy metadata 추가
- 잠금 화면 금액 노출에 대한 제품 정책 검토
- extension binary가 앱에 포함되는지 archive에서 확인
- 장기 relay가 실제 기기에서 시스템 정책에 따라 동작하는지 검증

현재 프로젝트는 개인 설치용 MVP이며 App Store 제출에 필요한 icon, screenshots, privacy manifest 검토와 store metadata 작업은 별도다.

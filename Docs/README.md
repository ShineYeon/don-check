# DonCheck 개발 문서

이 디렉터리는 기능과 운영 영역별 상세 문서를 보관합니다. 루트 [README](../README.md)는 설치와 전체 개요를 제공하고, 이곳의 문서는 구현을 변경하거나 장애를 분석하는 개발자를 대상으로 합니다.

## 읽는 순서

처음 프로젝트를 이해하는 경우 다음 순서를 권장합니다.

1. [제품 요구사항](product/requirements.md)
2. [아키텍처 개요](architecture/overview.md)
3. [체크리스트와 월별 주기](features/checklist.md)
4. [앱 UI와 상태 관리](features/app-ui.md)
5. [저장소](data/storage.md)
6. [알림](features/notifications.md)
7. [Live Activity](features/live-activity.md)
8. [위젯](features/widgets.md)
9. [빌드와 서명](development/build-and-signing.md)
10. [테스트](development/testing.md)
11. [문제 해결](operations/troubleshooting.md)

## 영역별 문서

### Product

- [requirements.md](product/requirements.md): 해결하려는 문제, 핵심 시나리오, 범위와 비범위

### Architecture

- [overview.md](architecture/overview.md): 앱/extension 프로세스, 공유 모듈, 동기화 흐름

### Features

- [checklist.md](features/checklist.md): 항목 CRUD, 월 키, 완료 기록, 월말 보정
- [app-ui.md](features/app-ui.md): SwiftUI 화면, 입력 검증, observable state
- [notifications.md](features/notifications.md): 로컬 알림 생성과 액션 처리
- [live-activity.md](features/live-activity.md): ActivityKit 모델, 릴레이 유지, UI와 제약
- [widgets.md](features/widgets.md): WidgetKit timeline, family별 레이아웃, interactive intent

### Data

- [storage.md](data/storage.md): App Group 저장소, 인코딩, 보존 정책, migration 고려사항

### Development

- [build-and-signing.md](development/build-and-signing.md): 로컬 빌드, capability, Bundle ID 변경
- [testing.md](development/testing.md): 기능별 검증 절차와 회귀 체크리스트

### Operations

- [troubleshooting.md](operations/troubleshooting.md): Live Activity/위젯/알림 문제의 진단 순서

## 문서 관리 규칙

- 구현 동작을 변경하는 PR은 관련 기능 문서를 함께 갱신합니다.
- OS 버전 조건이 있는 동작은 지원 버전과 fallback을 모두 기록합니다.
- 시스템이 보장하지 않는 동작은 보장처럼 표현하지 않습니다.
- 식별자, 저장 키, notification category/action ID 변경 시 검색 가능한 정확한 문자열을 남깁니다.
- 장애 사례는 증상뿐 아니라 로그 키워드, 원인, 해결 방법을 기록합니다.

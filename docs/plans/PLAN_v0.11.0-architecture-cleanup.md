# Implementation Plan: v0.11.0 — Architecture Cleanup

**Status**: ⏳ Pending
**Started**: 2026-05-01
**Last Updated**: 2026-05-01
**Estimated Completion**: 4-6시간 (i18n 범위 좁힌 가정)

## Overview

v0.10.0 final 리뷰의 후속 후보 3건 처리:

1. `OAuthSetup` `~Sendable` 명시 — 미래 안전성, 컴파일러가 강제
2. VendorPickerSheet → AuthCoordinator 분리 — 510줄 + 테스트 가능성
3. i18n 인프라 + 사용자 가시 문자열 sweep — `String(localized:)` 마이그레이션

### Success Criteria

- [ ] `OAuthSetup` 이 `~Sendable` 로 컴파일러가 Task 경계 차단
- [ ] `VendorPickerAuthCoordinator` 가 단위 테스트 가능 위치 (MaestroAdapters 또는 MaestroCore)
- [ ] VendorPickerSheet.swift 500줄 이하, file_length disable 제거
- [ ] AuthCoordinator 단위 테스트 5개 이상 추가
- [ ] String Catalog (`Localizable.xcstrings`) 신규 + 사용자 가시 문자열 마이그레이션
- [ ] swift test pass + lint clean

## Phase 1: OAuthSetup ~Sendable (15분)

- [ ] `Sources/MaestroCore/InteractiveAuthHelper.swift` 의 `OAuthSetup` 에 `~Sendable` 추가
- [ ] swift build 통과 확인
- [ ] (실패 시) Task 경계 캡처 위치 식별 + 수정

## Phase 2: VendorPickerAuthCoordinator 분리 (2-3시간)

### 분리 대상 (View → Coordinator):

- `loginInProgress`, `loginMessage`, `loginTask`
- `authStateByAdapter`, `loadAuth(for:)`, `performLogin(for:)`
- `loginGuideText`, `loginFallbackText` 같은 helper

### 신규 위치

- `Sources/MaestroCore/VendorPickerAuthCoordinator.swift` (또는 MaestroAdapters)
- `@Observable @MainActor public final class VendorPickerAuthCoordinator`

### View 가 보유:

- 셀렉션, 디스플레이 로직
- coordinator 를 `@Bindable` 로 받음

### 테스트

- `Tests/.../VendorPickerAuthCoordinatorTests.swift`:
  - performLogin 호출 → loginInProgress true
  - cancel → loginTask nil + 좀비 없음
  - browserOpenFailed → 클립보드 복사 검증

### Quality Gate

- [ ] file_length disable 제거 (VendorPickerSheet.swift 500줄 이하)
- [ ] 새 테스트 5+개 추가
- [ ] swift test pass

## Phase 3: i18n Sweep (2-3시간, 범위 한정)

### 범위

사용자 가시 문자열만 (a11y label 포함). 디버그 로그, 주석은 제외.

### 작업

- [ ] `Sources/Maestro/Resources/Localizable.xcstrings` 신규 (Xcode String Catalog)
- [ ] `String(localized:)` 또는 `LocalizedStringKey` 로 일괄 변환
- [ ] 한국어 (`ko`) 만 채움 (영어/일본어 후속 사이클)
- [ ] grep 검증: `Text("` 으로 한국어 hardcoded 0건

### Quality Gate

- [ ] 모든 사용자 가시 문자열이 String Catalog 통해 표시
- [ ] Maestro 실행 시 텍스트 표시 회귀 0
- [ ] swift test pass

## Phase 4: 통합 검증 + Release

- [ ] swift test 풀 스위트 + lint clean
- [ ] 4-agent final 리뷰 (cumulative)
- [ ] CHANGELOG v0.11.0
- [ ] appVersion 0.10.0 → 0.11.0
- [ ] git tag + push + DMG 설치 검증

## 진행 상태

- [ ] Phase 1: ~Sendable
- [ ] Phase 2: AuthCoordinator
- [ ] Phase 3: i18n
- [ ] Phase 4: 통합 + Release

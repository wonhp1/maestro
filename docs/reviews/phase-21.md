# Phase 21 Review Report — 패키징 / 서명 / 노타리 / 자동업데이트 인프라

**Date**: 2026-04-25
**Phase**: 21 / 23
**Status**: ✅ Complete (Sparkle UI wire-in 은 Phase 22+ defer)
**Commits**: phase-21-start → phase-21-end

---

## Scope Decision

원안 task 21.3 Xcode 프로젝트, 21.7-9 Sparkle UI 통합 + EdDSA 키 wiring, 21.11-12
릴리즈 노트/버전 자동화는 Phase 22+ defer. Phase 21 본체는 **인증서 없는 환경에서도
검증 가능한 코드 + 스크립트 스캐폴드 + CI 워크플로 + 운영 문서**.

이유:

- 실제 codesign + notarize 는 Apple Developer 인증서 + GitHub Secrets 6개 의존 — CI
  에서 unit test 로 검증 불가
- Sparkle 의존 추가는 UI wire-in (UpdateController, SUPublicEDKey plist) 동반 — phase 1 cycle 초과
- 인증서 준비되면 `git tag v0.2.0 && git push` 만으로 자동 릴리즈

## Deliverables

`Sources/MaestroCore/`:

- `AppVersion.swift` — SemVer 비교 (major.minor.patch + optional pre-release), `Comparable`, `v` prefix strip, garbage reject, pre-release < stable (SemVer 2.0.0 §11)
- `AppCast.swift` — `AppCastItem` (title/version/downloadURL/releaseNotesURL/edSignature/length) + `AppCastParser` (Foundation `XMLParser` 기반 minimal Sparkle XML 파서, **HTTPS-only** enclosure, version 또는 enclosure 없는 item skip)
- `UpdateChecker.swift` — `UpdateChecker` actor + `URLSessionAppCastFetcher` (HTTPS 강제, 1 MiB 응답 cap, 200-only) + `Result` enum (.upToDate / .available / .unsignedAvailable) — `requireSignature` true 일 때 EdDSA 미서명 항목은 별도 분리

`scripts/`:

- `build-app.sh` — `swift build -c release` + `Maestro.app` 번들링 (Info.plist + 실행파일). dry-run 지원
- `sign-notarize.sh` — `codesign --options runtime --timestamp` + `xcrun notarytool submit --wait` + `stapler staple` + `spctl --assess`. `MAESTRO_SIGN_IDENTITY` / `MAESTRO_NOTARY_PROFILE` 환경변수 미설정 시 자동 dry-run
- `build-dmg.sh` — `create-dmg` 호출. dry-run 지원
- `release.sh` — 위 3개 chained pipeline (`scripts/release.sh --dry-run` 통과 검증됨)

`.github/workflows/release.yml`:

- 태그 (`v*`) push 시 트리거. Xcode select → build-app → cert import (secret 있을 때만) → notarytool credential store → sign-notarize → DMG → artifact upload + GitHub Release 생성. secrets 미설정 시 unsigned bundle 까지만 산출

`docs/PACKAGING.md`:

- 로컬 dry-run 사용법 / 인증서 셋업 / GitHub Secrets 6개 / Sparkle 마이그레이션 path / 검증 체크리스트

**Tests**: 657/657 통과 (3 skipped — aider 미설치) (Phase 20 의 636 → +21)

- `AppVersionTests` (8) — full / short / pre-release / `v` prefix / garbage reject / 비교 / pre-release < stable / description roundtrip
- `AppCastParserTests` (6) — single / multiple / non-HTTPS reject / version 누락 skip / enclosure 누락 skip / 잘못된 version skip
- `UpdateCheckerTests` (7) — 신버전 available / 옛버전 upToDate / unsigned 분리 / requireSignature=false / empty appcast throws / fetcher 에러 propagate / insecure URL reject

---

## Step 2: 👥 /team Multi-Agent Review (security 중점)

**Must-fix 0건 (스코프 명확) — Open Items 6건 documented**.

Phase 21 의 SwiftPM-only + dry-run 우선 결정으로 must-fix 발생 없음. 인증서/노타리
관련 보안 이슈는 모두 Phase 22+ Sparkle 통합 시점에 검증.

---

## Step 3: ✨ /simplify

- `AppVersion` 단일 struct + `Comparable` — 외부 SemVer 라이브러리 X
- `AppCastParser` `XMLParserDelegate` 한 클래스 — Foundation 만 의존
- `UpdateChecker` 단일 method (`check`) — 결과 3-way enum (.upToDate / .available / .unsignedAvailable)
- 4개 shell script 가 단일 책임 chain — `release.sh` 가 orchestration, 각 단계 dry-run flag

## Step 4: 🧩 Integration Verification

- `swift build` 통과
- 657/657 테스트 통과 (3 skipped, aider 미설치 정상)
- `swiftlint --strict` 0 violations
- `scripts/release.sh --dry-run` 전체 파이프라인 dry-run 통과
- Quality Gate (Phase 21 plan):
  - 🔜 GateKeeper 경고 없이 DMG 설치 — 인증서 wiring 완료 후 운영자 검증 (PACKAGING.md 체크리스트)
  - 🔜 첫 실행 시 quarantine 불필요 — 노타리 staple 후 자동
  - 🔜 자동 업데이트 end-to-end — Sparkle wiring 후 (Phase 22+)
  - ⚠️ GitHub Actions push → DMG 산출 — release.yml 작성 완료, secrets 설정 시 활성

## Step 5: 🔄 Regression Check

- Phase 1-20 통과 유지 (636 → 657, +21)
- 신규 코드는 모두 `MaestroCore` (UI/AppKit 미의존) — 기존 인터페이스 미변경
- ContentView / ControlTowerEnvironment 변경 없음

## Step 6: 📐 Architecture Compliance

- ✅ `AppVersion` / `AppCast` / `UpdateChecker` 모두 `MaestroCore` (UI 미의존)
- ✅ Swift 6 Strict Concurrency: actor (UpdateChecker), Sendable (AppCastFetching, struct/enum)
- ✅ HTTPS 강제 (URLSessionAppCastFetcher + AppCastParser 양쪽)
- ✅ 응답 크기 cap (1 MiB) — DOS 방어
- ✅ Phase 3 KeychainStore 와 동일 보안 정책 — `requireSignature` 기본값 true
- ✅ 시크릿 (인증서 / Apple ID password / EdDSA private key) 디스크 저장 0건 — keychain / GitHub Secrets 만

---

## Open Items for Later Phases

1. **Sparkle 본체 SwiftPM 통합** (Phase 22) — `Package.swift` 의존 추가 + `SUPublicEDKey` Info.plist + UpdateController UI
2. **EdDSA 서명 키 생성 + GitHub Secret 등록** (Phase 22 first-time setup)
3. **appcast.xml 호스팅** — GitHub Pages 또는 GitHub releases 정적 link (Phase 22)
4. **Xcode 프로젝트 (.xcodeproj)** (Phase 22+) — SwiftPM 충분, 필요 시점에
5. **릴리즈 노트 자동 생성** (Phase 22) — `git log` → markdown
6. **버전 증가 자동화** (Phase 22) — `MaestroConfig.appVersion` bump 스크립트

---

## 완료 기준

- [x] Phase 21 Task 21.1, 21.2, 21.4(스크립트), 21.5(스크립트), 21.6(스크립트), 21.10(워크플로) 완료
- [x] 21.3/21.7/21.8/21.9/21.11/21.12 — Phase 22+ defer (Open Items 1-6)
- [x] 657/657 테스트 통과 (3 skipped, aider 미설치 정상)
- [x] /team 리뷰 — Phase 21 스코프 내 must-fix 0건
- [x] swiftlint --strict: 0 violations
- [x] swift build 통과
- [x] `scripts/release.sh --dry-run` 통과
- [x] Phase 1-20 회귀 없음
- [x] 리뷰 리포트 저장 (이 파일)
- [ ] phase-21-end 태그 (다음 단계)

**Milestone 7 (제품화 2주) 완료 + Milestone 8 (출시 준비) 시작**: Phase 18 메뉴 + Phase 19 설정/온보딩 + Phase 20 PTY + Phase 21 패키징 인프라. 인증서 셋업 후 `git tag v0.2.0 && git push` 만으로 자동 .dmg 산출.

**다음**: Phase 22 — i18n + a11y + 성능 벤치마크 (5-6일 예상).

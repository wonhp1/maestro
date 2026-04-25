# Maestro 패키징 / 서명 / 노타리제이션 / 자동 업데이트

Phase 21 산출물의 운영 가이드.

## 1. 로컬 dry-run

인증서 없이도 전체 파이프라인 흐름 검증:

```bash
scripts/release.sh --dry-run
```

각 단계 (build / sign / notarize / DMG) 가 어떤 명령을 실행하는지 stdout 출력. 실제
파일은 만들지 않음.

## 2. 인증서 / 노타리 셋업 (개발자 본인 Mac)

### Apple Developer 인증서

1. Apple Developer Program 가입 (연 99 USD).
2. https://developer.apple.com/account/resources/certificates → "Developer ID
   Application" 인증서 생성 (Keychain 의 CSR 사용).
3. 인증서를 macOS 키체인에 설치되어 있어야 함 — 보통 다운로드한 `.cer` 더블클릭.

### Notarytool credential

```bash
# Apple ID 의 app-specific password 가 필요 (https://account.apple.com).
xcrun notarytool store-credentials maestro-notary \
  --apple-id <YOUR_APPLE_ID> \
  --team-id <YOUR_TEAM_ID> \
  --password <APP_SPECIFIC_PASSWORD>
```

### 환경변수

```bash
export MAESTRO_SIGN_IDENTITY="Developer ID Application: 김경원 (TEAMID)"
export MAESTRO_NOTARY_PROFILE="maestro-notary"
```

### 빌드 + 서명 + 노타리 + DMG

```bash
scripts/release.sh
# 산출: build/Maestro-<version>.dmg
```

`spctl --assess --verbose=4 build/Maestro.app` 으로 GateKeeper 통과 확인.

## 3. GitHub Actions 릴리즈 워크플로

`.github/workflows/release.yml` — 태그 (`v*`) push 시 자동 트리거.

### 필요한 GitHub Secrets (Settings → Secrets and variables → Actions)

| Secret 이름                   | 내용                                                  |
| ----------------------------- | ----------------------------------------------------- |
| `MAESTRO_SIGN_IDENTITY`       | `Developer ID Application: NAME (TEAM)`               |
| `MAESTRO_SIGN_P12_BASE64`     | `.p12` 인증서 base64 (`base64 -i cert.p12 \| pbcopy`) |
| `MAESTRO_SIGN_P12_PASSWORD`   | `.p12` password                                       |
| `MAESTRO_NOTARY_APPLE_ID`     | Apple ID                                              |
| `MAESTRO_NOTARY_TEAM_ID`      | Team ID                                               |
| `MAESTRO_NOTARY_APP_PASSWORD` | app-specific password                                 |

secrets 미설정 시 sign-notarize 단계가 자동 dry-run — unsigned `.app` + DMG 까지만
산출 (PR 검토용).

### 릴리즈 절차

```bash
git tag v0.2.0
git push origin v0.2.0
# GitHub Actions 가 빌드 → 서명 → 노타리 → DMG → Release 생성
```

## 4. Sparkle 자동 업데이트 (Phase 21 → 22 마이그레이션 예정)

현재 Phase 21 은 다음만 ship:

- `AppVersion` (SemVer 비교)
- `AppCastParser` (Sparkle XML 파싱)
- `UpdateChecker` actor (HTTPS 강제, 1 MiB 응답 cap, EdDSA 서명 존재 여부 검증)

**Sparkle 본체 SwiftPM 의존 + UI wiring 은 Phase 22+ 에서**:

1. Package.swift 에 `https://github.com/sparkle-project/Sparkle.git` 추가
2. EdDSA 서명 키 생성 — `generate_keys` 도구 (Sparkle 배포에 포함)
3. public key 를 Info.plist `SUPublicEDKey` 로 박음
4. private key 는 `MAESTRO_SPARKLE_ED_PRIVATE_KEY` GitHub Secret 으로
5. release.yml 에서 `sign_update <dmg-path>` 로 EdDSA 서명 → appcast.xml 의
   `sparkle:edSignature` 업데이트

현재의 `UpdateChecker.requireSignature = true` 가 미서명 항목을
`.unsignedAvailable` 로 분리해 UI 가 사용자에게 명확히 보여줄 수 있도록 준비됨.

### appcast.xml 호스팅

GitHub Pages 또는 정적 호스팅:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Maestro</title>
    <item>
      <title>0.2.0</title>
      <sparkle:version>0.2.0</sparkle:version>
      <sparkle:releaseNotesLink>https://...</sparkle:releaseNotesLink>
      <enclosure
        url="https://github.com/wonhp1/maestro/releases/download/v0.2.0/Maestro-0.2.0.dmg"
        sparkle:edSignature="EDDSA_SIG=="
        length="12345678"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
```

## 5. 검증 체크리스트

배포 전:

- [ ] `swift test` 657 통과
- [ ] `swiftlint --strict` 0 violations
- [ ] `scripts/release.sh --dry-run` 통과
- [ ] (실제 인증서) `spctl --assess --verbose=4 build/Maestro.app` 통과
- [ ] `xcrun stapler validate build/Maestro.app` 통과
- [ ] DMG 더블클릭 → Applications 드래그 → 첫 실행 시 GateKeeper 경고 없음

## 6. 알려진 한계 (Phase 21 vs 원안)

원안 task 21.3 (Xcode 프로젝트), 21.7~9 (Sparkle UI 통합 + EdDSA wiring), 21.11~12
(릴리즈 노트/버전 자동화) 는 별도 Phase 22+ 로 defer. Phase 21 은:

- ✅ 인증서 없는 환경에서도 dry-run 으로 파이프라인 검증
- ✅ UpdateChecker / AppCastParser 실제 코드 (UnitTest 21건)
- ✅ shell 스크립트 4개 (build / sign / dmg / release)
- ✅ release.yml 워크플로 (secrets 있을 때 활성)
- 🔜 실제 .dmg 산출은 사용자가 인증서 셋업 후 release tag push

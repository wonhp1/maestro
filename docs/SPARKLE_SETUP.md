# Sparkle 자동 업데이트 셋업 가이드

Phase 26 에서 Sparkle 통합 코드는 ship 됐지만, **자동 업데이트가 실제로 작동하려면
사용자(운영자)가 다음 셋업을 한 번 진행해야 함**.

## 1. EdDSA 서명 키 생성 (1회)

Sparkle 은 다운로드한 DMG 의 무결성을 검증하기 위해 EdDSA 서명을 사용. 키 페어
한 번 생성:

```bash
# Maestro 빌드 결과물 안에 generate_keys 도구 포함됨 (Sparkle 패키지)
./build/Maestro.app/Contents/Frameworks/Sparkle.framework/Versions/Current/Resources/generate_keys
```

출력:

```
A key has been generated and saved in your keychain. Add this private key to GitHub Secrets:
[private key base64]

This is your public key. Add it to your app's Info.plist:
[public key base64]
```

→ **public key** 복사 → 환경변수 `MAESTRO_SPARKLE_PUBLIC_KEY` 로 설정 (build-app.sh
가 Info.plist 의 `SUPublicEDKey` 에 박음).

→ **private key** 는 **macOS Keychain** 에 자동 저장됨 (`Sparkle EdDSA Key for ed25519`).
GitHub Actions 에서도 사용하려면 Keychain 에서 export:

```bash
security find-generic-password -ga "ed25519" -w
```

> ⚠️ **CRITICAL**: 위 명령 출력 (private key) 은 **절대 git commit / 채팅 / 이슈 / 스크린샷에
> 포함하지 마세요.** 노출되면 공격자가 위조 업데이트를 푸시할 수 있어요. GitHub Actions
> Secrets (`MAESTRO_SPARKLE_PRIVATE_KEY`) 또는 1Password 같은 secret manager 에만 저장.
> 노출 의심 시 즉시 새 키 페어 생성 + 모든 사용자 강제 마이그레이션 필요.

## 2. appcast.xml 호스팅

GitHub Pages 권장 (무료, HTTPS):

1. GitHub repo Settings → Pages → Source: `main` branch, `/docs` folder
2. `docs/appcast.xml` 파일 생성:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Maestro</title>
    <link>https://wonhp1.github.io/maestro/appcast.xml</link>
    <description>Maestro updates</description>
    <language>en</language>
    <!-- 새 릴리즈마다 item 추가 -->
  </channel>
</rss>
```

3. URL 확인: `https://wonhp1.github.io/maestro/appcast.xml`
4. Maestro 의 `MAESTRO_APPCAST_URL` 환경변수 = 위 URL (build-app.sh 가 Info.plist 에 박음).
   기본값도 위 URL.

## 3. 새 릴리즈마다 (예: v0.4.0)

1. **빌드 + 서명 + 노타리** (이미 PACKAGING.md 가이드):

   ```bash
   export MAESTRO_SIGN_IDENTITY="Developer ID Application: ..."
   export MAESTRO_NOTARY_PROFILE="maestro-notary"
   export MAESTRO_SPARKLE_PUBLIC_KEY="..."
   scripts/release.sh
   ```

2. **EdDSA 서명**:

   ```bash
   ./build/Maestro.app/Contents/Frameworks/Sparkle.framework/Versions/Current/Resources/sign_update \
     build/Maestro-0.4.0.dmg
   ```

   출력: `sparkle:edSignature="..." length="..."` — 다음 단계에서 사용.

3. **DMG 를 GitHub Releases 에 업로드**:

   ```bash
   gh release create v0.4.0 build/Maestro-0.4.0.dmg --notes "Phase 27 ..."
   ```

4. **`docs/appcast.xml` 에 entry 추가**:

   ```xml
   <item>
     <title>0.4.0</title>
     <sparkle:version>0.4.0</sparkle:version>
     <sparkle:releaseNotesLink>https://github.com/wonhp1/maestro/releases/tag/v0.4.0</sparkle:releaseNotesLink>
     <pubDate>Fri, 25 Apr 2026 18:00:00 +0000</pubDate>
     <enclosure
       url="https://github.com/wonhp1/maestro/releases/download/v0.4.0/Maestro-0.4.0.dmg"
       sparkle:edSignature="EdDSA-SIG-FROM-STEP-2"
       length="LENGTH-FROM-STEP-2"
       type="application/octet-stream" />
   </item>
   ```

5. `docs/appcast.xml` commit + push → GitHub Pages 자동 배포 → 기존 사용자가 다음 launch
   시 (또는 24h 주기로) 새 버전 자동 감지 → "업데이트 있습니다" modal → 사용자 승인 →
   다운로드 + 재시작.

## 4. CI 자동화 (선택)

GitHub Actions release.yml 에 다음 단계 추가:

```yaml
- name: EdDSA sign
  run: |
    SIG=$(./build/Maestro.app/Contents/Frameworks/Sparkle.framework/Versions/Current/Resources/sign_update build/Maestro-*.dmg)
    echo "SPARKLE_SIG=$SIG" >> $GITHUB_ENV

- name: Update appcast.xml
  run: |
    # python script: parse SIG / length / version → docs/appcast.xml 에 prepend
```

GitHub Secrets 추가:

- `MAESTRO_SPARKLE_PUBLIC_KEY` (Info.plist 용)
- `MAESTRO_SPARKLE_PRIVATE_KEY` (sign_update Keychain import 용)

## 5. 사용자 경험

위 셋업 완료 후 Maestro 사용자 (DMG 설치자) 의 경험:

1. 첫 실행 시 Sparkle 이 24h 후 백그라운드 자동 체크 시작
2. 새 버전 발견 → modal 알림 ("Maestro 0.4.0 가 출시되었습니다. 업데이트 하시겠어요?")
3. "업데이트" 클릭 → 자동 다운로드 + EdDSA 검증 + 자동 재시작 → 새 버전
4. 또는 메뉴: Maestro → 업데이트 확인… → 강제 체크

## 6. 한계 / Known Issues

- **Sandbox 미지원**: Sparkle 은 자체 install daemon 사용 — Maestro 는 Sandbox 활성 X
  (현재 Info.plist 에 entitlements 없음). Sandbox 활성 시 Sparkle 의 SPUDownloader XPC
  service 추가 셋업 필요
- **첫 사용자 데이터**: 0.1.0 / 0.2.0 사용자는 Sparkle public key 가 없는 빌드라
  자동 업데이트 X. 수동으로 0.3.0 DMG 받아 한 번 교체해야 함 (이후로는 자동)
- **EdDSA private key 분실**: 생성된 key 잃으면 키 페어 재생성 필요 → 모든 기존 사용자
  새 public key 가진 빌드로 강제 마이그레이션

## 7. 참고 자료

- Sparkle 공식: https://sparkle-project.org/documentation/
- EdDSA 가이드: https://sparkle-project.org/documentation/#3-segue-for-security-conscious-developers
- appcast format: https://sparkle-project.org/documentation/publishing/

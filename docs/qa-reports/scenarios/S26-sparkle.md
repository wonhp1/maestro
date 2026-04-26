# S26: Sparkle 자동 업데이트 체크 (launch-time)

**상태**: ❌ FAIL (build-config 이슈, 코드 동작은 정상)
**실행**: 2026-04-26 02:15 KST

## Action

Maestro cold launch (open_application).

## Observe

- 1초 내 alert 표시: "Unable to Check For Updates — The updater failed to start. Please verify you have the latest version of Maestro and contact the app developer if the issue still persists. Check the Console logs for more information."
- OSLog (com.gimgyeongwon.maestro.. 또는 Sparkle subsystem):
  ```
  [org.sparkle-project.Sparkle:Sparkle] The provided EdDSA key could not be decoded.
  [org.sparkle-project.Sparkle:Sparkle] Fatal updater error (1): The EdDSA public key is not valid for Maestro.
  ```

## 진단

`docs/SPARKLE_SETUP.md` 가 명시한 셋업 미완:

- 환경변수 `MAESTRO_SPARKLE_PUBLIC_KEY` 가 build 시 미설정 → `Info.plist` 의 `SUPublicEDKey` 가 placeholder 또는 invalid.

코드 결함이 아니라 **운영 환경 셋업 누락**.

## Fix 옵션

1. **단기**: build-app.sh 가 `SUPublicEDKey` 미설정 시 Sparkle 자체 비활성 (Info.plist 에 키 누락) → updater 메뉴/체크 disable, alert 안 뜸.
2. **중기**: 실제 EdDSA 키 페어 생성 + GitHub Pages 에 appcast.xml 호스팅 (docs/SPARKLE_SETUP.md 셋업 따라).

→ **§ Active Issue I-02** 생성. 단기 fix (옵션 1) 가 사용자 경험 우선.

## Verdict

❌ **FAIL** for end-user experience. 코드 자체는 OK.

## Action plan

v0.4.7+: build-app.sh 에서 `MAESTRO_SPARKLE_PUBLIC_KEY` 미설정 시 SUPublicEDKey / SUFeedURL 둘 다 omit → Sparkle 가 graceful 하게 update 기능 자체 미노출.

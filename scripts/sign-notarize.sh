#!/usr/bin/env bash
# sign-notarize.sh — codesign + notarize Maestro.app.
#
# Usage:
#   scripts/sign-notarize.sh [--dry-run]
#
# 필요한 환경변수:
#   MAESTRO_SIGN_IDENTITY        codesign 인증서 이름 ("Developer ID Application: NAME (TEAM)")
#   MAESTRO_NOTARY_PROFILE       `xcrun notarytool store-credentials` 로 저장한 키체인 프로필 이름
#
# 동작:
#   1. codesign --force --options runtime --timestamp --sign "$IDENTITY" Maestro.app
#   2. ditto -c -k --keepParent Maestro.app Maestro.app.zip
#   3. xcrun notarytool submit Maestro.app.zip --keychain-profile "$PROFILE" --wait
#   4. xcrun stapler staple Maestro.app
#   5. spctl --assess --verbose Maestro.app  (검증)
#
# 환경변수가 없으면 dry-run 으로 강제 — 인증서 없는 환경 (CI 첫 setup) 에서 안전.

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then DRY_RUN=true; fi

cd "$(dirname "$0")/.."
APP_BUNDLE="build/Maestro.app"

if [[ ! -d "$APP_BUNDLE" && "$DRY_RUN" != "true" ]]; then
    echo "오류: $APP_BUNDLE 가 없음. 먼저 scripts/build-app.sh 실행"
    exit 1
fi

if [[ -z "${MAESTRO_SIGN_IDENTITY:-}" || -z "${MAESTRO_NOTARY_PROFILE:-}" ]]; then
    echo "==> MAESTRO_SIGN_IDENTITY 또는 MAESTRO_NOTARY_PROFILE 미설정 — dry-run 모드"
    DRY_RUN=true
fi

if $DRY_RUN; then
    echo "[dry-run] codesign --force --options runtime --timestamp \\"
    echo "          --sign \"\$MAESTRO_SIGN_IDENTITY\" $APP_BUNDLE"
    echo "[dry-run] ditto -c -k --keepParent $APP_BUNDLE $APP_BUNDLE.zip"
    echo "[dry-run] xcrun notarytool submit $APP_BUNDLE.zip \\"
    echo "          --keychain-profile \"\$MAESTRO_NOTARY_PROFILE\" --wait"
    echo "[dry-run] xcrun stapler staple $APP_BUNDLE"
    echo "[dry-run] spctl --assess --verbose $APP_BUNDLE"
    exit 0
fi

echo "==> codesign nested frameworks (Sparkle, etc.)"
# Phase 26: nested .framework / XPC / Updater.app 를 먼저 서명
find "$APP_BUNDLE/Contents/Frameworks" -type d \( -name "*.framework" -o -name "*.app" -o -name "*.xpc" \) 2>/dev/null | sort -r | while read -r nested; do
    codesign --force --options runtime --timestamp \
        --sign "$MAESTRO_SIGN_IDENTITY" "$nested" 2>&1 | head -1
done

echo "==> codesign $APP_BUNDLE"
codesign --force --options runtime --timestamp \
    --sign "$MAESTRO_SIGN_IDENTITY" "$APP_BUNDLE"

echo "==> notarize submission"
ZIP="${APP_BUNDLE}.zip"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP"
xcrun notarytool submit "$ZIP" \
    --keychain-profile "$MAESTRO_NOTARY_PROFILE" --wait
rm -f "$ZIP"

echo "==> staple"
xcrun stapler staple "$APP_BUNDLE"

echo "==> Gatekeeper 검증"
spctl --assess --verbose=4 "$APP_BUNDLE"

echo "==> 서명 + 노타리 완료"

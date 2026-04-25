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

echo "==> codesign nested executables + bundles (Sparkle Autoupdate / Updater.app / XPC)"
# Phase 26: Sparkle.framework 안의 raw binary (Autoupdate) + nested .app / .xpc 모두 서명.
# 가장 안쪽부터 sort -r (depth desc) 으로 처리 — outer framework 가 마지막.
SPARKLE_DIR="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_DIR" ]]; then
    # Autoupdate raw binary
    if [[ -f "$SPARKLE_DIR/Versions/B/Autoupdate" ]]; then
        codesign --force --options runtime --timestamp \
            --sign "$MAESTRO_SIGN_IDENTITY" "$SPARKLE_DIR/Versions/B/Autoupdate" 2>&1 | head -1
    fi
    # XPC services
    for xpc in "$SPARKLE_DIR/Versions/B/XPCServices/"*.xpc; do
        [[ -d "$xpc" ]] || continue
        codesign --force --options runtime --timestamp \
            --sign "$MAESTRO_SIGN_IDENTITY" "$xpc" 2>&1 | head -1
    done
    # Updater.app
    if [[ -d "$SPARKLE_DIR/Versions/B/Updater.app" ]]; then
        codesign --force --options runtime --timestamp \
            --sign "$MAESTRO_SIGN_IDENTITY" "$SPARKLE_DIR/Versions/B/Updater.app" 2>&1 | head -1
    fi
    # outer framework
    codesign --force --options runtime --timestamp \
        --sign "$MAESTRO_SIGN_IDENTITY" "$SPARKLE_DIR" 2>&1 | head -1
fi

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

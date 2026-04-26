#!/usr/bin/env bash
# build-app.sh — Maestro.app 번들 빌드 (release configuration).
#
# Usage:
#   scripts/build-app.sh [--dry-run]
#
# 산출물: build/Maestro.app
#
# 동작:
#   1. swift build -c release
#   2. .build/release/Maestro 실행파일 + Info.plist 등을 .app 번들 구조로 복사
#   3. 코드 서명은 sign-notarize.sh 가 책임 (이 스크립트는 unsigned bundle 만)
#
# Phase 21 의 SwiftPM-only 시점 — Xcode 프로젝트 도입 전까지는 수동 번들링.

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then DRY_RUN=true; fi

cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
APP_BUNDLE="${BUILD_DIR}/Maestro.app"
APP_NAME="Maestro"
BUNDLE_ID="com.gimgyeongwon.maestro"
APP_VERSION="$(grep 'static let appVersion' Sources/MaestroCore/MaestroConfig.swift \
    | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
[[ -z "$APP_VERSION" ]] && { echo "appVersion 파싱 실패"; exit 1; }

echo "==> Maestro $APP_VERSION 빌드"

if $DRY_RUN; then
    echo "[dry-run] swift build -c release"
    echo "[dry-run] mkdir -p $APP_BUNDLE/Contents/MacOS $APP_BUNDLE/Contents/Resources"
    echo "[dry-run] cp .build/release/Maestro $APP_BUNDLE/Contents/MacOS/"
    echo "[dry-run] write Info.plist (bundleId=$BUNDLE_ID, version=$APP_VERSION)"
    exit 0
fi

# 1. SwiftPM release 빌드
swift build -c release

# 2. 번들 구조
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp ".build/release/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# 2b. 앱 아이콘 (Phase 25)
if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# 3. Info.plist
# I-02 fix: MAESTRO_SPARKLE_PUBLIC_KEY 가 비어있으면 SUPublicEDKey / SUFeedURL /
# SUEnableAutomaticChecks 를 통째로 omit. Sparkle 이 placeholder 로 launch-time
# alert "Unable to Check For Updates" 띄우는 것 방지. CI release build 가 환경 변수
# 주입하면 정상 자동 업데이트 활성화.
SPARKLE_KEY="${MAESTRO_SPARKLE_PUBLIC_KEY:-}"
SPARKLE_BLOCK=""
if [[ -n "$SPARKLE_KEY" ]]; then
    SPARKLE_FEED="${MAESTRO_APPCAST_URL:-https://wonhp1.github.io/maestro/appcast.xml}"
    SPARKLE_BLOCK=$'    <key>SUFeedURL</key><string>'"$SPARKLE_FEED"$'</string>\n    <key>SUPublicEDKey</key><string>'"$SPARKLE_KEY"$'</string>\n    <key>SUEnableAutomaticChecks</key><true/>\n    <key>SUScheduledCheckInterval</key><integer>86400</integer>\n'
fi
cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleVersion</key><string>${APP_VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${APP_VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleSignature</key><string>????</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSUserNotificationAlertStyle</key><string>alert</string>
${SPARKLE_BLOCK}</dict>
</plist>
EOF

# 4. Sparkle.framework 번들 — SwiftPM 가 .build/release 에 위치시킴.
SPARKLE_FW=$(find .build -type d -name "Sparkle.framework" 2>/dev/null | head -1)
if [[ -n "$SPARKLE_FW" ]]; then
    mkdir -p "${APP_BUNDLE}/Contents/Frameworks"
    cp -R "$SPARKLE_FW" "${APP_BUNDLE}/Contents/Frameworks/"
    echo "==> Sparkle.framework 번들 추가"

    # 5. SwiftPM 빌드 executable 에는 @executable_path/../Frameworks rpath 가 없음 →
    #    Sparkle.framework 가 dyld 검색 경로에 안 잡혀 launch crash (v0.4.0 fix).
    EXEC_PATH="${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXEC_PATH" 2>/dev/null || true
    echo "==> @executable_path/../Frameworks rpath 추가"
fi

echo "==> $APP_BUNDLE 생성 완료"
echo "다음 단계: scripts/sign-notarize.sh"

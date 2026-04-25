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
</dict>
</plist>
EOF

echo "==> $APP_BUNDLE 생성 완료"
echo "다음 단계: scripts/sign-notarize.sh"

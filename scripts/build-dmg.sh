#!/usr/bin/env bash
# build-dmg.sh — Maestro.app 을 .dmg 로 패키징.
#
# Usage:
#   scripts/build-dmg.sh [--dry-run]
#
# 의존: create-dmg (https://github.com/create-dmg/create-dmg) — `brew install create-dmg`
#
# 산출물: build/Maestro-<version>.dmg

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then DRY_RUN=true; fi

cd "$(dirname "$0")/.."
APP_BUNDLE="build/Maestro.app"
APP_VERSION="$(grep 'static let appVersion' Sources/MaestroCore/MaestroConfig.swift \
    | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
DMG_PATH="build/Maestro-${APP_VERSION}.dmg"

if [[ ! -d "$APP_BUNDLE" && "$DRY_RUN" != "true" ]]; then
    echo "오류: $APP_BUNDLE 없음. scripts/build-app.sh 먼저 실행"
    exit 1
fi

if $DRY_RUN; then
    echo "[dry-run] create-dmg --volname \"Maestro $APP_VERSION\" \\"
    echo "          --window-size 600 400 --icon-size 100 \\"
    echo "          --app-drop-link 450 200 \\"
    echo "          $DMG_PATH $APP_BUNDLE"
    exit 0
fi

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "오류: create-dmg 미설치 — brew install create-dmg"
    exit 1
fi

rm -f "$DMG_PATH"

create-dmg \
    --volname "Maestro $APP_VERSION" \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "Maestro.app" 175 200 \
    --app-drop-link 425 200 \
    --hide-extension "Maestro.app" \
    "$DMG_PATH" \
    "$APP_BUNDLE"

echo "==> $DMG_PATH 생성 완료"

#!/usr/bin/env bash
# release.sh — full pipeline: build + sign + notarize + DMG.
#
# Usage:
#   scripts/release.sh [--dry-run]
#
# 환경변수:
#   MAESTRO_SIGN_IDENTITY    (codesign 인증서)
#   MAESTRO_NOTARY_PROFILE   (notarytool 키체인 프로필)
#   변수 미설정 → sign-notarize.sh 가 dry-run.

set -euo pipefail

cd "$(dirname "$0")/.."

MODE_FLAG="${1:-}"

scripts/build-app.sh "$MODE_FLAG"
scripts/sign-notarize.sh "$MODE_FLAG"
scripts/build-dmg.sh "$MODE_FLAG"

echo "==> release pipeline 완료"

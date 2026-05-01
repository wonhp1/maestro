#!/usr/bin/env bash
# v0.11.1 — Sparkle appcast.xml 자동 갱신.
#
# Usage:
#   ./scripts/update-appcast.sh <version> <dmg-path>
#
# 환경변수:
#   MAESTRO_SPARKLE_PRIVATE_KEY  EdDSA private key (sign_update -s 입력)
#   GITHUB_REPO                  e.g. "wonhp1/maestro" (release URL 생성용)
#
# 동작:
#   1. sign_update 로 DMG 의 EdDSA 서명 + 길이 추출
#   2. docs/appcast.xml 의 </channel> 직전에 새 <item> 삽입
#   3. (commit / push 는 호출자 책임)

set -euo pipefail

VERSION="${1:?version required}"
DMG_PATH="${2:?dmg path required}"
APPCAST="docs/appcast.xml"
REPO="${GITHUB_REPO:-wonhp1/maestro}"
SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"

if [ ! -x "$SIGN_UPDATE" ]; then
    echo "❌ sign_update 미발견 — Sparkle SwiftPM artifact 가 없음. swift build 먼저." >&2
    exit 2
fi

if [ -z "${MAESTRO_SPARKLE_PRIVATE_KEY:-}" ]; then
    echo "⚠️  MAESTRO_SPARKLE_PRIVATE_KEY 미설정 — appcast 갱신 skip." >&2
    exit 0
fi

# sign_update 는 v2 부터 --ed-key-file 만 허용 (-s 은 deprecated → ERROR).
# 환경변수 → 임시 파일 → 즉시 삭제.
KEY_FILE=$(mktemp)
trap 'rm -f "$KEY_FILE"' EXIT
printf '%s' "$MAESTRO_SPARKLE_PRIVATE_KEY" > "$KEY_FILE"
chmod 600 "$KEY_FILE"

SIGN_OUTPUT=$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$DMG_PATH")
echo "sign_update output: $SIGN_OUTPUT"

# 파싱
EDSIG=$(echo "$SIGN_OUTPUT" | grep -oE 'sparkle:edSignature="[^"]+"' | sed 's/sparkle:edSignature="//;s/"$//')
LENGTH=$(echo "$SIGN_OUTPUT" | grep -oE 'length="[0-9]+"' | sed 's/length="//;s/"$//')
if [ -z "$EDSIG" ] || [ -z "$LENGTH" ]; then
    echo "❌ sign_update 출력 파싱 실패: $SIGN_OUTPUT" >&2
    exit 3
fi

PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
DMG_BASENAME=$(basename "$DMG_PATH")
DMG_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${DMG_BASENAME}"

# CHANGELOG 에서 해당 버전 항목 추출 (없으면 generic 메시지)
RELEASE_NOTES=""
if [ -f CHANGELOG.md ]; then
    # awk 로 ## [버전] 부터 다음 ## 까지 추출
    NOTES=$(awk -v ver="$VERSION" '
        $0 ~ "^## \\[" ver "\\]" { capture=1; next }
        capture && /^## \[/ { exit }
        capture { print }
    ' CHANGELOG.md | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    if [ -n "$NOTES" ]; then
        RELEASE_NOTES="<![CDATA[<pre>${NOTES}</pre>]]>"
    fi
fi
[ -z "$RELEASE_NOTES" ] && RELEASE_NOTES="Maestro v${VERSION} 업데이트."

# 새 <item> 블록
NEW_ITEM=$(cat <<EOF
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description>${RELEASE_NOTES}</description>
      <enclosure
        url="${DMG_URL}"
        sparkle:version="${VERSION}"
        sparkle:shortVersionString="${VERSION}"
        length="${LENGTH}"
        type="application/octet-stream"
        sparkle:edSignature="${EDSIG}" />
    </item>
EOF
)

# </channel> 직전 삽입 — 최신 entry 가 위에.
# Python 으로 안전하게 처리 (sed 의 multiline 처리 까다로움).
python3 - "$APPCAST" "$NEW_ITEM" "$VERSION" <<'PYEOF'
import sys, re
path, new_item, version = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding='utf-8') as f:
    content = f.read()

# 이미 같은 버전 entry 가 있으면 skip (멱등성)
if f'<sparkle:version>{version}</sparkle:version>' in content:
    print(f'⚠️  v{version} 은 이미 appcast 에 있음 — skip', file=sys.stderr)
    sys.exit(0)

# </channel> 직전에 삽입 — 위쪽 (최신) 위치를 위해 첫 <item> 또는 </channel> 직전
# 정책: 첫 <item> 직전이 우선 (최신 위), 없으면 </channel> 직전.
if '<item>' in content:
    new_content = content.replace('<item>', new_item.strip() + '\n    <item>', 1)
else:
    new_content = content.replace('</channel>', f'{new_item}\n  </channel>', 1)

with open(path, 'w', encoding='utf-8') as f:
    f.write(new_content)
print(f'✅ v{version} entry 추가됨')
PYEOF

echo "✅ docs/appcast.xml 갱신 완료 (v${VERSION})"

# S13: PATH augmentation (Finder cold launch)

**상태**: ✅ PASS
**실행**: 2026-04-26 02:15 KST
**대상**: Maestro 0.4.6, /Applications/Maestro.app, Finder cold launch

## Setup

- `~/Library/Application Support/Maestro` 백업 후 비움
- `~/Library/Logs/Maestro/path-augment.log` 삭제
- App quit (pkill -9 Maestro)
- `open -a Maestro` (open_application — Finder/launchd 동등)

## Action

1. open_application "Maestro"
2. 3초 대기 후 screenshot

## Observe

**path-augment.log**:

```
=== 2026-04-25 17:15:50 +0000 ===
result: augmented: +11 entries
HOME: ~
SHELL env: /bin/zsh
PATH after augment:
  /usr/bin /bin /usr/sbin /sbin
  ~/.bun/bin
  ~/.antigravity/antigravity/bin
  ~/.npm-global/bin     ← claude 위치
  ~/bin
  /Library/Frameworks/Python.framework/Versions/3.14/bin
  /opt/homebrew/bin /opt/homebrew/sbin /usr/local/bin
  /Library/Apple/usr/bin
  ...
```

**Onboarding step 2** ("에이전트 감지"): "감지됨: ✓ claude" — adapter detection
이 PATH 변경 후 정상 동작.

## Verdict

✅ **PASS** — `-ilc` fix (v0.4.4) 가 .app launch 컨텍스트에서 제대로 동작.
v0.4.3 의 미해결 + augmentation 안 됨 문제 완전 해결.

## Evidence

- log: 첫 두 라인 (augmented +11)
- screenshot: 두 번째 step 의 "✓ claude" 텍스트

## Regression hooks

- `Tests/MaestroCoreTests/EnvironmentAugmenterSyncTests.swift` (3 tests)
- `Tests/MaestroCoreTests/LoginShellPathExtractorTests.swift` (testExtractInvokesShellWithLoginInteractiveArgs — `-ilc` 인자 contract)

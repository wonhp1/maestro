# S14 — 친절 에러 (AdapterError 한국어 + 설치 안내)

**상태**: ✅ PASS
**검증 방식**: Source review
**대상**: `Sources/MaestroCore/AgentAdapter.swift`

---

## AdapterError enum

`AgentAdapter.swift:101-147` — `LocalizedError` 채택, 모든 case 한국어 메시지.

```
case notInstalled(adapterId: String)
case sessionCreationFailed(reason: String)
case unknownSession(id: SessionID)
case processFailed(exitCode: Int32, stderr: String)
case unsupported(operation: String)
```

문서 주석 (`AgentAdapter.swift:113-114`) 명시:

> 사용자에게 친화적인 한국어 메시지. 에러 case 이름 (".AdapterError error 0") 대신 "claude CLI 가 설치되어 있지 않아요…" 처럼 구체적 안내.

## errorDescription 매핑 (`:115-129`)

| Case                     | 메시지                                                                                                        |
| ------------------------ | ------------------------------------------------------------------------------------------------------------- |
| `.notInstalled(claude)`  | `Claude Code CLI 를 찾지 못했어요.\n터미널에서 \`npm install -g @anthropic-ai/claude-code\` 로 설치해주세요.` |
| `.notInstalled(aider)`   | `Aider CLI 를 찾지 못했어요.\n터미널에서 \`pip install aider-chat\` 로 설치해주세요.`                         |
| `.notInstalled(other)`   | `어댑터 \(adapterId) 의 CLI 를 PATH 에서 찾지 못했어요.`                                                      |
| `.sessionCreationFailed` | `세션 생성 실패: \(reason)`                                                                                   |
| `.unknownSession`        | `알 수 없는 세션: \(id)`                                                                                      |
| `.processFailed`         | `에이전트 프로세스 실패 (exit \(exitCode)): \(trimmed-stderr)`                                                |
| `.unsupported`           | `이 어댑터는 \(operation) 동작을 지원하지 않아요.`                                                            |

## notInstalledMessage 분기 (`:131-146`)

vendor-specific 설치 안내 명시 — claude/aider 둘 다 정확한 패키지 매니저 명령 포함. fallback 메시지도 한국어.

---

## Verdict

- ✅ AdapterError 모든 case 한국어 메시지 보유
- ✅ `.notInstalled` 에 vendor 별 설치 명령 (npm / pip) 동봉
- ✅ `LocalizedError` 채택으로 SwiftUI/NSAlert 가 자동으로 `errorDescription` 사용 가능

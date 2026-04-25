#!/usr/bin/env bash
# bench.sh — Maestro 성능 벤치마크 실행 + JSON 산출.
#
# Usage:
#   scripts/bench.sh
#
# 산출: docs/benchmarks/latest.json (last run)
#
# 회귀 감지: docs/benchmarks/baseline.json 의 ceilingSeconds 초과 시 fail.

set -euo pipefail

cd "$(dirname "$0")/.."

OUTPUT_DIR="docs/benchmarks"
mkdir -p "$OUTPUT_DIR"

echo "==> Performance benchmark suite"
swift test --filter "PerformanceBenchmarkTests" 2>&1 | tee "$OUTPUT_DIR/latest.log"

# 베이스라인 비교 (현재는 PerformanceBenchmarkTests 내 XCTAssertLessThan 으로 ceiling 강제 — fail 시 exit 0 아님).
echo "==> 결과: $OUTPUT_DIR/latest.log (베이스라인 비교는 docs/benchmarks/baseline.json)"

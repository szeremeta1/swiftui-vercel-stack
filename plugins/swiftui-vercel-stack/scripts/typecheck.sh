#!/usr/bin/env bash
# /typecheck — run TypeScript type-check (`tsc --noEmit`) for the project
# containing $PWD, surfacing only "error TS####" lines.
#
# Walks up from $PWD to find a tsconfig.json. Prefers the project's local
# TypeScript via `npx --no-install tsc`; falls back to global `tsc` if
# available; reports a friendly error if neither is reachable.
#
# Exit codes:
#   0 — no type errors (or no tsconfig.json found / silent skip)
#   2 — type errors found; stderr lists them

set -uo pipefail

START_DIR="${1:-$PWD}"

find_tsconfig_root() {
  local dir="$1"
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if [[ -f "$dir/tsconfig.json" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

PROJECT_ROOT="$(find_tsconfig_root "$START_DIR" || true)"
if [[ -z "$PROJECT_ROOT" ]]; then
  echo "swiftui-vercel-stack: no tsconfig.json found at or above $START_DIR" >&2
  exit 0
fi

# Prefer project-local tsc to avoid version drift.
TSC_CMD=()
if [[ -x "$PROJECT_ROOT/node_modules/.bin/tsc" ]]; then
  TSC_CMD=( "$PROJECT_ROOT/node_modules/.bin/tsc" )
elif command -v npx > /dev/null 2>&1; then
  TSC_CMD=( npx --no-install tsc )
elif command -v tsc > /dev/null 2>&1; then
  TSC_CMD=( tsc )
else
  echo "swiftui-vercel-stack: no tsc found. Install TypeScript via 'npm i -D typescript' in $PROJECT_ROOT." >&2
  exit 0
fi

LOG="$(mktemp -t typecheck.XXXXXX)"
trap 'rm -f "$LOG"' EXIT

(
  cd "$PROJECT_ROOT" || exit 1
  "${TSC_CMD[@]}" --noEmit --pretty false
) >"$LOG" 2>&1
STATUS=$?

if [[ $STATUS -eq 0 ]]; then
  echo "swiftui-vercel-stack: tsc --noEmit passed in $PROJECT_ROOT"
  exit 0
fi

# Filter to actual TS error lines: "path/to/file.ts(12,34): error TS2345: ..."
ERRORS="$(grep -E ': error TS[0-9]+:' "$LOG" || true)"
if [[ -z "$ERRORS" ]]; then
  ERRORS="$(tail -n 30 "$LOG")"
fi

LINE_COUNT="$(printf '%s\n' "$ERRORS" | wc -l | tr -d ' ')"
if (( LINE_COUNT > 60 )); then
  TRUNCATED="$(printf '%s\n' "$ERRORS" | head -n 40)"
  EXTRA=$(( LINE_COUNT - 40 ))
  ERRORS="$TRUNCATED

… $EXTRA more errors. Run /typecheck after fixing the first batch."
fi

{
  echo "swiftui-vercel-stack: tsc --noEmit FAILED in $PROJECT_ROOT"
  echo "---"
  printf '%s\n' "$ERRORS"
} >&2

exit 2

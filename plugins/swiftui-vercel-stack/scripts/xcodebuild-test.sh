#!/usr/bin/env bash
# /xct — run xcodebuild test for the SwiftUI project containing $PWD,
# surfacing only failing tests and assertion messages.
#
# Designed to be invoked as a slash command (no stdin). Walks up from $PWD
# to find an .xcodeproj or .xcworkspace, picks the scheme, picks a
# destination (config > auto-detect first available iPhone Simulator >
# fallback "iPhone 16"), runs `xcodebuild test`, and filters output.
#
# Exit codes:
#   0 — all tests passed (or no tests found / silent skip)
#   2 — at least one test failed; stderr lists the failures

set -uo pipefail

START_DIR="${1:-$PWD}"

# --- Walk up to find an .xcodeproj or .xcworkspace ----------------------------
find_project_root() {
  local dir="$1"
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if compgen -G "$dir/*.xcworkspace" > /dev/null 2>&1 \
      || compgen -G "$dir/*.xcodeproj" > /dev/null 2>&1; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

PROJECT_ROOT="$(find_project_root "$START_DIR" || true)"
if [[ -z "$PROJECT_ROOT" ]]; then
  echo "swiftui-vercel-stack: no .xcodeproj or .xcworkspace found at or above $START_DIR" >&2
  exit 0
fi

# --- Resolve scheme + destination ---------------------------------------------
SCHEME=""
CONFIGURATION="Debug"
DESTINATION=""

CONFIG_FILE="$PROJECT_ROOT/.swiftui-vercel-stack.json"
if [[ -f "$CONFIG_FILE" ]]; then
  read -r SCHEME CONFIGURATION DESTINATION < <(python3 -c "
import json
try:
    c = json.load(open('$CONFIG_FILE'))
except Exception:
    c = {}
print(c.get('scheme',''), c.get('configuration','Debug'), c.get('destination',''))
" 2>/dev/null)
fi

if [[ -z "$SCHEME" ]]; then
  XCODEPROJ="$(ls -d "$PROJECT_ROOT"/*.xcodeproj 2>/dev/null | head -n1)"
  [[ -n "$XCODEPROJ" ]] && SCHEME="$(basename "$XCODEPROJ" .xcodeproj)"
fi

if [[ -z "$SCHEME" ]]; then
  echo "swiftui-vercel-stack: no scheme inferred for $PROJECT_ROOT" >&2
  exit 0
fi

# Pick a destination if config didn't provide one.
if [[ -z "$DESTINATION" ]]; then
  # Prefer iPhone 16 if available; otherwise grab any booted/available iPhone.
  if command -v xcrun > /dev/null 2>&1; then
    UDID="$(xcrun simctl list devices available 2>/dev/null \
      | grep -E 'iPhone' \
      | grep -oE '\([0-9A-F-]{36}\)' \
      | head -n1 \
      | tr -d '()')"
    if [[ -n "$UDID" ]]; then
      DESTINATION="id=$UDID"
    else
      DESTINATION="platform=iOS Simulator,name=iPhone 16"
    fi
  else
    DESTINATION="platform=iOS Simulator,name=iPhone 16"
  fi
fi

# --- Run xcodebuild test ------------------------------------------------------
LOG="$(mktemp -t xct.XXXXXX)"
trap 'rm -f "$LOG"' EXIT

(
  cd "$PROJECT_ROOT" || exit 1
  xcodebuild test \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -quiet
) >"$LOG" 2>&1
STATUS=$?

# --- Distill failures ---------------------------------------------------------
# Test failure lines look like:
#   /path/Foo.swift:42: error: -[FooTests testBar] : XCTAssertEqual failed: ...
#   Test Case '-[FooTests.FooTests testBar]' failed (0.123 seconds).
FAILURES="$(grep -E '(^.*\.swift:[0-9]+: error:|Test Case .* failed|XCTAssert.* failed|error: .* failed: caught error)' "$LOG" || true)"

if [[ $STATUS -eq 0 && -z "$FAILURES" ]]; then
  # All green. Print a one-line confirmation (slash commands benefit from a
  # visible "yes it ran" signal more than hooks do).
  PASS_COUNT="$(grep -cE '^Test Case .* passed' "$LOG" 2>/dev/null || echo 0)"
  echo "swiftui-vercel-stack: xcodebuild test passed for scheme '$SCHEME' (${PASS_COUNT} test cases)."
  exit 0
fi

# Cap output at 80 lines (tests can have lots of failures).
LINE_COUNT="$(printf '%s\n' "$FAILURES" | wc -l | tr -d ' ')"
if (( LINE_COUNT > 80 )); then
  TRUNCATED="$(printf '%s\n' "$FAILURES" | head -n 50)"
  EXTRA=$(( LINE_COUNT - 50 ))
  FAILURES="$TRUNCATED

… $EXTRA more failure lines. Full log at $LOG (preserved this run only)."
  trap - EXIT  # don't auto-delete the log if we're pointing the user at it
fi

if [[ -z "$FAILURES" ]]; then
  # Test command failed but no recognizable failure markers (e.g. simulator
  # boot error, scheme misconfig) — show the tail.
  FAILURES="$(tail -n 30 "$LOG")"
fi

{
  echo "swiftui-vercel-stack: xcodebuild test FAILED for scheme '$SCHEME' in $PROJECT_ROOT"
  echo "destination: $DESTINATION"
  echo "---"
  printf '%s\n' "$FAILURES"
} >&2

exit 2

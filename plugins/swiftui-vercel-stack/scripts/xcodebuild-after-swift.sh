#!/usr/bin/env bash
# PostToolUse hook: after a Swift file is edited, run xcodebuild and surface
# only the errors/warnings to Claude. Silent on success.
#
# Stdin (JSON): {"tool_name": ..., "tool_input": {"file_path": ...}, "cwd": ...}
# Exit codes:
#   0 — success (build clean, or hook deliberately skipped)
#   2 — build failed; stderr contains the distilled errors (Claude reads stderr)

set -uo pipefail

# --- Read stdin (hook mode) or fall back to PWD (manual /xcb mode) ------------
# When invoked as a hook, stdin contains JSON with tool_input.file_path.
# When invoked manually (e.g. via /xcb), there is no stdin; we use $PWD.
FILE_PATH=""
if [[ ! -t 0 ]]; then
  STDIN="$(cat)"
  if [[ -n "$STDIN" ]]; then
    FILE_PATH="$(printf '%s' "$STDIN" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('file_path', '') or '')
except Exception:
    pass
" 2>/dev/null)"
  fi
fi

# Manual mode: search from PWD instead of from a specific file's directory.
if [[ -z "$FILE_PATH" ]]; then
  FILE_PATH="$PWD/.manual-trigger"
else
  # Defense in depth: the `if` filter should already gate on .swift, but verify.
  case "$FILE_PATH" in
    *.swift) ;;
    *) exit 0 ;;
  esac
fi

# --- Walk up to find an .xcodeproj or .xcworkspace ----------------------------
find_project_root() {
  local dir
  dir="$(dirname "$1")"
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if compgen -G "$dir/*.xcworkspace" > /dev/null 2>&1; then
      printf '%s\n' "$dir"
      return 0
    fi
    if compgen -G "$dir/*.xcodeproj" > /dev/null 2>&1; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

PROJECT_ROOT="$(find_project_root "$FILE_PATH" || true)"
if [[ -z "$PROJECT_ROOT" ]]; then
  # No Xcode project anywhere above this file. Silently skip — not every Swift
  # file lives in an Xcode project (e.g. SwiftPM packages).
  exit 0
fi

# --- Resolve scheme ------------------------------------------------------------
# Priority: per-project config > .xcodeproj basename
SCHEME=""
CONFIGURATION="Debug"
DESTINATION=""

CONFIG_FILE="$PROJECT_ROOT/.swiftui-vercel-stack.json"
if [[ -f "$CONFIG_FILE" ]]; then
  SCHEME="$(python3 -c "import json,sys
try:
  c=json.load(open('$CONFIG_FILE'))
  print(c.get('scheme',''))
except: pass" 2>/dev/null)"
  CFG_CONFIG="$(python3 -c "import json,sys
try:
  c=json.load(open('$CONFIG_FILE'))
  print(c.get('configuration',''))
except: pass" 2>/dev/null)"
  CFG_DEST="$(python3 -c "import json,sys
try:
  c=json.load(open('$CONFIG_FILE'))
  print(c.get('destination',''))
except: pass" 2>/dev/null)"
  [[ -n "$CFG_CONFIG" ]] && CONFIGURATION="$CFG_CONFIG"
  [[ -n "$CFG_DEST" ]] && DESTINATION="$CFG_DEST"
fi

if [[ -z "$SCHEME" ]]; then
  XCODEPROJ="$(ls -d "$PROJECT_ROOT"/*.xcodeproj 2>/dev/null | head -n1)"
  if [[ -n "$XCODEPROJ" ]]; then
    SCHEME="$(basename "$XCODEPROJ" .xcodeproj)"
  fi
fi

if [[ -z "$SCHEME" ]]; then
  echo "swiftui-vercel-stack: no scheme inferred; create $CONFIG_FILE with {\"scheme\":\"YourScheme\"}" >&2
  exit 0  # Don't block — just inform.
fi

# --- Run xcodebuild ------------------------------------------------------------
LOG="$(mktemp -t xcb.XXXXXX)"
trap 'rm -f "$LOG"' EXIT

XCB_ARGS=( -scheme "$SCHEME" -configuration "$CONFIGURATION" build -quiet )
[[ -n "$DESTINATION" ]] && XCB_ARGS+=( -destination "$DESTINATION" )

(
  cd "$PROJECT_ROOT" || exit 1
  xcodebuild "${XCB_ARGS[@]}"
) >"$LOG" 2>&1
STATUS=$?

if [[ $STATUS -eq 0 ]]; then
  exit 0  # Silent success.
fi

# --- Distill errors -----------------------------------------------------------
# Grab anything matching "error:" or "warning:" plus a single line of context.
DISTILLED="$(grep -E -B0 -A0 "(error:|warning:|Undefined symbol|ld: |linker command failed)" "$LOG" || true)"

if [[ -z "$DISTILLED" ]]; then
  # xcodebuild failed but no recognizable error markers — show the tail.
  DISTILLED="$(tail -n 30 "$LOG")"
fi

# Cap output at 50 lines.
LINE_COUNT="$(printf '%s\n' "$DISTILLED" | wc -l | tr -d ' ')"
if (( LINE_COUNT > 50 )); then
  DISTILLED="$(printf '%s\n' "$DISTILLED" | head -n 30)"
  EXTRA=$(( LINE_COUNT - 30 ))
  DISTILLED="$DISTILLED

… $EXTRA more lines. Run /xcb for full output, or hand the log at $LOG to xcode-build-doctor."
fi

{
  echo "swiftui-vercel-stack: xcodebuild failed for scheme '$SCHEME' in $PROJECT_ROOT"
  echo "---"
  printf '%s\n' "$DISTILLED"
} >&2

exit 2

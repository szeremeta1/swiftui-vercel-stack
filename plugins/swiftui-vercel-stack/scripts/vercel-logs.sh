#!/usr/bin/env bash
# /vercel-logs — fetch recent runtime logs from the latest production deployment
# of the current Vercel project, filtered to errors and warnings.
#
# Walks up from $PWD to find a vercel.json or .vercel/ directory. Resolves the
# latest production deployment URL via `vercel ls --prod`, then pulls logs
# with `vercel logs <url>` and filters.
#
# Optional second argument overrides the deployment URL:
#   vercel-logs.sh "$PWD" https://my-deploy-abc123.vercel.app
#
# Exit codes:
#   0 — logs fetched (zero matching lines is still success — no errors!)
#   1 — vercel CLI missing, project not linked, or no deployment found
#   2 — `vercel logs` itself failed

set -uo pipefail

START_DIR="${1:-$PWD}"
URL_OVERRIDE="${2:-}"

if ! command -v vercel > /dev/null 2>&1; then
  echo "swiftui-vercel-stack: vercel CLI not found. Install with: npm i -g vercel" >&2
  exit 1
fi

find_vercel_root() {
  local dir="$1"
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if [[ -f "$dir/vercel.json" || -d "$dir/.vercel" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

PROJECT_ROOT="$(find_vercel_root "$START_DIR" || true)"
if [[ -z "$PROJECT_ROOT" ]]; then
  echo "swiftui-vercel-stack: no vercel.json or .vercel/ found at or above $START_DIR." >&2
  echo "Run 'vercel link' in your project root first." >&2
  exit 1
fi

# --- Resolve deployment URL ---------------------------------------------------
DEPLOY_URL="$URL_OVERRIDE"
if [[ -z "$DEPLOY_URL" ]]; then
  LIST_OUT="$(cd "$PROJECT_ROOT" && vercel ls --prod --yes 2>&1 || true)"
  DEPLOY_URL="$(printf '%s\n' "$LIST_OUT" | grep -oE 'https://[a-z0-9-]+\.vercel\.app' | head -n1)"
fi

if [[ -z "$DEPLOY_URL" ]]; then
  echo "swiftui-vercel-stack: could not resolve a production deployment URL for $PROJECT_ROOT" >&2
  echo "Try running 'vercel ls --prod' manually, or pass the URL as an argument." >&2
  exit 1
fi

echo "swiftui-vercel-stack: fetching logs for $DEPLOY_URL" >&2

# --- Fetch logs ---------------------------------------------------------------
LOG="$(mktemp -t vercel-logs.XXXXXX)"
trap 'rm -f "$LOG"' EXIT

(
  cd "$PROJECT_ROOT" || exit 1
  # `vercel logs <url>` returns a non-streaming snapshot when stdout is not a TTY.
  vercel logs "$DEPLOY_URL" 2>&1
) >"$LOG"
STATUS=$?

if [[ $STATUS -ne 0 ]]; then
  {
    echo "swiftui-vercel-stack: vercel logs failed for $DEPLOY_URL"
    echo "---"
    tail -n 30 "$LOG"
  } >&2
  exit 2
fi

# --- Filter to errors / warnings / non-2xx HTTP --------------------------------
# Vercel log lines look roughly like:
#   2026-04-26T20:30:00.000Z  ERROR  Function execution timed out
#   GET 200 /api/foo
#   GET 500 /api/bar  (interesting)
#   [error] something
ERRORS="$(grep -E -i \
  '(\bERROR\b|\bWARN\b|\[error\]|\[warn\]|exception|stack trace|unhandled|GET (4[0-9]{2}|5[0-9]{2}) |POST (4[0-9]{2}|5[0-9]{2}) |PUT (4[0-9]{2}|5[0-9]{2}) |DELETE (4[0-9]{2}|5[0-9]{2}) )' \
  "$LOG" || true)"

LINE_COUNT="$(printf '%s\n' "$ERRORS" | grep -c . || true)"

if [[ -z "$ERRORS" || "$LINE_COUNT" -eq 0 ]]; then
  echo "swiftui-vercel-stack: no errors or warnings in recent logs for $DEPLOY_URL"
  exit 0
fi

if (( LINE_COUNT > 80 )); then
  ERRORS="$(printf '%s\n' "$ERRORS" | tail -n 60)"
  EXTRA=$(( LINE_COUNT - 60 ))
  ERRORS="… $EXTRA earlier lines elided
$ERRORS"
fi

{
  echo "swiftui-vercel-stack: $LINE_COUNT error/warning lines from $DEPLOY_URL"
  echo "---"
  printf '%s\n' "$ERRORS"
}

exit 0

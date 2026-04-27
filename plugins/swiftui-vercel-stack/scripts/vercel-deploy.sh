#!/usr/bin/env bash
# /vercel-deploy — deploy the current Vercel project to production and surface
# only the deployment URL plus any error/warning lines.
#
# Walks up from $PWD to find a vercel.json or .vercel/ directory, runs
# `vercel deploy --prod --yes` from there, and filters output.
#
# Exit codes:
#   0 — deploy succeeded; stdout has the URL
#   1 — `vercel` CLI not installed (informational, non-blocking for Claude)
#   2 — deploy failed; stderr has the error context

set -uo pipefail

START_DIR="${1:-$PWD}"

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

LOG="$(mktemp -t vercel-deploy.XXXXXX)"
trap 'rm -f "$LOG"' EXIT

echo "swiftui-vercel-stack: deploying $PROJECT_ROOT to production…" >&2

(
  cd "$PROJECT_ROOT" || exit 1
  vercel deploy --prod --yes
) >"$LOG" 2>&1
STATUS=$?

# Extract the deployment URL — vercel prints it as the last vercel.app URL line.
DEPLOY_URL="$(grep -oE 'https://[a-z0-9-]+\.vercel\.app[^[:space:]]*' "$LOG" | tail -n1 || true)"

if [[ $STATUS -eq 0 ]]; then
  if [[ -n "$DEPLOY_URL" ]]; then
    echo "swiftui-vercel-stack: deploy succeeded → $DEPLOY_URL"
  else
    echo "swiftui-vercel-stack: deploy succeeded (no URL parsed; check 'vercel ls')."
  fi
  exit 0
fi

# Deploy failed — surface error lines.
ERRORS="$(grep -E -i '(error|fail|missing|invalid|not found|cannot)' "$LOG" || true)"
if [[ -z "$ERRORS" ]]; then
  ERRORS="$(tail -n 30 "$LOG")"
fi

LINE_COUNT="$(printf '%s\n' "$ERRORS" | wc -l | tr -d ' ')"
if (( LINE_COUNT > 50 )); then
  ERRORS="$(printf '%s\n' "$ERRORS" | head -n 30)"
fi

{
  echo "swiftui-vercel-stack: vercel deploy FAILED in $PROJECT_ROOT"
  echo "---"
  printf '%s\n' "$ERRORS"
} >&2

exit 2

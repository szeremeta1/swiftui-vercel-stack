#!/usr/bin/env bash
# PostToolUse hook: after a server file is edited, remind Claude (and indirectly
# the user) to deploy. Non-blocking: deploy is irreversible-ish, so this hook
# never auto-deploys — it just nudges.
#
# Stdin (JSON): {"tool_name": ..., "tool_input": {"file_path": ...}, "cwd": ...}
# Exit code: 0 (always — the message is informational).

set -uo pipefail

STDIN="$(cat)"

extract_json() {
  local key="$1"
  printf '%s' "$STDIN" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    keys = '$key'.split('.')
    val = data
    for k in keys:
        val = val.get(k) if isinstance(val, dict) else None
        if val is None:
            sys.exit(0)
    print(val)
except Exception:
    sys.exit(0)
"
}

FILE_PATH="$(extract_json 'tool_input.file_path')"
[[ -z "$FILE_PATH" ]] && exit 0

REL="$FILE_PATH"

cat >&2 <<EOF
swiftui-vercel-stack: server file edited ($REL).
When you finish this batch of changes, deploy with:  vercel deploy --prod
(This plugin does NOT auto-deploy — confirm with the user first.)
EOF

exit 0

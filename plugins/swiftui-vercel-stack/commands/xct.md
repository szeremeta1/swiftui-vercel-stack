---
description: Run xcodebuild test for the current SwiftUI project and report failures only.
---

Run the bundled test script:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/xcodebuild-test.sh"
```

The script auto-detects the `.xcodeproj` above the current working directory, picks the scheme (from `.swiftui-vercel-stack.json` if present, else from the project basename), picks an iOS simulator destination (config-provided > first available iPhone simulator > "iPhone 16"), and runs `xcodebuild test -quiet`.

On success, prints a one-line confirmation with the pass count. On failure, prints only the failing test cases and their assertion messages (capped at 80 lines).

Use this when you've edited test files, after a refactor, or before declaring a feature done. The build hook (`xcodebuild-after-swift`) only verifies compilation — `/xct` verifies behavior.

If failures look like they stem from concurrency, macros, or codesigning rather than your test logic, hand the output to the `xcode-build-doctor` subagent.

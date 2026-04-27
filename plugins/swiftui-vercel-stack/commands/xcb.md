---
description: Run xcodebuild for the current SwiftUI project and report errors only.
---

Run the bundled build script for the current project:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/xcodebuild-after-swift.sh" < /dev/null
```

The script auto-detects the `.xcodeproj` above the current working directory, picks the scheme (from `.swiftui-vercel-stack.json` if present, else from the project basename), runs `xcodebuild build -quiet`, and prints **only** errors and warnings on failure. Use this after a `git pull`, branch switch, or whenever you want to verify the build state without making an edit.

If the script reports failures you can't immediately interpret (Swift 6 concurrency, macro expansion, codesigning, etc.), hand the output to the `xcode-build-doctor` subagent for diagnosis.

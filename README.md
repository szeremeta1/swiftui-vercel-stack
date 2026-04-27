# swiftui-vercel-stack

A Claude Code marketplace for full-stack SwiftUI iOS + Vercel/Next.js workflows.

## Plugins

### `swiftui-vercel-stack`

Hooks and helpers for the most common friction in SwiftUI + Vercel projects:

- **Hooks:** auto-`xcodebuild` after every Swift edit (errors only), and a non-blocking deploy reminder after server edits.
- **Slash commands:** `/xcb` (build), `/xct` (test), `/typecheck` (tsc), `/vercel-deploy` (prod deploy), `/vercel-logs` (filtered runtime logs), `/upstash-audit` (Redis cost analysis).
- **Subagents:** `xcode-build-doctor` (diagnose Swift 6 / SwiftUI / codesigning failures), `parity-check` (diff iOS Swift feature against Android Kotlin counterpart).

See [plugins/swiftui-vercel-stack/README.md](plugins/swiftui-vercel-stack/README.md) for full details, configuration, and architecture.

## Install

```
/plugin marketplace add szeremeta1/swiftui-vercel-stack
/plugin install swiftui-vercel-stack@swiftui-vercel-stack
```

## License

MIT — see [LICENSE](LICENSE).

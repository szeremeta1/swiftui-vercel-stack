# swiftui-vercel-stack

A Claude Code marketplace for full-stack SwiftUI iOS + Vercel/Next.js workflows.

## Plugins

### `swiftui-vercel-stack`

Hooks and helpers for the most common friction in SwiftUI + Vercel projects:

- Auto-runs `xcodebuild` after every Swift edit and surfaces only the errors (not the full build log).
- Reminds Claude to deploy after server edits — without auto-deploying.
- Ships a `/xcb` slash command for on-demand builds and an `xcode-build-doctor` subagent for diagnosing failures.

See [plugins/swiftui-vercel-stack/README.md](plugins/swiftui-vercel-stack/README.md) for full details, configuration, and architecture.

## Install

```
/plugin marketplace add szeremeta1/swiftui-vercel-stack
/plugin install swiftui-vercel-stack@swiftui-vercel-stack
```

## License

MIT — see [LICENSE](LICENSE).

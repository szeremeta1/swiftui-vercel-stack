# swiftui-vercel-stack

A Claude Code plugin that automates the verification loop for SwiftUI iOS + Vercel/Next.js projects.

If your project's `CLAUDE.md` says things like *"run `xcodebuild` after every Swift edit before calling done"* or *"deploy to Vercel after every server modification"*, this plugin moves that enforcement out of the prompt into deterministic hooks. Hooks fire regardless of whether Claude remembered the rule, and only the *errors* (not the full build log) come back to Claude — saving a meaningful chunk of context per session.

## What it does

### Hooks (automatic, no invocation needed)

| Hook | Triggered by | Behavior |
|---|---|---|
| `xcodebuild-after-swift` | Edit/Write/MultiEdit on `*.swift` | Runs `xcodebuild build` for the enclosing project. Silent on success; on failure, returns only `error:`/`warning:` lines (capped at 50). Blocks Claude with exit 2 on failure. |
| `vercel-deploy-reminder` | Edit/Write under `server/`, `api/`, `app/api/` | Prints a non-blocking nudge to deploy. Never auto-deploys. |

### Slash commands (manual)

| Command | Purpose |
|---|---|
| `/xcb` | Run `xcodebuild build` for the current project. Errors only. Useful after `git pull` or branch switch. |
| `/xct` | Run `xcodebuild test`. Failing test cases + assertion messages only. |
| `/typecheck` | Run `tsc --noEmit` for the nearest TypeScript project. `error TS####:` lines only. |
| `/vercel-deploy` | `vercel deploy --prod --yes` from the nearest Vercel project root. Surfaces only the deployment URL or filtered error context. |
| `/vercel-logs [url]` | Fetch recent runtime logs from the latest production deployment. Filters to errors, warnings, and non-2xx HTTP responses. Optional URL argument inspects a specific deploy. |
| `/upstash-audit` | Systematic command-volume audit of a Vercel + Upstash Redis project. Ranks call sites by estimated cost, proposes patches (in-process caching, MGET coalescing, `Cache-Control` headers, early-exit crons). |

### Subagents (delegated)

| Agent | Purpose |
|---|---|
| `xcode-build-doctor` | Diagnoses xcodebuild failures — Swift 6 strict concurrency, SwiftUI macro expansion, codesigning, linker errors, stale derived data. Proposes a minimal fix with a confidence rating. |
| `parity-check` | Compares an iOS Swift feature against its Android Kotlin counterpart. Reports behavioral, API contract, state-handling, localization/a11y, and analytics gaps. Skips style differences. |

## Install

```
/plugin marketplace add szeremeta1/swiftui-vercel-stack
/plugin install swiftui-vercel-stack@swiftui-vercel-stack
```

## Configuration

Most projects need no configuration — the plugin auto-detects the `.xcodeproj` above the edited file and infers the scheme from its basename (`Foo.xcodeproj` → scheme `Foo`).

To override defaults, drop a `.swiftui-vercel-stack.json` at the root of your project:

```json
{
  "scheme": "MyApp",
  "configuration": "Debug",
  "destination": "platform=iOS Simulator,name=iPhone 16"
}
```

| Key | Default | Used by | Purpose |
|---|---|---|---|
| `scheme` | basename of `*.xcodeproj` | hook, `/xcb`, `/xct` | Scheme passed to `xcodebuild -scheme` |
| `configuration` | `Debug` | hook, `/xcb`, `/xct` | Passed to `-configuration` |
| `destination` | auto-detect (first available iPhone simulator), else `iPhone 16` | `/xct` only | Passed to `-destination` (only required for `test`) |

## How the build hook works

`scripts/xcodebuild-after-swift.sh`:

1. Reads the edited file path from the hook's stdin JSON.
2. Walks up the directory tree until it finds a `.xcodeproj` or `.xcworkspace`. If none, exits silently — not every Swift file lives in an Xcode project (e.g. SwiftPM scratch).
3. Reads optional `.swiftui-vercel-stack.json` from the project root.
4. Runs `xcodebuild -scheme <scheme> -configuration <config> build -quiet`.
5. On success, exits 0 silently. On failure, distills `error:`/`warning:` lines from the log, caps at 50 lines, prints to stderr, and exits 2 (blocking — Claude must address before continuing).

All slash commands follow the same project-discovery pattern: walk up from `$PWD` to find the relevant marker (`*.xcodeproj`, `tsconfig.json`, `vercel.json`/`.vercel/`), exit silently if not found, otherwise execute and filter output.

## Why hooks instead of CLAUDE.md instructions?

1. **Determinism.** Prose in `CLAUDE.md` works *most* of the time. A hook works *every* time.
2. **Context savings.** A full xcodebuild log can be hundreds of lines of `Build settings`, `Probing signature of`, `Touch /path/to/...` noise. The hook strips it down to the actual diagnostic lines, which is all Claude needs to react. Same for `tsc`, `vercel deploy`, and `vercel logs` output.

The Vercel deploy is intentionally *not* automated. Pushing to production is irreversible enough that the human (or at minimum an explicit Claude action via `/vercel-deploy`) should be in the loop.

## Requirements

- **macOS** for the Swift bits (`xcodebuild` is macOS-only). The Vercel and TypeScript pieces work on Linux too.
- **`python3`** on `PATH` (bundled with macOS).
- **`vercel` CLI** for `/vercel-deploy` and `/vercel-logs` (`npm i -g vercel`, then `vercel link` in your project).
- **Project-local TypeScript** for `/typecheck` (the script prefers `node_modules/.bin/tsc` over global).

## Limitations

- The build hook does not do dependency-aware caching — every `.swift` edit triggers a build. Xcode's compiler caches keep this fast for incremental edits, but cold builds on large projects can take seconds.
- Single-scheme assumption. Multi-scheme projects need a `.swiftui-vercel-stack.json` to disambiguate.
- `/xct` runs the full test target. There's no per-file test selection yet.
- `/upstash-audit` makes order-of-magnitude estimates, not exact predictions. It's directionally right; treat numbers as ±50%.
- `parity-check` reads source code only — it can't catch runtime-only behavioral gaps. It tells you when it's uncertain.

## License

MIT

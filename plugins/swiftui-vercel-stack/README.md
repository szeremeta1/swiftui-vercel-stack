# swiftui-vercel-stack

A Claude Code plugin that automates the verification loop for SwiftUI iOS + Vercel/Next.js projects.

If your project's `CLAUDE.md` says things like *"run `xcodebuild` after every Swift edit before calling done"* or *"deploy to Vercel after every server modification"*, this plugin moves that enforcement out of the prompt into deterministic hooks. The hook fires regardless of whether Claude remembered the rule, and only the *errors* (not the full build log) come back to Claude — saving a meaningful chunk of context per session.

## What it does

| Component | Type | Behavior |
|---|---|---|
| `xcodebuild-after-swift` | `PostToolUse` hook | After Edit/Write/MultiEdit on a `*.swift` file, runs `xcodebuild build` for the enclosing project. Silent on success; on failure, returns only `error:`/`warning:` lines (capped at 50). |
| `vercel-deploy-reminder` | `PostToolUse` hook | After Edit/Write under `server/`, `api/`, or `app/api/`, prints a non-blocking reminder to deploy. Never auto-deploys. |
| `/xcb` | Slash command | On-demand build for the current project. Same logic as the hook, callable explicitly (e.g. after a `git pull` with no edits). |
| `xcode-build-doctor` | Subagent | Diagnoses xcodebuild failures — Swift 6 concurrency, SwiftUI macro expansion, codesigning, linker errors, stale derived data. Proposes a minimal fix. |

## Install

```
/plugin marketplace add szeremeta/swiftui-vercel-stack
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

| Key | Default | Purpose |
|---|---|---|
| `scheme` | basename of `*.xcodeproj` | Scheme passed to `xcodebuild -scheme` |
| `configuration` | `Debug` | Passed to `-configuration` |
| `destination` | (unset) | Passed to `-destination` if present |

## How it works

The hook script (`scripts/xcodebuild-after-swift.sh`):

1. Reads the edited file path from the hook's stdin JSON.
2. Walks up the directory tree until it finds a `.xcodeproj` or `.xcworkspace`. If none, exits silently — not every Swift file lives in an Xcode project.
3. Reads optional `.swiftui-vercel-stack.json` from the project root.
4. Runs `xcodebuild -scheme <scheme> -configuration <config> build -quiet`.
5. On success, exits 0 silently. On failure, distills `error:`/`warning:` lines from the log, caps at 50 lines, prints to stderr, and exits 2 (blocking — Claude must address before continuing).

The slash command runs the same script with empty stdin; the script falls back to `$PWD` when no file path is on stdin.

## Why a hook?

Two reasons:

1. **Determinism.** Putting "run xcodebuild after every Swift edit" in `CLAUDE.md` works *most* of the time. A hook works *every* time.
2. **Context savings.** A full xcodebuild log can be hundreds of lines of `Build settings`, `Probing signature of`, `Touch /path/to/...` noise. The hook strips it down to the actual diagnostic lines, which is all Claude needs to react.

The Vercel reminder is intentionally *not* an auto-deploy. Pushing to production is irreversible enough that the human (or at minimum an explicit Claude action) should be in the loop.

## Limitations

- macOS only (xcodebuild is macOS-only).
- Requires `python3` on `PATH` (bundled with macOS).
- The hook does not do dependency-aware caching — every `.swift` edit triggers a full rebuild. For most incremental builds this is fast (Xcode caches at the compiler level), but on large projects with cold caches the first run can be slow.
- Single-scheme assumption. Multi-scheme projects need a `.swiftui-vercel-stack.json` to disambiguate.

## License

MIT

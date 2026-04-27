---
description: Run `tsc --noEmit` for the current TypeScript project and report only TS errors.
---

Run the bundled type-check script:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/typecheck.sh"
```

The script walks up from the current working directory to find a `tsconfig.json`, picks the project's local TypeScript compiler (`node_modules/.bin/tsc`) when present, and runs `tsc --noEmit --pretty false`.

On success, prints a one-line confirmation. On failure, prints only `error TS####:` lines (capped at 60).

Use this on Next.js / Express / Node projects after a refactor or before deploying. Type errors caught here would otherwise show up at `vercel deploy --prod` time, which is much slower to iterate on.

If the project has no `tsconfig.json`, the script silently skips — pure JavaScript projects are not its concern.

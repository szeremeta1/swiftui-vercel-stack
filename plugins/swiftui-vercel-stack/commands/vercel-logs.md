---
description: Fetch recent runtime logs from the latest Vercel production deployment, filtered to errors and warnings.
---

Run the bundled logs script:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vercel-logs.sh" "$PWD" $ARGUMENTS
```

The script walks up from the current working directory to find the Vercel project root, resolves the latest production deployment via `vercel ls --prod`, then pulls logs with `vercel logs <url>` and filters for:

- `ERROR` / `WARN` / `[error]` / `[warn]` log lines
- Stack traces and unhandled exceptions
- Non-2xx HTTP responses (`GET 500 /api/foo`, etc.)

Output is capped at 60 lines (most recent kept).

**Optional argument:** pass a specific deployment URL to inspect that deploy instead of the latest:

```
/vercel-logs https://my-deploy-abc123.vercel.app
```

Use this after a `/vercel-deploy` to verify the deployment is healthy, or whenever a user reports a production issue.

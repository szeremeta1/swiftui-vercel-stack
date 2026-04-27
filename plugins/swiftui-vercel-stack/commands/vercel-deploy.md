---
description: Deploy the current Vercel project to production and surface only the URL or error context.
---

Run the bundled deploy script:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vercel-deploy.sh"
```

The script walks up from the current working directory to find a `vercel.json` or `.vercel/` directory, then runs `vercel deploy --prod --yes` from that root. Output is filtered:

- **Success** → one line with the deployment URL.
- **Failure** → one line header + filtered error/warning context (capped at 50 lines).

Requires the `vercel` CLI (`npm i -g vercel`) and an existing project link (`vercel link`).

This is the deliberate counterpart to the `vercel-deploy-reminder` hook: the hook nudges Claude to deploy after server edits, this command actually does it. **Confirm with the user before running** — production deploys are visible to end users.

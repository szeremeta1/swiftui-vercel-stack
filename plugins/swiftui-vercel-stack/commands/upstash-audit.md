---
description: Audit a Vercel + Upstash Redis project for command-volume hotspots and propose caching fixes.
---

You are about to perform a systematic Upstash Redis cost audit for the project at `$PWD`. The goal: identify the top command-volume drivers and propose concrete patches that reduce Redis traffic without changing behavior.

## Why this matters

Upstash pay-as-you-go pricing is **command-count driven** (~$0.20 per 100K commands), with a 500K/month free tier. A typical aggregator project that runs CRON jobs hitting Redis ends up burning the free tier within days — usually because of (a) RSS-style dedup GETs on every cron cycle, (b) per-request `getAllSources()` calls with no in-process cache, (c) per-item override lookups that miss 99% of the time, and (d) cron jobs that hold locks every N minutes even when there's nothing to do.

## Procedure

### 1. Find every Redis call site

Use Grep to find calls to common Redis clients (Upstash, ioredis, node-redis, `@vercel/kv`):

```bash
grep -rE "redis\.(get|set|del|sadd|smembers|sismember|zadd|zrange|zrem|incr|expire|hset|hget|scan|rpop|rpush|lrange)|kv\.(get|set|del|incr)|new Redis|createClient|@upstash/redis|@vercel/kv" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.mjs" -n .
```

Read each call site to understand:
- Which key pattern it touches (`source:*`, `dedup:*`, `device:*`, etc.)
- How many ops per invocation (1 GET? 1 SMEMBERS + N GETs? batch?)
- What triggers the invocation (HTTP route handler? cron? lazy init?)

### 2. Find cron schedules

Check `vercel.json` for the `crons` array. Each entry's `schedule` is a cron expression — convert to invocations per day:

| Schedule          | Per day | Per month |
|-------------------|---------|-----------|
| `* * * * *`       | 1440    | 43,200    |
| `*/5 * * * *`     | 288     | 8,640     |
| `*/10 * * * *`    | 144     | 4,320     |
| `*/15 * * * *`    | 96      | 2,880     |
| `0 * * * *`       | 24      | 720       |
| `0 0 * * *`       | 1       | 30        |

For each cron route, multiply: `ops_per_invocation × invocations_per_month`.

### 3. Estimate HTTP-route-driven volume

For routes that hit Redis on every request, you need a request-volume estimate. Ask the user if they don't have one; otherwise assume modest defaults (1K req/day for a hobby project, 100K/day for a small production app) and flag the assumption explicitly.

### 4. Build the ranked table

```
| Rank | Driver | Est. commands/mo | Est. $ | Why |
|------|--------|------------------|--------|-----|
| 1    | <key pattern + caller> | XK–YM | $X.XX | <root cause> |
| ...  | ... | ... | ... | ... |
```

Include estimates within an order of magnitude — precision isn't the point, the *ranking* is.

### 5. Propose fixes

For each top driver, propose the smallest patch that reduces traffic. Common moves, in order of leverage:

1. **In-process memoization** for "config-like" reads (`getAllSources()`, feature flags, override lists). A 60s in-memory cache typically cuts these by 99% without staleness issues.
2. **Coalesce per-item GETs into one batch** (`MGET`, or a single SMEMBERS + bulk pipeline) when iterating a list.
3. **Set HTTP `Cache-Control` headers** on cacheable routes (`/api/feed`, `/api/sources`, `/api/config/*`) so Vercel's edge cache absorbs reads before they hit Redis.
4. **Early-exit cron jobs** that check a cheap "is there anything to do?" key before doing the expensive workflow. A SISMEMBER on a flag is cheaper than SCAN + N GETs.
5. **Replace dedup GETs with SADD-and-check-return-value** — a single SADD returning 0 means "already seen" without needing a separate GET.
6. **Increase cron interval** when 5-minute granularity isn't actually needed for the user-facing behavior. Doubling the interval halves the cost.

### 6. Note what NOT to touch

End the report with a "leave alone" section listing call sites that look noisy but are actually cheap (e.g. ZADDs that fire only on new items, fixed-key cleanup ops, infinitely-cached translation keys). This prevents future Claude sessions from "optimizing" hot paths that aren't actually hot.

### 7. Output format

```markdown
## Upstash audit: <project name>

### Assumptions
- Request volume: <N>/day (<source: user-provided | flagged default>)
- Time window: <month | last 30 days>

### Top drivers
| Rank | Driver | Est. cmd/mo | Est. $ | Why |
|------|--------|-------------|--------|-----|
| 1    | ... | ... | ... | ... |

### Recommended patches (ordered by ROI)
1. **<driver>** → <patch> (file:line). Saves ~XK cmd/mo.
2. ...

### Leave alone
- <call site>: <why it's fine>
```

Be honest about confidence. If you're guessing at request volume, say so. If a call site's frequency depends on user behavior you can't measure, say so.

---

Now perform the audit for the project at `$PWD`.

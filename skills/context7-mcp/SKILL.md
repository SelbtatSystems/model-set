---
name: context7-mcp
description: >
  Fetch current, version-accurate library/framework docs via Context7 MCP instead of
  relying on training data. Use proactively BEFORE writing or changing any code touching
  an external library/framework/SDK where API details, config, or version-specific
  behaviour matter — and when debugging a lib-specific error, migrating versions, or
  unsure an API still exists. Trigger even when the user doesn't say "Context7" or "docs":
  if the task involves Stripe, NestJS, TypeORM, Expo, React Query, React Hook Form, React
  Router, Vite, class-validator, Lucide, or any third-party package, pull docs first. Do
  NOT use for general concepts, refactoring, business logic, code review, or scripts with
  no external dependency.
---

# Context7 MCP

Up-to-date, version-specific docs and code examples for ~9,000+ libraries, fetched from
source at query time. Stops you coding against a stale or hallucinated API.

**Use it (proactively, before coding):** implementing against any external lib/SDK where
API shape, config, or version behaviour matters; debugging a lib-specific error; migrating
versions; or unsure a signature/option/pattern is current. Prefer over web search for
library-specific questions.

**Don't use it:** general concepts, algorithms, refactoring, business logic, code review,
or standalone scripts with no third-party dependency.

## Workflow

**1. Resolve the ID** (skip if you already know it) — turns a name into `/org/project[/version]`:

```
mcp__context7__resolve-library-id libraryName:"stripe"
```

Returns ranked matches (trust score + coverage); pick the one matching the package you use.
Ambiguous? Inspect matches rather than guess — a wrong ID returns "documentation not found".

**2. Fetch the docs:**

```
mcp__context7__query-docs libraryId:"/stripe/stripe-node" topic:"subscriptions"
```

- `libraryId` (required) — exact ID from step 1.
- `topic` — always set it (`"webhooks"`, `"routing"`, `"migrations"`); un-topic'd fetches
  waste tokens. One topic per fetch — do separate focused fetches for multiple areas.
- token budget — default ~5000; raise only for a broad API sweep.

## Shortcuts

- **Known ID → skip resolve.** The `/org/project` format lets you go straight to fetch.
- **Version-pin** by appending a version; fetch a named version's docs, not latest:
  `libraryId:"/vercel/next.js/v15.0.0" topic:"app router"`.

## Pin your stack

Resolve each common lib **once**, then record IDs here (or in CLAUDE.md) to skip step 1.
Resolve — don't guess the slug:

```
stripe -> /stripe/stripe-node   # confirmed
nestjs / typeorm / expo / react-query / react-hook-form /
react-router / vite / class-validator / lucide -> <resolve once, then pin>
```

## Gotchas

- **"Documentation not found"** = bad/invalid ID → re-run resolve. An unindexed version
  also fails; drop to `/org/project` (latest).
- **Thin results?** Raise the token budget or page through (some versions expose `page`,
  1–10) with the same topic.
- Docs are community-contributed; quality varies — cross-check anything surprising.

## Compatibility — verify YOUR surface with `/mcp`

Two tool surfaces exist; adjust the calls above to match yours:

- **This skill targets:** `resolve-library-id` + `query-docs` (fetch arg `libraryId`).
- **Classic `@upstash/context7-mcp`:** `resolve-library-id` + `get-library-docs`, arg
  `context7CompatibleLibraryID`, plus `topic` / `tokens` (default 5000) / `page`.
- Narrowing arg is `topic:` on most installs; the newest platform interface uses `query:`
  (a natural-language question). Use whichever yours exposes.

If names differ, update the `mcp__context7__*` calls and fetch arg throughout — the rest
(resolve → fetch, pinning, topic-narrowing, versioning) is unchanged.
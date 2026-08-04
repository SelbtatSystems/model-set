# Risk playbooks — high-tier hand-checks

Hand-checks the automated review skills do not run. Reach for the playbook that matches the diff. Tuned to a Dockerized TypeScript stack (NestJS API · React/Vite + Next.js front-ends · Postgres with RLS · Redis · MinIO). Run on top of `/security-review` and `/verify`, not instead of them.

## Recording deferred security findings

Medium/low `/security-review` findings are **not** merge blockers — record them for later in the owning context's `SECURITY.md`, then merge.

**Resolve the file** from the linked ticket's `**App:**` value (or, with no ticket, the app directory the changed files live under):

| `**App:**` | `SECURITY.md` |
| --- | --- |
| `backend` | `memory/backend/SECURITY.md` |
| `agcore-web` | `memory/apps/AgCore-web/SECURITY.md` |
| `myfarmjob-web` | `memory/apps/MyFarmJob/SECURITY.md` |
| `eform` | `memory/apps/eForm/SECURITY.md` |
| `agcore-landing` | `memory/apps/AgCore-landing/SECURITY.md` |
| `myfarmjob-landing` | `memory/apps/MyFarmJob-landing/SECURITY.md` |
| `admin-web` | `memory/apps/Admin-web/SECURITY.md` |
| `shared` / cross-cutting | `memory/docs/SECURITY.md` |

This map is AgCore/MyFarmJob-specific — use it only when `./memory` resolves. Other repos: resolve via the repo's own context map, else fall back to the repo's `docs/SECURITY.md`. The target file is missing entirely → fall back to `docs/SECURITY.md` and note it in the report.

**Write the file only — never run `git` or scripts in `memory/`** (the wiki's own agent commits + reindexes). Append under a dedicated heading so curated invariants are never touched — create the heading once if absent, then append a dated bullet per finding (newest last):

```markdown
## Deferred findings (merge-pr)

- 2026-06-29 · PR #52 · low · apps/eForm/.../Field.tsx — <one-line finding + suggested fix>
```

One bullet per finding: `date · PR# · severity · file · finding + fix`.

## DB migrations

A pulled migration is **not** auto-applied to a local/worktree DB — apply it before testing.

- Migration runs clean on a **fresh** DB (init.sql + all migrations).
- Migration runs clean on an **existing** populated DB (the real upgrade path).
- Ships migration **and** `init.sql` in the same change; drift guard passes (`./scripts/check-init-schema.sh` or equivalent).
- No silent data loss: column drops/renames/type narrowing have a backfill or are confirmed safe against current data.
- Reversible, or the irreversibility is called out.
- New foreign keys / hot columns have the indexes the queries need.
- Delegate non-trivial schema work to the **data-layer** agent.

## Multi-tenant isolation (RLS / org scoping)

The highest-stakes regression class — one missed scope leaks another org's data.

- Request as org A, then org B: A cannot read/write B's rows, and vice versa.
- Every request sets the tenant context (e.g. `app.current_org`) before touching tenant tables.
- Background jobs / system tasks run under an explicit org context or a deliberate privileged path — never an ambient one.
- New tables holding tenant data have RLS enabled + a policy (not just app-layer filtering).
- List/search/aggregate endpoints are scoped — count and export paths leak just as easily as detail reads.

## Auth + tokens

- New/changed endpoints carry the right guard; nothing privileged is unauthenticated by omission.
- Access vs refresh token lifetimes and rotation unchanged unless intended.
- Magic-link / one-time tokens: single-use, expiring, unguessable; replay and expiry tested.
- Validation is server-side (class-validator / DTO), not only in the front-end.
- Unauthenticated and wrong-role requests fail **closed** (403/401), not open.

## PII + legal/immutable documents

- Sensitive fields (TFN, passport, bank) stay encrypted at rest; not logged, not in error messages, not in API responses that don't need them.
- Generated legal records (agreements, submissions) are immutable once issued — no edit path reopens them.
- File uploads: type + size validated server-side; storage keys not user-controlled / not guessable; presigned URLs scoped + expiring.

## API contract (front ↔ back)

Where full-stack PRs break silently: backend renamed a field, frontend still reads the old one.

- Request + response shapes match what the client sends/expects (field names, nullability, enums).
- Status codes and error shapes unchanged, or both sides updated together.
- Backwards compatibility for any client not in this PR (mobile, third parties).
- Verify a real call end-to-end (`curl` the endpoint or drive the UI), not just types.

## Refactor equivalence (low-risk, but prove it)

For a move-only / no-behaviour-change PR, prove nothing changed:

- Build green + existing unit and e2e tests green.
- Route inventory identical before vs after.
- Diff is renames + import-path edits only — flag any hunk with real logic change (it means the PR is not actually move-only).

## Failure + observability

For PRs touching submissions, payments, file generation, or external calls:

- Errors are logged with enough context to debug, without leaking secrets/PII.
- Each external failure handled cleanly: PDF generation, MinIO upload, Stripe call, email send, DB transaction rollback.
- Background jobs are idempotent — a retry does not duplicate data.
- No new noisy log floods on the normal path.

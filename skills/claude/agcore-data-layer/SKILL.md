---
name: agcore-data-layer
description: AgCore/MyFarmJob data-layer work for PostgreSQL, Redis, and MinIO. Use when working in the AgCore repo and the task touches schema design, migrations, init.sql drift, RLS, SQL queries, indexes, performance, Redis sessions/rate limits/cache/presence, MinIO buckets, storage keys, presigned URLs, or asks where data should live.
---

# AgCore Data Layer

Use this skill only for AgCore/MyFarmJob data-layer work. If the current workspace is not the AgCore repo, say the skill is project-specific and stop using it.

## First Read

Read these before planning or editing:

1. `CONTEXT-MAP.md`
2. `memory/AgCore/db/CONTEXT.md`
3. `memory/AgCore/db/SECURITY.md`
4. Relevant accepted ADRs in `memory/AgCore/db/docs/adr/`, if any exist

Completion criterion: know the current schema/storage source of truth, security invariants, and validation commands before touching files.

## Mode Gate

Decide the mode before touching state.

**Plan mode**: use when the user asks to plan, design, scope, assess, review, or when the main agent is in Plan mode. Stay read-only. Inspect files and read-only database/storage state only. Do not create migrations, edit `init.sql`, mutate Redis/MinIO, run DDL/DML, or edit `memory/AgCore/db/CONTEXT.md`.

Return only:

```markdown
**Data-Layer Plan**
- **Stores touched**: Postgres / Redis / MinIO + why each
- **Schema**: tables/columns/indexes/constraints to add or alter
- **Migration**: `db/migrations/YYYYMMDD_*.sql` + matching `db/init.sql` edits
- **Cache**: Redis key patterns + TTLs
- **Storage**: buckets + storage-key columns
- **Steps**: ordered build steps, including drift guard
- **Risks**: data-loss, prod-safety, RLS, drift, performance
- **Open questions**: blockers only
```

**Build mode**: use when the user explicitly asks to implement/add/change/fix/migrate, or an approved plan already exists. Run the relevant workflow below.

If unsure, choose plan mode.

## Store Routing

Route before designing.

| Data shape | Store | Examples |
|---|---|---|
| Permanent, relational, ACID, JOINs, audit, geo, full-text | PostgreSQL | users, jobs, time entries, pay, org structure |
| Ephemeral, fast, expiring key-value | Redis | sessions, rate limits, API cache, presence, temp tokens |
| Binary blobs, documents, generated files | MinIO | avatars, eForm PDFs, visa docs, uploads |

Features often span stores. Example: generated PDF = MinIO object plus Postgres row with a storage key. Name each store's role explicitly.

If the task does not touch persistence, caching, or object storage, say so and hand back.

## PostgreSQL Workflow

For any schema/table/column/index/query/RLS change:

1. Verify current state from `db/init.sql`, TypeORM entities, migrations, and live dev DB when available.
2. Before schema design/refactor, use pg-aiguide if available:
   - `design-postgres-tables`: default for tables, data types, constraints, indexes, JSONB.
   - `design-postgis-tables`: spatial columns; this DB uses PostGIS.
   - `postgres_16` docs for version-specific behavior.
3. For TypeORM/NestJS API specifics, use Context7 docs before changing decorators, entities, migrations tooling, or framework APIs.
4. Write a migration: `db/migrations/YYYYMMDD_short_description.sql`.
5. Update `db/init.sql` in the same change. This is mandatory. Fresh DBs do not replay migrations.
6. Apply and verify in the Docker dev stack or postgres MCP when available.
7. Run `./scripts/check-init-schema.sh`.

Completion criterion: migration, `init.sql`, entity expectations, live/dev verification, and drift guard all agree, or every remaining gap is reported with exact command + error.

## RLS And Safety

Tenant isolation is release-blocking.

- Preserve `orgId`/`org_id` scoping and Postgres RLS.
- Preserve `FORCE ROW LEVEL SECURITY`.
- Do not forge, drop, or trust `x-org-id` without membership validation.
- Do not add raw SQL or unscoped repository calls that bypass tenant checks.
- Keep `app.current_org` and `app.current_user` GUC assumptions intact.
- Keep app-side encryption wiring in sync when touching PII/TFN/payroll/super/right-to-work data.
- Keep dev-only extensions (`hypopg`, `pg_stat_statements`) out of `db/init.sql`.

Destructive statements (`DROP`, `TRUNCATE`, broad `DELETE`, data-dropping `ALTER`) require an explicit reason in the plan and a heads-up before execution.

## Redis Workflow

Use Redis only for ephemeral data.

Known patterns:

| Use | Pattern | TTL |
|---|---|---|
| Sessions | `session:{userId}:{tokenId}` | 7d |
| Rate limit | `ratelimit:{ip}:{endpoint}` | 1m |
| API cache | `cache:api:{endpoint}:{hash}` | 5-60m |
| Presence | `presence:{userId}` | 30s |
| Temp | `temp:{purpose}:{id}` | varies |

Inspect with Docker from `infrastructure/docker`:

```bash
docker compose --env-file ../../.env exec redis redis-cli -a "$REDIS_PASSWORD" <CMD>
```

Never store permanent relational data, audit data, or data needing JOINs/ACID in Redis.

## MinIO Workflow

Use MinIO only for blobs. Postgres stores metadata and object keys.

Buckets:

| Bucket | Policy | Contents |
|---|---|---|
| `avatars` | public | profile images under `users/{userId}/`, images only, <=2MB |
| `documents` | private/presigned | eForm PDFs, visa docs, user documents, generated private files |
| `uploads` | private | general uploads |

Inspect with `mc`:

```bash
mc ls agcore-local
mc ls --recursive agcore-local/documents
mc stat agcore-local/documents/<key>
mc anonymous get-json agcore-local/<bucket>
```

When changing storage-key columns or bucket layout, keep `backend/src/storage/storage.service.ts`, owning entities, and `memory/AgCore/db/CONTEXT.md` in sync. Private reads use presigned URLs; never expose internal Docker hostnames such as `minio:9000` to browsers.

## Build Summary

For build mode, end with:

```markdown
**Changes**: [file]: [what + why]
**Untouched**: [file]: [why left alone]
**Concerns**: [risks to verify, including data loss, prod safety, drift guard status]
**Removed Dead Code**: [list]
```

Also report exact validation commands and results. If a required check cannot run, say why and what was already verified.

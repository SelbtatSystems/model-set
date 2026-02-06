# CLAUDE.md - AgCore/MyFarmJob Platform

> **Update this file when major changes made** to maintain accurate reference, be concise.

- In all interactions and commit messages, be concise and sacrifice grammar for the sake of concision

## Overview
Full-stack agricultural workforce platform (Australia) serving two user groups:
- **myfarmjob.com** - Job seekers search/apply for farm work
- **agcore.com.au** - super Farm businesses app manage workforce, payroll, compliance, propertys and horticulural operations.

## Architecture
```
agcore/
├── apps/
│   ├── agcore-web/         # Business dashboard (React+Vite)
│   ├── myfarmjob-web/      # Job seeker portal (React+Vite)
│   ├── myfarmjob-eForm-web/# Public eForm app (React+Vite)
│   ├── agcore-mobile/      # Business mobile (RN+Expo)
│   └── myfarmjob-mobile/   # Seeker mobile (RN+Expo)
├── backend/                 # NestJS API server
├── packages/                # shared-types, shared-ui, api-client, mobile-utils
├── infrastructure/          # docker, kubernetes, terraform configs
├── db/init.sql             # PostgreSQL schema (source of truth)
└── scripts/                 # Build & deployment scripts
```

## Domains
| Service | URL | Purpose |
|---------|-----|---------|
| Business Dashboard | https://agcore.com.au | Employers manage workforce |
| Job Seeker Portal | https://myfarmjob.com | Workers search/apply |
| Public eForms | https://eform.myfarmjob.com/{uuid} | No-login employment forms |
| API | https://api.agcore.com.au | Central backend |
| Traefik | https://traefik.agcore.com.au | Reverse proxy admin |
| MinIO | https://storage.agcore.com.au | File storage admin |

## Tech Stack
**Frontend**: React 18, Vite, CSS Variables, React Query, React Hook Form, React Router
**Mobile**: React Native + Expo, React Navigation, NativeWind (Tailwind for RN)
**Backend**: NestJS (Node/TS), TypeORM, JWT w/ refresh tokens, class-validator
**Database**: PostgreSQL 16 + PostGIS, extensions: uuid-ossp, pgcrypto, pg_trgm
**Cache**: Redis 7
**Infrastructure**: Docker + Compose, Traefik v3 (Let's Encrypt), MinIO, Kubernetes (prod)

## GitHub
Your primary method for interacting with GitHub should be the GitHub CLI.

## Git
When creating brances, prefix them with sven/ to indicate they came from me.

## Quick Start
```bash
# Build and start all services
cd infrastructure/docker
docker-compose --env-file ../../.env build
docker-compose --env-file ../../.env up -d
docker-compose ps  # verify healthy
```

## Port Mapping
Docker ports offset to allow simultaneous local dev:

| Service | Docker | Local Dev | Container |
|---------|--------|-----------|-----------|
| PostgreSQL | 5433 | 5432 | 5432 |
| Redis | 6380 | 6379 | 6379 |
| API | 3100 | 3000 | 3000 |
| AgCore Web | 3101 | 3001 | 3001 |
| MyFarmJob Web | 3102 | 3002 | 3002 |
| eForm Web | 3103 | 3003 | 3003 |
| MinIO API/Console | 9000/9001 | - | 9000/9001 |

**Local dev**: Use `backend/.env.local` which configures localhost instead of Docker hostnames

## Database

### MCP Tools
- **pg-aiguide** (planning): `/pg:design-postgres-tables`, `semantic_search_postgres_docs` - research best practices before implementation
- **postgres-mcp** (execution): queries, schema inspection, index analysis, migrations

### DB Change Workflow
1. **Plan** w/ pg-aiguide - research optimal patterns, data types, indexes
2. **Verify** current state w/ postgres-mcp - check existing structures/dependencies
3. **Create migration**: `db/migrations/YYYYMMDD_description.sql` with forward/rollback sections
4. **Update baseline**: Apply changes to `db/init.sql` (single source of truth)
5. **Execute & verify** w/ postgres-mcp - run migration, validate indexes used

### Key Tables
**Core**: users (all accounts), auth_tokens (verification/reset/magic), user_sessions (JWT refresh), notifications
**Business**: businesses (w/ subscription tiers), organizations (farms), departments (shed/paddock), blocks
**Jobs**: jobs (postings), job_applications, seeker_profiles
**Workforce**: worker_assignments, time_entries (clock in/out), time_entry_edits (audit), worker_ratings, payroll_records
**eForms**: eform_templates (dynamic forms), eform_instances (shareable links), eform_submissions (w/ auto-account creation)

## Redis
Use `redis-mcp` server for all operations

### When to Use Redis vs PostgreSQL
| Use Case | Redis Key Pattern | TTL | Notes |
|----------|-------------------|-----|-------|
| Session tokens | `session:{userId}:{tokenId}` | 7d | Refresh token storage |
| Rate limiting | `ratelimit:{ip}:{endpoint}` | 1m | API throttling |
| API cache | `cache:api:{endpoint}:{hash}` | 5-60m | Job listings, profiles |
| User presence | `presence:{userId}` | 30s | Online/offline status |
| Temp data | `temp:{purpose}:{id}` | varies | OTP codes, magic links |
| Queues | `queue:{jobType}` | until processed | Email, notifications |

**Use PostgreSQL for**: permanent data, complex JOINs, ACID transactions, audit trails, full-text search, geospatial (PostGIS)

### Cache Invalidation
- Time-based (TTL), Event-based (invalidate on mutations), Pattern-based (SCAN + DEL)

## Stripe Integration
**CRITICAL**: Always check Context7 MCP for latest docs BEFORE using Stripe MCP

### Workflow
```bash
# 1. Research first (ALWAYS)
mcp__context7__resolve-library-id libraryName:"stripe"
mcp__context7__query-docs libraryId:"/stripe/stripe-node" query:"your question"

# 2. Supplement with Stripe docs
mcp__stripe__search_stripe_documentation question:"..." language:"node"

# 3. Stripe MCP operations
mcp__stripe__list_customers/products/prices/subscriptions/invoices
mcp__stripe__search_stripe_resources  # e.g. customers:email:"user@example.com"
mcp__stripe__fetch_stripe_resources   # fetch by ID
mcp__stripe__stripe_integration_recommender  # complex integration advice
```

### Products
Subscription tiers: Free, Starter, Professional, Enterprise (monthly/yearly options)
Customers linked to `businesses` table via Stripe customer ID

## Authentication Flow

### Standard Login
1. User submits email/password → backend validates against `users.password_hash`
2. Returns JWT access token (15min) + refresh token (7 days)
3. Frontend stores tokens, includes access token in API requests

### Magic Link (eForm auto-accounts)
1. User requests magic link → backend creates token in `auth_tokens` type=magic_link
2. Email sent with link → user clicks → backend validates and creates session
3. User can then set password

### Token Refresh
Access token expires 15min → frontend sends refresh token to `/auth/refresh` → new access token returned

## eForm Submission Flow
1. Employer creates 'Workplace Rules' section template in dashboard → generates shareable link (`eform_instances`)
2. Anyone accesses `eform.myfarmjob.com/{uuid}` (no login required)
3. User fills and submits form:
   - Email exists → links to existing account
   - New email → creates `job_seeker` account (password NULL, can use magic link)
   - Creates `eform_submissions`, updates `seeker_profiles`, generates PDF → MinIO
4. Employer views submissions in dashboard, can import as workers

## API Structure
```
/auth     - register, login, refresh, logout, magic-link, verify-email, reset-password
/users    - GET/PATCH /me (current user profile)
/businesses - CRUD operations, /{id}/* (business-specific ops)
/organizations - /{id}/* (org operations)
/jobs     - GET / (public search), POST / (employer create), /{id}/*
/applications - POST / (apply), /{id}/*
/time-entries - POST /clock-in, /clock-out, GET / (list)
/eforms   - GET/POST /templates (employer), GET/POST /submit/{uuid} (public)
/reports  - POST /generate (payroll, timesheet)
```

## Environment Variables
Key vars in `.env`:
- `DATABASE_URL`, `REDIS_URL` - connections
- `JWT_SECRET`, `JWT_REFRESH_SECRET` - auth
- `MINIO_ENDPOINT` - file storage
- `SMTP_*` - email config
- `STRIPE_*` - payment processing

## Styling Guidelines
- **AgCore Web**: Desktop-first, responsive down. CSS vars in `apps/agcore-web/src/styles/globals.css`
- **MyFarmJob/eForm**: Mobile-first, responsive up. Agricultural greens, earthy tones

## Visual Testing

### Quick Check (do after EVERY frontend change)
1. Navigate to changed pages: `mcp__playwright__browser_navigate`
2. Verify against `/context/design-principles.md`
3. Validate feature meets user request and acceptance criteria
4. Screenshot at 1440px desktop viewport
5. Check for errors: `mcp__playwright__browser_console_messages`

### Comprehensive Review (major UI changes, pre-PR)
```bash
@agent-design-review
```
Tests: interactive states, responsiveness (mobile/tablet/desktop), a11y (WCAG 2.1 AA), visual polish, edge cases

### Playwright MCP Commands
```javascript
mcp__playwright__browser_navigate(url)           // go to page
mcp__playwright__browser_take_screenshot()       // capture visual
mcp__playwright__browser_resize(width, height)   // test responsive
mcp__playwright__browser_click/type/hover(el)   // test interactions
mcp__playwright__browser_console_messages()     // check errors
mcp__playwright__browser_snapshot()             // a11y check
mcp__playwright__browser_wait_for(text/el)      // ensure loaded
```

### Design Checklist
- [ ] Visual hierarchy & spacing
- [ ] Consistency w/ design tokens
- [ ] Responsive: 375px, 768px, 1440px
- [ ] Keyboard nav, contrast, semantic HTML
- [ ] Loading/error/empty states
- [ ] Animations 150-300ms

## Test Credentials

Before testing rebuild/restart the docker container with the
```bash
docker-compose --env-file ../../.env down                     # stop all
docker-compose --env-file ../../.env build                     # build all
docker-compose --env-file ../../.env up -d                    # start all
```

| Platform | URL (local/docker) | Email | Password | Role |
|----------|-------------------|-------|----------|------|
| AgCore | localhost:3101 | business@test.com | Test123! | business_owner |
| MyFarmJob | localhost:3102 | seeker@test.com | Test123! | job_seeker |

## Common Commands
```bash
# Docker
docker-compose --env-file ../../.env up -d                    # start all
docker-compose --env-file ../../.env up -d --profile mobile   # include mobile dev
docker-compose --env-file ../../.env down                     # stop all
docker-compose logs -f backend          # tail logs
docker-compose exec postgres psql -U agcore_user -d agcore_db  # DB shell

# Backend
cd backend
npm run start:dev       # dev w/ hot-reload
npm run build          # prod build
npm run test           # tests
npm run migration:run  # TypeORM migrations

# Frontend
cd apps/[app-name]
npm run dev            # dev server
npm run build          # prod build
npm run preview        # preview prod
```

## Troubleshooting
- **DB connection**: `docker-compose ps postgres` / `logs postgres`. Reset: `docker-compose down -v && up -d`
- **Port conflicts**: `lsof -i :PORT` (mac/linux) or `netstat -ano | findstr :PORT` (windows)
- **Docker rebuild**: `docker-compose build --no-cache` or full reset: `docker system prune -a`

## Security
- TFN, bank details, super info encrypted at rest
- PostgreSQL RLS on sensitive tables
- Short-lived JWT (15m) + secure refresh rotation
- HTTPS via Traefik w/ Let's Encrypt
- Strict CORS origin whitelist
- All inputs validated w/ class-validator
- File uploads: type/size validation

## Plans
- At the end of each plan,give me a list of unresolved questions to answer, if any. Make the questions extremly concise. Sacrifice grammar for the sake of concision.

## Future Enhancements
- [ ] AI job matching
- [ ] IoT farm equipment integration
- [ ] QR/NFC clock-in
- [ ] Push notifications (mobile)
- [ ] Advanced analytics
- [ ] 2FA
- [ ] Audit logging

---
**Last Updated**: 2026-01-05 | **Maintained By**: Claude Code Assistant
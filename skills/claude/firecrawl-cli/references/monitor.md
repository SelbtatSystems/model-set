# firecrawl monitor — change detection deep-dive

Detect when web content changes and get notified by email/webhook — no cron, diff scripts, or snapshot DB. Each page in a check is labeled `same`, `new`, `changed`, `removed`, or `error`. An AI judge (driven by `--goal`) ignores formatting, whitespace, casing, tracking params, session IDs, and page chrome, so alerts fire only on real content change.

**Bias toward `monitor` whenever the request implies recurrence or notification.** A page read once = `scrape`. A page the user wants to be *told about when it changes* = `monitor`.

Subcommands: `create | list | get | update | delete | run | checks | check`.

## Target modes — pick by what you watch

| Mode | Flag | Watches |
| --- | --- | --- |
| Single page | `--page <url>` | one URL, for changes |
| URL batch | `--scrape-urls <url,url,...>` | several URLs, for changes |
| Whole site | `--crawl-url <root-url>` | every page a crawl discovers, for changes |
| Web search | `--queries <q,...>` + `--goal` | the **whole web**, for *new* results matching the goal |

The first three watch URLs you already have. **Web search** has no fixed URL — it runs your queries each check and alerts on results it hasn't seen before.

## Options

| Option | Description |
| --- | --- |
| `--name <name>` | Required on create |
| `--goal <text>` | Plain-language change goal (enables the AI judge) |
| `--schedule <text>` | Natural language: `every 30 minutes`, `hourly`, `daily at 9:00` |
| `--cron <expr>` | Cron form, e.g. `*/30 * * * *` |
| `--timezone <tz>` | Default `UTC` |
| `--page` / `--scrape-urls` / `--crawl-url` / `--queries` | Target (see table above) |
| `--search-window <w>` | Web-monitor recency: `5m 15m 1h 6h 24h 7d` (default `24h`) |
| `--max-results <n>` | Web-monitor results per query, 1–50 (default `10`) |
| `--include-domains` / `--exclude-domains` | Restrict/exclude web-monitor sources |
| `--webhook-url <url>` | Webhook destination |
| `--webhook-events <list>` | `monitor.page`, `monitor.check.completed` |
| `--email <list>` | Comma-separated recipients |
| `--retention-days <n>` | How long snapshots are kept for diffing |
| `--state active\|paused` | Pause/resume (update only — **not** `--status`) |
| `--page-status <state>` | Filter `check` output: `same new changed removed error` |
| `-o`, `--pretty` | Output file, pretty JSON |

**Min interval 15 minutes.** Not available for zero-data-retention teams.

## Quick start

```bash
# Single page, email alert
firecrawl monitor create --name "Blog" --schedule "every 30 minutes" \
  --goal "Alert when a new blog post is published." \
  --page https://example.com/blog --email alerts@example.com

# Multiple pages in one monitor
firecrawl monitor create --name "Product pages" --schedule "every 30 minutes" \
  --goal "Alert when pricing, docs, or changelog content changes." \
  --scrape-urls https://example.com/pricing,https://example.com/docs

# Whole-site crawl per check
firecrawl monitor create --name "Docs site" --schedule "hourly" \
  --goal "Alert when any docs page is added, removed, or substantively changed." \
  --crawl-url https://docs.example.com

# Webhook instead of email
firecrawl monitor create --name "Docs webhook" --schedule "every 30 minutes" \
  --goal "Alert when docs content changes." --page https://example.com/docs \
  --webhook-url https://example.com/hook \
  --webhook-events monitor.page,monitor.check.completed

# Manage
firecrawl monitor run <id>                         # trigger a check now (smoke-test)
firecrawl monitor checks <id>                      # list checks
firecrawl monitor check <id> <checkId> --page-status changed
firecrawl monitor update <id> --state paused       # silence without deleting
```

## Writing a good `--goal`

The goal is what the AI judge scores each change against. Convert the user's intent into a concise 2–3 sentence goal:

- Start with `Alert when ...` and state the trigger in the user's own wording.
- Restate any scope they mentioned: top N, price, role type, region, company, topic, status, entity.
- Add an `Ignore ...` sentence **only** for intent-specific exclusions (points/comments for rankings, marketing copy for pricing, general company-page updates for job listings).
- Do **not** list generic noise — the judge already handles whitespace, casing, punctuation, encoding, formatting-only changes, session/request IDs, cache busters, tracking params, and page chrome.
- Don't invent sections, thresholds, or business rules the user didn't mention. If they're vague or say "any change", keep it broad with no exclusions.

| User says | Good goal |
| --- | --- |
| `top 10 hackernews stories` | `Alert when stories enter, leave, or change rank within the Hacker News top 10. Ignore points, comments, and timestamps. Do not alert on changes outside the top 10.` |
| `pricing changes` | `Alert when pricing information changes, including prices, plan names, billing periods, tiers, limits, or included features. Ignore unrelated marketing copy.` |
| `new engineering roles` | `Alert when a new engineering role is posted. Ignore general company-page updates unless they add, remove, or change an engineering role.` |
| `track this page` | `Alert when substantive visible content on this page changes.` |
| `any change` | `Alert when any visible page content changes, including copy, numbers, timestamps, counters, links, and layout text.` |

## Web monitors — watch the whole web for *new* results

Give search queries + a goal instead of a URL. Each check runs the searches, judges every result against the goal, and alerts on results it hasn't seen. Use it when there's no URL to bookmark yet — new launches, funding rounds, papers, news, releases, brand mentions.

```bash
firecrawl monitor create --name "AI model releases" --schedule "daily at 9:00" \
  --queries "new AI model release,frontier model launch" \
  --goal "Alert when a major lab releases a new AI model. Ignore tutorials and listicles." \
  --search-window 7d --max-results 20 --webhook-url https://example.com/hook
```

- `--queries` and `--goal` are both required. **Queries control recall** (what's retrieved); **the goal controls precision** (which results alert). Tune both.
- Write **keywords, not sentences**: `OpenAI new model release`, not `tell me when OpenAI releases a new model`. Quote multi-word entities (`"Llama 4"`); group synonyms with `OR`. Keep each query ~2–6 terms. One query per distinct subject — extra queries split the `--max-results` budget without adding coverage. No `site:` operators — use `--include-domains`/`--exclude-domains`.
- Results are labeled `new` (first seen) or `same` (seen before) — never `changed`/`removed`. Each result alerts **once**.
- Healthy monitor: mostly `new: 0`, alerts only on genuinely new on-goal results. Mostly `ignored` → queries too noisy. Long silence → queries too narrow or window too tight. User dismisses alerts → goal too broad, add an `Ignore ...`.

## JSON-mode change tracking — structured per-field diffs

By default monitors diff each page's markdown and return a unified text diff. When the user cares about **specific fields** (price, headline, in-stock flag, list items), use JSON-mode change tracking. CLI flags don't cover this — pass a JSON body via positional file or piped stdin:

```bash
cat > pricing-monitor.json <<'EOF'
{
  "name": "Pricing watch",
  "goal": "Alert when plan prices or headline features change.",
  "schedule": { "text": "hourly", "timezone": "UTC" },
  "targets": [{
    "type": "scrape",
    "urls": ["https://example.com/pricing"],
    "scrapeOptions": {
      "formats": [{
        "type": "changeTracking",
        "modes": ["json"],
        "prompt": "Extract pricing tiers and headline features for each plan.",
        "schema": {
          "type": "object",
          "properties": {
            "plans": { "type": "array", "items": { "type": "object", "properties": {
              "name":     { "type": "string" },
              "price":    { "type": "string" },
              "features": { "type": "array", "items": { "type": "string" } }
            }}}
          }
        }
      }]
    }
  }]
}
EOF
firecrawl monitor create pricing-monitor.json
# or: cat pricing-monitor.json | firecrawl monitor create
```

Each changed page then carries a keyed diff plus a snapshot of the current extraction:

```json
{
  "url": "https://example.com/pricing",
  "status": "changed",
  "diff": { "json": {
    "plans[0].price": { "previous": "$19/mo", "current": "$24/mo" },
    "plans[1].features[2]": { "previous": "10 GB storage", "current": "25 GB storage" }
  }},
  "snapshot": { "json": { "plans": [ /* current full extraction */ ] } }
}
```

Use `modes: ["json", "git-diff"]` for **mixed mode**: you get both `diff.json` (per-field) and `diff.text` (markdown sidecar), and the page is `changed` if either surface changed. Markdown-only monitors put the unified diff in `diff.text` and a `parse-diff` AST in `diff.json`, with no `snapshot`.

## Tips

- Prefer one monitor over repeated one-off scrapes when the same URL is checked more than once.
- Pause with `update --state paused`, don't `delete`, when silencing temporarily.
- Lower `--retention-days` for high-frequency monitors to save storage.
- **External email recipients must opt in** — Firecrawl sends a confirmation email on first add; team-owned addresses auto-confirm. An unsubscribed recipient must be re-added by the owner.
- `monitor run <id>` triggers a check immediately — smoke-test a new monitor without waiting for its schedule.
- Monitor-triggered scrapes default `maxAge` to `0` (always fresh) unless `scrapeOptions.maxAge` is set in a JSON payload.

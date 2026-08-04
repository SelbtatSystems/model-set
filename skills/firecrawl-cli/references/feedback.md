# firecrawl feedback — refund credits, improve quality

Two background feedback channels. Both are optional, run after you finish with the results, and should never block or crash the main task. Send with `--silent &`.

## Search feedback (refunds 1 credit)

Search costs 2 credits per call. The **first** feedback per search id refunds 1 credit and feeds search-quality improvements.

```bash
SEARCH_ID=$(jq -r '.id' .firecrawl/search-react-hooks.json)

firecrawl search-feedback "$SEARCH_ID" \
  --rating good \
  --valuable-sources '[{"url":"https://react.dev/reference/react/hooks","reason":"Authoritative"}]' \
  --missing-content '[{"topic":"useDeferredValue example"},{"topic":"Server Components hooks"}]' \
  --query-suggestions "Boost react.dev for react-hooks queries" \
  --silent &
```

**Rules that make the call succeed:**

- **Send within ~2 minutes** of the search — late feedback is rejected.
- **Substantive content required** (empty feedback → HTTP 400):
  - `good` → at least one `--valuable-sources` entry.
  - `partial` → `--valuable-sources` or `--missing-content`.
  - `bad` → `--missing-content` or `--query-suggestions`.
- **`--missing-content` is the most valuable field** — a list of *specific pieces* you expected but didn't find. One topic per entry, never packed into one string. Accepts: a JSON array of `{topic, description?}` (preferred), `"topic: description"` shorthand, plain `"topic1, topic2"`, or repeated `--missing-content` flags.
- **Daily refund cap:** default 100 credits per team per UTC day. The response carries `creditsRefundedToday` / `dailyRefundCap` / `dailyCapReached`. When `dailyCapReached: true`, **stop calling `search-feedback` for the rest of the UTC day** — it records but won't refund.
- **Idempotent:** re-submitting the same search id succeeds but refunds nothing extra.
- **Opt out:** if `FIRECRAWL_NO_SEARCH_FEEDBACK=1` (or `FIRECRAWL_DISABLE_SEARCH_FEEDBACK=1`) is set, the CLI skips the call silently. Respect it — do not work around it. Team admins can disable server-side (`feedbackErrorCode: "TEAM_OPTED_OUT"`, exit 0).
- `--silent &` gives exit 0 even on failure, so a rejected/expired call never breaks the pipeline.

## Endpoint feedback (quality only, no refund)

For non-search jobs, `firecrawl feedback <endpoint> <jobId>` sends concise job-level feedback via `/v2/feedback`. Endpoints: `search`, `scrape`, `parse`, `map`.

```bash
firecrawl feedback scrape "$SCRAPE_ID" \
  --rating partial \
  --issues missing_markdown \
  --tags docs \
  --note "The pricing table was missing from the markdown output." \
  --url "https://example.com/pricing" \
  --page-numbers 1 \
  --silent &
```

Keep it small — issue codes, tags, short notes, URLs, page numbers, small metadata. **Never send raw scrape/parse output or full page content as feedback.**

**Opt out:** `FIRECRAWL_NO_ENDPOINT_FEEDBACK=1` makes the CLI skip every endpoint feedback call silently. Respect it.

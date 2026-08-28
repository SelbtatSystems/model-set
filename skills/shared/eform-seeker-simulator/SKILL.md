---
name: eform-seeker-simulator
description: Simulate a job seeker filling and submitting the public eForm (wage employment agreement) in the AgCore worktree the agent is currently running from, with a random persona — any residency/visa type or Australian national, TFN or pending TFN — then verify submission, PDF generation, employer review visibility, and magic-link account setup via agent-browser, and record the new seeker in memory/AgCore/TEST-LOGIN.md. Use when the user wants to fill in or test the eForm, generate a random seeker submission, simulate a visa holder or Australian citizen, verify the eForm→review→magic-link→account pipeline, or run a seeker through the employment form end-to-end.
---

# eForm Seeker Simulator

Drive the public eForm in the **current AgCore worktree's Docker stack** end-to-end as a freshly invented job seeker — a **persona** generated each run — then prove the submission landed: backend logs show the submission, identity resolution, and compliance-PDF generation; the exact employer Organisation sees it in Review Submissions; the magic link reaches the seeker's MyFarmJob account; and the new credentials land in `memory/AgCore/TEST-LOGIN.md`.

The eForm is a **public, login-free** 12-step wage agreement. AU citizens skip the Visa step; everyone else uploads ID + visa documents. The backend emails a **magic link** (logged to the console in dev, never sent) that lets the seeker set a password and sign in.

## Step 0 — Resolve the current worktree (always first)

Run from the AgCore checkout/worktree named in the session:

```bash
<skill-dir>/scripts/resolve-worktree-runtime.sh
```

Record its `repo_root`, `backend_url`, `agcore_url`, `eform_url`, `myfarmjob_url`, and `test_docs_dir` output. Use these values throughout the run. Never infer a port offset from the worktree name and never reuse a URL from another checkout. The gitignored Compose override is the authority.

If the user names an Organisation, resolve it by **exact legal name** in this worktree:

```bash
<skill-dir>/scripts/resolve-eform-links.sh "<exact legal name>"
```

Use the returned live link. If it returns multiple named eForms, stop and ask which named eForm to submit; do not guess. A user-supplied Organisation or link overrides `TEST-LOGIN.md`.

**Completion criterion:** every URL belongs to the current worktree's Compose project, and the exact requested Organisation + ABN are recorded before opening the browser.

## Prerequisites (verify before starting)

1. **Docker stack healthy** — `resolve-worktree-runtime.sh` must find running `backend`, `agcore-web`, `myfarmjob-eform-web`, and `myfarmjob-web` services and their published ports. If any is down, stop and name the current worktree and missing service. No fallback stack.
2. **eForm link present** — use the user override resolved in Step 0. Otherwise read `<repo>/memory/AgCore/TEST-LOGIN.md` and use only the identifier from `test-link.eform-test`; discard any stored host/port and reconstruct the URL with this run's `eform_url`. Validate that it resolves in the current worktree. If it does not, stop and ask for a live link in this worktree.
3. **Test documents present** — `<test_docs_dir>/` must contain `Test-Passport.jpg`, `Test-AU-visa-letter.pdf`, `Test-AU-ID.png`, `Test-Work-Permit.pdf`. If any are missing, stop and tell the user.

**Completion criterion:** all three checks pass before any browser action. One missing → stop, name it.

## Workflow

### Step 1 — Generate the persona

Load [`references/persona-generator.md`](references/persona-generator.md) and build a complete persona: residency status, visa subclass + nationality (if non-citizen), TFN status, super, bank, emergency contact, medical, experience, and declarations. Apply any **user override** from the prompt verbatim (e.g. "make an AU citizen with Pending TFN", "use subclass 417", "a WHM from Brazil") — override wins over the random draw; everything not overridden is random.

Generate the TFN value with `scripts/gen-tfn.py` (prints one checksum-valid 9-digit TFN) when the persona's TFN status is `Yes`. Never use TFN status `No` — it blocks the form (super step rejects).

Write the full persona down (name, email, every field value, the residency path taken) before touching the browser. **Completion criterion:** every field the form will ask for has a decided value; the residency path (citizen vs visa-holder) is fixed.

### Step 2 — Start the backend log window

Record the start time and choose a temporary output file. This avoids fragile detached log-tail processes that some agent runners reap when a shell command returns:

```bash
STARTED_AT="$(date --iso-8601=seconds)"
LOGFILE="/tmp/eform-sim-backend-$(date +%s).log"
```

After submission, Step 5 captures this worktree backend's logs since `STARTED_AT`.

**Completion criterion:** both values are recorded before the first browser request.

### Step 3 — Open the form with a clean session

A **draft cookie** (HttpOnly, same-device) can silently restore a half-filled form and skip forward over fields. Defeat it: use a fresh agent-browser session for this run and do not restore saved state.

```bash
SESSION="$(agent-browser session id --scope worktree --prefix eform-seeker-simulator)-$(date +%s)"
agent-browser --session "$SESSION" open "<resolved-eform-url>"
agent-browser --session "$SESSION" wait --load networkidle
agent-browser --session "$SESSION" snapshot -i
```

Confirm the landing/Home page rendered the **exact requested legal name + ABN**, not merely a similar Organisation, and not a "Form Not Found" 404 or "not yet available" 409. A mismatch is a failed prerequisite: stop rather than submitting to the wrong legal entity. If it 404s, the identifier is dead in this worktree — stop and tell the user to republish the eForm link. No fallback stacks.

Click the **"Complete Employee eForm"** CTA to reach Step 1 (Introduction). **Completion criterion:** the Introduction heading is visible; no draft-restore banner carried over.

### Step 4 — Drive the 12 steps

Load [`references/form-field-map.md`](references/form-field-map.md). For **each step**: `agent-browser snapshot -i` → match the snapshot's `@eN` refs to the field labels listed → fill/select/check/upload by ref → click the primary action button ("Continue to Application" → "Next" → … → "Review Application" → "Submit Form"). Re-snapshot after every page change — refs go stale on navigation.

Rules that catch agents:
- **Citizens (AU_CITIZEN):** Step 8 (Visa) is skipped; instead Step 3 shows a right-to-work block. Set `rightToWorkDoc = Australian birth certificate + photo ID` (value `BIRTH_CERT_PHOTO_ID`), upload `Test-AU-ID.png` → `rightToWorkDocFile` and `Test-Work-Permit.pdf` → `rightToWorkPhotoIdFile`, check the right-to-work declaration. No expiry date needed for this doc type.
- **Visa holders (PERMANENT_RESIDENT / NZ_CITIZEN / WHM / OTHER_VISA):** Step 8 appears. Upload `Test-Passport.jpg` → `idDocument` and `Test-AU-visa-letter.pdf` → `visaCopy`. If the chosen visa subclass has no expiry date (e.g. 866, 189), the expiry field is hidden — do not fill it.
- **File uploads** use absolute paths under this run's `<test_docs_dir>`, for example `agent-browser --session "$SESSION" upload @eN <test_docs_dir>/Test-Passport.jpg`. Draft files are persisted by separate requests: after **each** upload, run `agent-browser --session "$SESSION" wait --load networkidle` before uploading another file. Never batch two upload commands; concurrent draft writes can race and retain only one file.
- **Medical details** (when answer is `yes`) need ≥ 15 characters.
- **Super:** `hasSuper` must be `Yes`. WHM and OTHER_VISA get APRA only (SMSF hidden). Pick a known APRA fund so the ABN auto-fills.
- **Step 12 (Review):** check `allInfoCorrect` before the submit button un-disables, then click "Submit Form".

**Completion criterion:** the success screen reads "Submission received" (legacy copy: "Application submitted successfully!") — not a field-error jump-back, not a 400/404/409.

### Step 5 — Verify in the backend logs

Capture the log window, then load [`references/verification.md`](references/verification.md):

```bash
<skill-dir>/scripts/capture-backend-logs.sh "$STARTED_AT" "$LOGFILE"
```

Grep that file for, in order:
1. Submission accepted (the submitter email or the "Form submitted successfully" line).
2. Identity `match_method` — expect `new_user` for a fresh email (the magic link only fires for `new_user` or an existing user with no password).
3. Compliance-PDF generation (an `eform-submissions/<id>/<orgId>.pdf` path or the pdf-generator log line).
4. The magic link: a `[DEV MODE] Email to <persona-email>` block whose `HTML:` line contains `https://myfarmjob.com/auth/setup-password?token=<token>`. Extract the full URL with the regex in the reference.

If the magic-link URL is missing, the persona email matched an existing claimed account (no magic link sent) — the run still succeeded but cannot complete account setup. Record the submission, flag "no magic link (email already claimed)" in the report, and skip Step 6.

**Completion criterion:** submission + identity + PDF all present in logs; the magic-link URL is captured (or its absence is explained and recorded).

### Step 6 — Redeem the magic link and set the password

The dev magic link is hardcoded to `https://myfarmjob.com/auth/setup-password?token=...`, which does not resolve locally. **Rewrite only the host** to this run's `<myfarmjob_url>` (keep path + token), then drive the MyFarmJob setup-password page in the **same browser session**:

```bash
agent-browser --session "$SESSION" open "<myfarmjob_url>/auth/setup-password?token=<token>"
agent-browser --session "$SESSION" wait --load networkidle
agent-browser --session "$SESSION" snapshot -i
# fill the "password" and "confirmPassword" inputs with the dev test password
agent-browser --session "$SESSION" fill <passwordRef> "Test123!"
agent-browser --session "$SESSION" fill <confirmRef>   "Test123!"
agent-browser --session "$SESSION" click <submitButton>           # "Create password & Sign in"
agent-browser --session "$SESSION" wait --text "You're all set!"
```

`Test123!` is the dev test password (meets the regex `(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])`, min 8) and matches the existing `memory/AgCore/TEST-LOGIN.md` convention. The page auto-redirects to `/` after ~2 s. Record the worktree-specific `<myfarmjob_url>` in the seeker entry.

**Completion criterion:** `agent-browser get url` returns a seeker dashboard route (not `/auth/setup-password`, not `/auth/login`); `snapshot -i` shows authenticated seeker UI, not a login form.

### Step 7 — Verify employer review visibility and record the seeker

Open `<agcore_url>/workforce/eform-qr` in an authenticated employer browser session, select the exact Organisation recorded in Step 0, and locate the new submitter in **Review Submissions**. Confirm the displayed status matches the backend review row. If browser authentication is needed, use the AgCore dev credentials from `<repo>/memory/AgCore/TEST-LOGIN.md`; never switch to another stack just because it already has a logged-in session.

Append one entry to the `eform-seekers` array in `<repo>/memory/AgCore/TEST-LOGIN.md` (schema + the exact edit in [`references/verification.md`](references/verification.md)). One entry per run — never overwrite. Then close the agent-browser session.

**Completion criterion:** the exact Organisation's Review Submissions UI shows the new submission in this worktree, `memory/AgCore/TEST-LOGIN.md` parses, the new entry is present, and the browser session is closed.

## Edge cases the persona generator must cover

- **TFN `Pending`** — no TFN value is sent; a yellow "provide within 28 days" notice shows. The review screen reflects `pending` (any TFN typed then switched to Pending is discarded — never send both).
- **Citizen with no visa** — the Visa step is absent; uploads land on the right-to-work fields instead. Two files, not one ID + one visa.
- **No-expiry visa subclass** (866, 189, 190, 191, 192, 801, 100, …) — the expiry-date input is hidden behind a "does not have an expiry date" notice; do not fill it.
- **WHM regional-work notice** — informational only; no field to fill.

## Report

After Step 7, give the user a concise summary: worktree + resolved ports, exact Organisation legal name + ABN, persona (name, email, residency, visa subclass, nationality, TFN status), submission ID, whether the PDF was generated, whether Review Submissions displayed it, whether the magic link was redeemed, and the new `memory/AgCore/TEST-LOGIN.md` entry. Flag any log anomaly or skipped step.

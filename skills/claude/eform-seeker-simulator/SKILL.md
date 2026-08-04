---
name: eform-seeker-simulator
description: Simulate a job seeker filling and submitting the public eForm (wage employment agreement) at localhost:3103 with a random persona — any residency/visa type or Australian national, TFN or pending TFN — then verify submission, PDF generation, and magic-link account setup via agent-browser, and record the new seeker in memory/AgCore/TEST-LOGIN.md. Use when the user wants to fill in or test the eForm, generate a random seeker submission, simulate a visa holder or Australian citizen, verify the eForm→magic-link→account pipeline, or run a seeker through the employment form end-to-end.
---

# eForm Seeker Simulator

Drive the public eForm at `http://localhost:3103` end-to-end as a freshly invented job seeker — a **persona** generated each run — then prove the submission landed: backend logs show the submission, identity resolution, and compliance-PDF generation; the magic link reaches the seeker's MyFarmJob account; and the new credentials land in `memory/AgCore/TEST-LOGIN.md`.

The eForm is a **public, login-free** 12-step wage agreement. AU citizens skip the Visa step; everyone else uploads ID + visa documents. The backend emails a **magic link** (logged to the console in dev, never sent) that lets the seeker set a password and sign in.

## Prerequisites (verify before starting)

1. **Docker stack healthy** — `backend` and `myfarmjob-eform-web` containers up on host ports `3100` and `3103`; `myfarmjob-web` on `3104`. If any is down, stop and tell the user to bring the stack up (`dc build && dc up -d`). No fallback hosts — `localhost` only.
2. **eForm link present** — read `<repo>/memory/AgCore/TEST-LOGIN.md` and look for `test-link.eform-test`. It holds the full eForm URL (e.g. `http://localhost:3103/<identifier>`) or just the `<identifier>`. If the key is missing, stop and tell the user to add it.
3. **Test documents present** — `<repo>/test-docs/` must contain `Test-Passport.jpg`, `Test-AU-visa-letter.pdf`, `Test-AU-ID.png`, `Test-Work-Permit.pdf`. If any are missing, stop and tell the user.

**Completion criterion:** all three checks pass before any browser action. One missing → stop, name it.

## Workflow

### Step 1 — Generate the persona

Load [`references/persona-generator.md`](references/persona-generator.md) and build a complete persona: residency status, visa subclass + nationality (if non-citizen), TFN status, super, bank, emergency contact, medical, experience, and declarations. Apply any **user override** from the prompt verbatim (e.g. "make an AU citizen with Pending TFN", "use subclass 417", "a WHM from Brazil") — override wins over the random draw; everything not overridden is random.

Generate the TFN value with `scripts/gen-tfn.py` (prints one checksum-valid 9-digit TFN) when the persona's TFN status is `Yes`. Never use TFN status `No` — it blocks the form (super step rejects).

Write the full persona down (name, email, every field value, the residency path taken) before touching the browser. **Completion criterion:** every field the form will ask for has a decided value; the residency path (citizen vs visa-holder) is fixed.

### Step 2 — Start the backend log tail

Run `scripts/tail-backend-logs.sh` — it prints `<logfile> <pid>`. The log captures everything the backend emits from now on; the PID is killed at the end. Keep both for the verification step.

**Completion criterion:** a log file exists and is growing (confirm with one `wc -l` after a few seconds); the PID is recorded for cleanup.

### Step 3 — Open the form with a clean session

A **draft cookie** (HttpOnly, same-device) can silently restore a half-filled form and skip forward over fields. Defeat it: open a fresh browser session — do not load saved state, clear cookies for `localhost:3103` if any persist.

```bash
agent-browser open "<eform-url>"            # the URL from memory/AgCore/TEST-LOGIN.md test-link.eform-test
agent-browser wait --load networkidle
agent-browser snapshot -i
```

Confirm the landing/Home page rendered the org context (legal name + ABN visible), not a "Form Not Found" 404 or "not yet available" 409. If it 404s, the identifier is dead — stop and tell the user to republish the eForm link. No fallback hosts.

Click the **"Complete Employee eForm"** CTA to reach Step 1 (Introduction). **Completion criterion:** the Introduction heading is visible; no draft-restore banner carried over.

### Step 4 — Drive the 12 steps

Load [`references/form-field-map.md`](references/form-field-map.md). For **each step**: `agent-browser snapshot -i` → match the snapshot's `@eN` refs to the field labels listed → fill/select/check/upload by ref → click the primary action button ("Continue to Application" → "Next" → … → "Review Application" → "Submit Form"). Re-snapshot after every page change — refs go stale on navigation.

Rules that catch agents:
- **Citizens (AU_CITIZEN):** Step 8 (Visa) is skipped; instead Step 3 shows a right-to-work block. Set `rightToWorkDoc = Australian birth certificate + photo ID` (value `BIRTH_CERT_PHOTO_ID`), upload `Test-AU-ID.png` → `rightToWorkDocFile` and `Test-Work-Permit.pdf` → `rightToWorkPhotoIdFile`, check the right-to-work declaration. No expiry date needed for this doc type.
- **Visa holders (PERMANENT_RESIDENT / NZ_CITIZEN / WHM / OTHER_VISA):** Step 8 appears. Upload `Test-Passport.jpg` → `idDocument` and `Test-AU-visa-letter.pdf` → `visaCopy`. If the chosen visa subclass has no expiry date (e.g. 866, 189), the expiry field is hidden — do not fill it.
- **File uploads** use absolute paths: `agent-browser upload @eN /home/sven/Projects/AgCore/test-docs/Test-Passport.jpg`.
- **Medical details** (when answer is `yes`) need ≥ 15 characters.
- **Super:** `hasSuper` must be `Yes`. WHM and OTHER_VISA get APRA only (SMSF hidden). Pick a known APRA fund so the ABN auto-fills.
- **Step 12 (Review):** check `allInfoCorrect` before the submit button un-disables, then click "Submit Form".

**Completion criterion:** the success screen reads "Application submitted successfully!" — not a field-error jump-back, not a 400/404/409.

### Step 5 — Verify in the backend logs

Load [`references/verification.md`](references/verification.md). Grep the tail log for, in order:
1. Submission accepted (the submitter email or the "Form submitted successfully" line).
2. Identity `match_method` — expect `new_user` for a fresh email (the magic link only fires for `new_user` or an existing user with no password).
3. Compliance-PDF generation (an `eform-submissions/<id>/<orgId>.pdf` path or the pdf-generator log line).
4. The magic link: a `[DEV MODE] Email to <persona-email>` block whose `HTML:` line contains `https://myfarmjob.com/auth/setup-password?token=<token>`. Extract the full URL with the regex in the reference.

If the magic-link URL is missing, the persona email matched an existing claimed account (no magic link sent) — the run still succeeded but cannot complete account setup. Record the submission, flag "no magic link (email already claimed)" in the report, and skip Step 6.

**Completion criterion:** submission + identity + PDF all present in logs; the magic-link URL is captured (or its absence is explained and recorded).

### Step 6 — Redeem the magic link and set the password

The dev magic link is hardcoded to `https://myfarmjob.com/auth/setup-password?token=...`, which does not resolve locally. **Rewrite the host** to `http://localhost:3104` (keep path + token), then drive the MyFarmJob setup-password page in the **same browser session**:

```bash
agent-browser open "http://localhost:3104/auth/setup-password?token=<token>"
agent-browser wait --load networkidle
agent-browser snapshot -i
# fill the "password" and "confirmPassword" inputs with the dev test password
agent-browser fill <passwordRef> "Test123!"
agent-browser fill <confirmRef>   "Test123!"
agent-browser click <submitButton>           # "Create password & Sign in"
agent-browser wait --text "You're all set!"
```

`Test123!` is the dev test password (meets the regex `(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])`, min 8) and matches the existing `memory/AgCore/TEST-LOGIN.md` convention. The page auto-redirects to `/` after ~2 s.

**Completion criterion:** `agent-browser get url` returns a seeker dashboard route (not `/auth/setup-password`, not `/auth/login`); `snapshot -i` shows authenticated seeker UI, not a login form.

### Step 7 — Record the seeker

Append one entry to the `eform-seekers` array in `<repo>/memory/AgCore/TEST-LOGIN.md` (schema + the exact edit in [`references/verification.md`](references/verification.md)). One entry per run — never overwrite. Then kill the log-tail PID from Step 2.

**Completion criterion:** `memory/AgCore/TEST-LOGIN.md` parses, the new entry is present, and the background log process is killed.

## Edge cases the persona generator must cover

- **TFN `Pending`** — no TFN value is sent; a yellow "provide within 28 days" notice shows. The review screen reflects `pending` (any TFN typed then switched to Pending is discarded — never send both).
- **Citizen with no visa** — the Visa step is absent; uploads land on the right-to-work fields instead. Two files, not one ID + one visa.
- **No-expiry visa subclass** (866, 189, 190, 191, 192, 801, 100, …) — the expiry-date input is hidden behind a "does not have an expiry date" notice; do not fill it.
- **WHM regional-work notice** — informational only; no field to fill.

## Report

After Step 7, give the user a concise summary: the persona (name, email, residency, visa subclass, nationality, TFN status), the submission ID if extractable, whether the PDF was generated, whether the magic link was redeemed, and the new `memory/AgCore/TEST-LOGIN.md` entry. Flag any log anomaly or skipped step.

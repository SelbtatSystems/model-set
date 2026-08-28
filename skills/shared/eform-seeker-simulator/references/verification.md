# Verification

After "Submission received" (legacy copy: "Application submitted successfully!") appears, capture the backend log window started in Step 2, prove the submission landed end-to-end, then redeem the magic link and record the seeker. All of this happens in dev — emails are **logged, never sent**.

## 1. Read the backend log

The tail started in Step 2 wrote to the file printed by `scripts/tail-backend-logs.sh`. Grep it in this order:

```bash
# 1a. Submission + identity + magic-link email (the dev-mode email block):
grep -nE "<persona-email>|DEV MODE|setup-password\?token=" <logfile>

# 1b. Compliance PDF generation:
grep -nE "eform-submissions/|pdf" <logfile>

# 1c. Identity match method (if logged):
grep -niE "match_method|identity|new_user|email_conflict|email_strong|email_only_no_dob|identity_cross" <logfile>
```

What each hit means:
- **`[DEV MODE] Email to <persona-email>`** followed by `Subject:` and `HTML:` lines — the seeker confirmation email. The `HTML:` line contains the magic link. This is the single highest-signal confirmation: submission accepted, identity resolved, and (if the link is present) a magic link was issued.
- **`eform-submissions/<submissionId>/<orgId>.pdf`** — the compliance PDF was generated and stored in MinIO.
- **`match_method` / `new_user`** — identity resolution path. Expect `new_user` for a fresh `<first>.<last>.<hex>@test.com` email; that's the only path that issues a magic link (the user has no password yet). Other methods (`email_strong`, `email_only_no_dob`) send a magic link only if the matched user has no password; `email_conflict` and `identity_cross` send none.

### Extract the magic link

The `HTML:` log line renders the link twice (as an `<a href="…">` and a plain-text copy). Pull the raw URL:

```
https://myfarmjob\.com/auth/setup-password\?token=[a-f0-9]+
```

Use the first match. The token is 64 lowercase hex chars (32 random bytes). Capture the full `https://myfarmjob.com/auth/setup-password?token=<token>` string.

### If the magic link is absent

No `[DEV MODE] Email to <persona-email>` block, or the block has no `setup-password` link → the email matched an existing **claimed** account (`email_conflict` or `identity_cross`, or an existing user with a password). The submission still succeeded. Record it, flag **"no magic link — email already claimed"** in the report, and **skip Step 6** (account setup). Do not stop the run on this — it's a valid outcome, just one without account setup to verify.

## 2. Redeem the magic link

The dev magic link is hardcoded to `https://myfarmjob.com/auth/setup-password?token=<token>` (`backend/src/eforms/eform-submission.service.ts:1527`), which does not resolve locally. **Rewrite the host** to the current worktree's `<myfarmjob_url>` from Step 0:

```
https://myfarmjob.com  →  <myfarmjob_url>
```

Keep the path and token exactly. The rewritten URL: `<myfarmjob_url>/auth/setup-password?token=<token>`.

Open it in the **same browser session** (so the cookies set on submit persist) and drive the setup-password page:

```bash
agent-browser --session "$SESSION" open "<myfarmjob_url>/auth/setup-password?token=<token>"
agent-browser --session "$SESSION" wait --load networkidle
agent-browser --session "$SESSION" snapshot -i
# @e? input name="password"  →  fill "Test123!"
# @e? input name="confirmPassword"  →  fill "Test123!"
# button "Create password & Sign in"  →  click
agent-browser --session "$SESSION" wait --text "You're all set!"
```

- The dev test password is **`Test123!`** (satisfies the backend regex `(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])`, min 8 max 128) and matches the existing `memory/AgCore/TEST-LOGIN.md` convention.
- If the page shows "Invalid Link" / "This setup link is invalid or has expired" instead of the form, the token was already used or expired (1-hour window). Re-submitting the eForm issues a fresh one — but that creates a duplicate submission. Prefer to stop and report the expired token rather than re-submit.

## 3. Confirm the seeker is authenticated

The success page auto-redirects to `/dashboard` (~2 s). Verify:

```bash
agent-browser --session "$SESSION" wait --url "**/dashboard"
agent-browser --session "$SESSION" get url       # expect <myfarmjob_url>/dashboard, NOT /auth/setup-password or /auth/login
agent-browser --session "$SESSION" snapshot -i   # expect authenticated seeker UI, not a login form
```

If the URL still contains `/auth/setup-password` or bounces to `/auth/login`, account setup failed — report the exact URL and the snapshot.

## 4. Record the seeker in memory/AgCore/TEST-LOGIN.md

Append **one entry per run** to the `eform-seekers` array in `<repo>/memory/AgCore/TEST-LOGIN.md`. Use the `edit` tool (string replacement) so the existing `//` comments are preserved — do not rewrite the whole file.

### Entry shape

```json
{
  "email": "<persona email>",
  "password": "Test123!",
  "firstName": "<first>",
  "lastName": "<last>",
  "residencyStatus": "AU_CITIZEN|PERMANENT_RESIDENT|NZ_CITIZEN|WHM|OTHER_VISA",
  "visaSubclass": "<3-digit code or null for citizens>",
  "nationality": "<for non-citizens, or null>",
  "tfnStatus": "Yes|Pending",
  "magicLinkUrl": "https://myfarmjob.com/auth/setup-password?token=<token>",
  "magicLinkRedeemed": true,
  "loginUrl": "<myfarmjob_url>/auth/login",
  "submissionId": "<id if extractable from logs, else null>",
  "pdfGenerated": true,
  "createdAt": "<ISO 8601 UTC>"
}
```

### First run — the array does not exist yet

The file has `//` comments (invalid JSON), so use the `edit` tool (string replacement) to preserve them. The last valid key is `test-link` (its closing `}` has no trailing comma — it sits just before the `//"admin-web"` comment block). Read the file, copy the exact current text of the `test-link` block as the `oldString`, and replace it with itself plus a comma and the new array. For example, given the current file:

**oldString** (copy the exact text from the read — the URL is user-set, do not hardcode it):
```
  "test-link": {
    "eform-test" : "http://localhost:<eform-port>/<identifier>"
  }
```

**newString:**
```
  "test-link": {
    "eform-test" : "http://localhost:<eform-port>/<identifier>"
  },
  "eform-seekers": [
    <ENTRY>
  ]
```

(Replace `<ENTRY>` with the actual JSON object above, indented four spaces. The only structural change is adding `,` after the `test-link` closing `}` and the new array — the `//` comments below are untouched.)

### Subsequent runs — the array already exists

Insert `,\n    <ENTRY>` immediately before the `]` that closes the `eform-seekers` array. Find the unique closing by including the last entry's closing brace in the `oldString`, e.g. if the last entry ends `  ]`, match the final entry's tail + the `]` and replace with the same tail + `,\n    <ENTRY>\n  ]`. Never overwrite existing entries — append only.

After the edit, confirm the file still parses as JSON after stripping its Markdown fences and `//` comment lines.

## 5. Clean up

Close the run's agent-browser session. Leave the log file in `/tmp` (useful for the report; it's outside the repo). Do not commit `memory/AgCore/TEST-LOGIN.md` — the user commits when ready.

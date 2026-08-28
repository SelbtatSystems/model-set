# Form Field Map

The 12-step wage eForm. For each step: `agent-browser snapshot -i`, match the snapshot's `@eN` refs to the labels below, act, then click the primary button and re-snapshot. Refs are reassigned every snapshot — never carry a ref across a navigation.

Labels are quoted from the English bundle (`apps/myfarmjob-eForm-web/src/contexts/translation-bundles/en.ts`); the snapshot shows them as element text. Field **values** are the persona's (see `persona-generator.md`); the *option values* below are what `select`/radio need.

## Step 1 — Introduction

- No inputs. Click **"Continue to Application"**.

## Step 2 — Residency & work rights

- `residencyStatus` radio — click the option whose label matches the persona:
  - `Australian citizen` → `AU_CITIZEN`
  - `Permanent resident` → `PERMANENT_RESIDENT`
  - `New Zealand citizen (special category visa)` → `NZ_CITIZEN`
  - `Working holiday maker (visa subclass 417 or 462)` → `WHM`
  - `Other temporary visa holder (student, sponsored, etc.)` → `OTHER_VISA`
- Primary button: **"Next"**.

## Step 3 — Personal Details

Fill in order (refs from snapshot):
- First Name (`@e?`, placeholder "John") ← persona `firstName`
- Last Name (placeholder "Doe") ← `lastName`
- Date of birth (date input) ← `dob`
- Gender (select) ← option label matching persona `gender`; if `Prefer to self-describe`, fill the revealed self-describe text input
- Address (placeholder "Nr. street name") ← `address`
- Suburb (placeholder "Cairns") ← `suburb`
- State (select) ← `state`
- Postcode (digits, max 4) ← `postcode`
- Mobile (tel, locked +61) ← 9-digit local number (no country code)
- Email (email) ← `email`

**If `AU_CITIZEN` — the Right-to-Work block appears here (not a separate step):**
- Right-to-work document (select) → "Australian birth certificate + photo ID" (`BIRTH_CERT_PHOTO_ID`)
- Document number ← persona `rightToWorkDocNumber`
- Upload identity document (file input, label "Upload a copy of your identity document…"):
  `agent-browser --session "$SESSION" upload @eN <test_docs_dir>/Test-AU-ID.png`
  then `agent-browser --session "$SESSION" wait --load networkidle`
- Upload photo ID (file input, label "Upload your photo ID…"):
  `agent-browser --session "$SESSION" upload @eN <test_docs_dir>/Test-Work-Permit.pdf`
  then `agent-browser --session "$SESSION" wait --load networkidle`
- Declaration checkbox ("I declare that the document details…") — check
- No expiry-date field for this doc type.

Primary button: **"Next"**.

## Step 4 — Emergency Contact

- Emergency contact name ← `emergencyName`
- Relationship (select) ← `emergencyRelationship`; if `Other`, fill the revealed `emergencyRelationshipOther`
- Contact number (tel with country-code dropdown, default +61) ← `emergencyContact` (digits; the dropdown handles the code)
- Emergency email (optional) ← omit unless persona sets it

Primary button: **"Next"**.

## Step 5 — Tax File Number

- `hasTFN` radio — click **"Yes"**, **"No"**, or **"Pending"** per persona. (`No` blocks — persona never uses it.)
  - If `Yes`: the TFN input (digits, max 11, placeholder "123 456 782") appears ← persona `tfn`.
  - If `Pending`: a yellow notice shows; no TFN input.
- TFN declaration full name (signature field, "My Full Name") ← `<firstName> <lastName>`
- Declaration date — defaults to today; leave it.

Primary button: **"Next"**.

## Step 6 — Super

- `hasSuper` radio → **"Yes"** (always).
- `superType` radio (card layout):
  - **APRA** ("The APRA fund or Retirement Savings Account…") — default; the only option for `WHM`/`OTHER_VISA`.
  - **SMSF** ("The Self-Managed Super Fund…") — only for citizens/PR/NZ.
- **APRA fields:** Your Name ← `superName`; Super Member Number ← digits; Super Fund (searchable select) ← pick a known fund (e.g. "AustralianSuper"); Fund ABN ← auto-fills, verify.
- **SMSF fields:** Fund ABN ← 11 digits; Fund Name ← `smsfName`; BSB ← 6 digits (formats `123-456`); Account Number ← digits; Trustee declaration checkbox — check.

Primary button: **"Next"**.

## Step 7 — Bank Account Details

- Bank name ← `bankName`
- Account name ← auto-filled from personal name; leave unless persona differs
- Account number (digits, max 9) ← `accountNumber`
- BSB (6 digits, formats `123-456`) ← `bsb`

Primary button: **"Next"**.

## Step 8 — Visa & Right to Work — **skipped for `AU_CITIZEN`**

If the persona is a citizen, this step is absent; the flow jumps Personal → Emergency (no Visa step). For visa holders:

- Visa family name / given name — **read-only, auto-filled**; do not fill.
- Middle name / other names — optional; omit by default.
- Nationality (searchable select) ← `visaNationality` (type to filter, pick the match)
- Passport number ← `visaPassportNumber` (uppercase alphanumeric)
- Visa grant number ← `visaGrantNumber` (≤13 chars, digits + one optional `X`)
- Visa subclass (3 digits) ← `visaSubclass`; the read-only Visa name field auto-populates.
- Visa expiry date — **only if the subclass requires it**. If a "This visa subclass does not have an expiry date" notice shows instead of a date input, skip it. Otherwise enter a future date.
- Visa document upload (label "Visa grant notice or visa label…"):
  `agent-browser --session "$SESSION" upload @eN <test_docs_dir>/Test-AU-visa-letter.pdf`
  then `agent-browser --session "$SESSION" wait --load networkidle`
- ID document upload (label "ID image (passport photo page or equivalent)"):
  `agent-browser --session "$SESSION" upload @eN <test_docs_dir>/Test-Passport.jpg`
  then `agent-browser --session "$SESSION" wait --load networkidle`
- VEVO consent checkbox ("I consent to my employer checking my visa status…") — check
- Visa agreement checkbox ("I have entered this information truthfully…") — check
- Visa full name (signature, "My Full Name") ← `<firstName> <lastName>`
- Date of acceptance — defaults to today; leave it.

Primary button: **"Next"**.

## Step 9 — Health and Medical

Four yes/no radios (lowercase values): previous injuries, allergies, hospital admissions, other medical. For each, if `yes`, fill the revealed "Please describe" textarea with **≥ 15 characters**.

Primary button: **"Next"**.

## Step 10 — Employee Agreement and Workplace Rules

- FWIS received checkbox ("I confirm I have received and read the Fair Work Information Statement") — check (required)
- CEIS received checkbox ("Casual Employment Information Statement") — check (required for the casual agreement used by the simulator)
- Safety/PPE/injury/hazard acknowledgement checkbox — check (required)
- Conditional punch-location acknowledgement checkbox — check (required)
- Agreement accepted/electronic-signature checkbox — check (required)
- Agreement full name (signature) ← `<firstName> <lastName>`
- Agreement date — defaults to today; leave it.

Primary button: **"Next"**.

## Step 11 — Skills & Experience

All optional. Fill with the persona's selections (checkboxes for work types/crops, radio for seasons, multi-select for licences). Leaving all blank is valid.

Primary button: **"Review Application"**.

## Step 12 — Check Your Details

- Scroll to the bottom; check the **"All information is correct"** checkbox (`allInfoCorrect`).
- The **"Submit Form"** button now un-disables. Click it.
- Wait for the success screen — text **"Submission received"** (legacy copy: **"Application submitted successfully!"**).

If instead the form jumps back to an earlier step with field errors, a backend validation rejected a field (mapped via `FIELD_TO_FORM_MAPPING`). Read the error, fix the offending field from the persona (e.g. invalid TFN → regenerate via `gen-tfn.py`; super fund name matches personal name → pick a real fund), re-check `allInfoCorrect`, and re-submit. Do not weaken validation.

## File-upload quick reference

| Persona path | Field label (snapshot) | File (absolute path) |
|---|---|---|
| Citizen (`AU_CITIZEN`) | "Upload a copy of your identity document…" | `<test_docs_dir>/Test-AU-ID.png` |
| Citizen (`AU_CITIZEN`) | "Upload your photo ID…" | `<test_docs_dir>/Test-Work-Permit.pdf` |
| Visa holder | "ID image (passport photo page or equivalent)" | `<test_docs_dir>/Test-Passport.jpg` |
| Visa holder | "Visa grant notice or visa label…" | `<test_docs_dir>/Test-AU-visa-letter.pdf` |

Use absolute paths with `agent-browser --session "$SESSION" upload @eN <path>`, then wait for network idle before the next upload. The backend checks magic bytes, not filenames — `.jpg`/`.png`/`.pdf` are all in the accepted MIME set.

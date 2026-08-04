# Persona Generator

Build one complete persona before touching the browser. A persona is the invented job seeker: every field the form will ask for, decided up front. Random by default; a **user override** in the prompt wins over the random draw for whatever it specifies, and everything it leaves out is random.

## Residency — the root branch

Pick `residencyStatus` at random from all five (equal weight), unless the user overrides:

| `residencyStatus` | Label on the form | Visa step? | Super | Files |
|---|---|---|---|---|
| `AU_CITIZEN` | Australian citizen | No (right-to-work block instead) | APRA or SMSF | `Test-AU-ID.png` + `Test-Work-Permit.pdf` |
| `PERMANENT_RESIDENT` | Permanent resident | Yes | APRA or SMSF | `Test-Passport.jpg` + `Test-AU-visa-letter.pdf` |
| `NZ_CITIZEN` | New Zealand citizen (special category visa) | Yes | APRA or SMSF | `Test-Passport.jpg` + `Test-AU-visa-letter.pdf` |
| `WHM` | Working holiday maker (visa subclass 417 or 462) | Yes | **APRA only** (SMSF hidden) | `Test-Passport.jpg` + `Test-AU-visa-letter.pdf` |
| `OTHER_VISA` | Other temporary visa holder (student, sponsored, etc.) | Yes | **APRA only** (SMSF hidden) | `Test-Passport.jpg` + `Test-AU-visa-letter.pdf` |

Citizens are ~20% of random draws; the other four share the rest. Each residency fixes the visa, super, and file-upload path for the rest of the persona.

## Personal details (Step 3)

- `firstName`, `lastName` — random plausible; letters only (field strips non-letters). Avoid names with apostrophes/dashes (the sanitizer drops them).
- `nickname` — optional; omit unless the user asks.
- `dob` — a date making the seeker ≥ 18 (e.g. 1990-01-15). Format `YYYY-MM-DD`.
- `gender` — `Male` | `Female` | `PreferNotToSay` | `SelfDescribe`. If `SelfDescribe`, also set `genderSelfDescribeText` (cleared if gender changes).
- `address`, `suburb` — plausible Australian street + suburb (e.g. "12 Smith St", "Cairns").
- `state` — one of `ACT` `NSW` `NT` `QLD` `SA` `TAS` `VIC` `WA`.
- `postcode` — 4 digits matching the state (e.g. QLD → 4000–4999). Field is digits-only, max 4.
- `mobile` — **locked to +61**, 9 digits local (e.g. `412345678`). Stored as `+61412345678`. Do not type the country code — the input is locked.
- `email` — fresh and unique per run: `<first>.<last>.<6hex>@test.com` (lowercased). Must match `/^[^\s@]+@[^\s@]+\.[^\s@]+$/`. A fresh email forces the `new_user` identity path, which is the only path that issues a magic link.

### Citizen-only right-to-work block (Step 3, when `AU_CITIZEN`)

- `rightToWorkDoc` = `BIRTH_CERT_PHOTO_ID` (label "Australian birth certificate + photo ID"). This doc type requires **two** files and **no expiry date**:
  - `rightToWorkDocFile` ← `/home/sven/Projects/AgCore/test-docs/Test-AU-ID.png`
  - `rightToWorkPhotoIdFile` ← `/home/sven/Projects/AgCore/test-docs/Test-Work-Permit.pdf`
- `rightToWorkDocNumber` — a plausible cert number (free text, e.g. `BC123456`).
- `rightToWorkDeclaration` — check the consent checkbox.

(Other doc types — `AU_PASSPORT`, `CITIZENSHIP_CERT`, `PR_IMMICARD`, `NZ_PASSPORT` — are valid but change the files/expiry; `BIRTH_CERT_PHOTO_ID` is the default for the two-file citizen path. The user may override.)

## Emergency contact (Step 4)

- `emergencyName` — letters only.
- `emergencyRelationship` — `Friend` | `Father` | `Mother` | `Sister` | `Brother` | `Partner` | `Other`. If `Other`, set `emergencyRelationshipOther` (free text).
- `emergencyContact` — country code (default `+61`) + up to 15 digits. Use a different number than the seeker's mobile.
- `emergencyEmail` — optional; if provided must be valid. Omit by default.

## Tax — TFN (Step 5)

`hasTFN` ∈ {`Yes`, `Pending`}. **Never `No`** — it blocks the super step. Random pick between `Yes` and `Pending` unless overridden.

- `Yes` → generate a checksum-valid TFN via `scripts/gen-tfn.py` (prints 9 digits). Do not invent a TFN by hand — the checksum (weights `[1,4,3,7,5,8,6,9,10]`, sum mod 11 = 0) rejects guesses. Known-good fallback: `123456782`.
- `Pending` → send **no** TFN value. The form shows a yellow "provide within 28 days" notice; the review screen reflects `pending`. If a TFN was typed then the status switched to `Pending`, the TFN is discarded — never send both.
- `tfnDeclarationName` = `<firstName> <lastName>` (signature field, cursive font).
- `tfnDeclarationDate` = today (defaults to today in `Australia/Brisbane`).

## Super (Step 6)

`hasSuper` = `Yes` (the only accepted value; `No` hard-blocks). Then `superType`:

- **APRA** (default; the only option for `WHM` / `OTHER_VISA`):
  - `superName` = `<firstName> <lastName>`.
  - `superMemberNumber` — digits only (the field strips non-digits in the current build); 6–10 digits.
  - `superFundName` — pick a known fund from the list so `superFundABN` auto-fills: Australian Retirement Trust, AustralianSuper, Rest Super, Hostplus, Aware Super, UniSuper, Cbus, HESTA, CareSuper. Do **not** type a personal name into the fund field (rejected).
  - `superFundABN` — auto-fills on fund selection; verify it populated.
- **SMSF** (allowed for `AU_CITIZEN` / `PERMANENT_RESIDENT` / `NZ_CITIZEN` only):
  - `smsfABN` — 11 digits.
  - `smsfName` — a fund name (not a personal name).
  - `smsfBSB` — 6 digits (auto-formatted `123-456`).
  - `smsfAccountNumber` — digits.
  - `smsfTrusteeDeclaration` — check the box.

## Bank (Step 7)

- `bankName` — letters only (e.g. "Commonwealth Bank").
- `accountName` = `<firstName> <lastName>` (auto-fills until manually edited — leave it).
- `accountNumber` — digits, max 9.
- `bsb` — 6 digits (auto-formatted `123-456`).

## Visa (Step 8) — citizens skip this entirely

- `visaFamilyName` / `visaGivenName` — read-only, auto-filled from personal names. Do not fill.
- `visaMiddleName`, `visaOtherNames` — optional; omit by default.
- `visaNationality` — from the 29-key list (British, American, Canadian, French, German, Italian, Spanish, Chinese, Japanese, Korean, Indian, Indonesian, Malaysian, Thai, Vietnamese, Filipino, Brazilian, Irish, Dutch, Swedish, Norwegian, Danish, Polish, Czech, Austrian, Swiss, Portuguese, Greek, Turkish, Russian). For `NZ_CITIZEN` use "New Zealand". Never "Australian" (not in the list).
- `visaPassportNumber` — 8–10 uppercase alphanumeric (e.g. `AB1234567`). Free text.
- `visaGrantNumber` — 1–13 chars, digits plus at most one `X`, uppercase, no spaces/dashes (e.g. `1234567890` or `1234X567`). Field enforces this on change.
- `visaSubclass` — 3 digits. Pick from the catalogue in `packages/shared-types/src/visa-subclasses.ts` (83 entries). Suggested defaults by residency (any valid code is fine):
  - `WHM` → `417` or `462` (both have expiry).
  - `NZ_CITIZEN` → `444` if present, else any no-expiry subclass.
  - `PERMANENT_RESIDENT` → a permanent/no-expiry subclass (`100`, `801`, `189`, `190`, `191`, `192`, `866`).
  - `OTHER_VISA` → a temporary/has-expiry subclass (`500`, `482`, `485`, `408`, `407`).
- `visaName` — read-only, auto-populates from the subclass code. Do not fill.
- `visaExpiryDate` — **only when the subclass requires it**. Check the catalogue: `hasExpiryDate: false` → the field is hidden behind a "does not have an expiry date" notice; do not fill. `hasExpiryDate: true` → a future date (`YYYY-MM-DD`). Unknown subclass → expiry required.
- `visaCopy` ← `/home/sven/Projects/AgCore/test-docs/Test-AU-visa-letter.pdf` (backend field `visaDocFile`).
- `idDocument` ← `/home/sven/Projects/AgCore/test-docs/Test-Passport.jpg`.
- `vevoConsent` — check.
- `visaAgreement` — check.
- `visaFullName` = `<firstName> <lastName>` (signature field).
- `dateOfAcceptance` = today.

## Medical (Step 9)

Four questions — `previousInjuries`, `allergies`, `hospitalAdmissions`, `otherMedical`. Each is a radio `yes` | `no` (**lowercase values**, unlike Yes/No elsewhere). Random per question. When `yes`, the matching `<key>Details` textarea is required and **must be ≥ 15 characters** (e.g. "No major issues reported."). `ppeAck` — check the PPE checkbox.

## Agreement (Step 10)

- `fwisReceived` — check (required).
- `ceisReceived` — optional; check it anyway (casual default).
- `workersCompAck` — check (required).
- `agreementAccepted` — check (required).
- `agreementFullName` = `<firstName> <lastName>` (signature field).
- `agreementDate` = today.

## Skills & experience (Step 11) — all optional

- `farmWorkTypes` — any subset of: Picking, Packing, Pruning, Planting, Tractor operation, Forklift operation, Irrigation, General farm labour, "None / I'm new to farm work".
- `cropsWorkedWith` — any subset of: Vegetables, Citrus, Berries, Stone fruit, Nuts, Grapes, Livestock.
- `cropsOther` — free text; omit by default.
- `farmExperienceSeasons` — `0 (first season)` | `1` | `2–3` | `4+`.
- `driverLicences` — any subset of the licence options; omit by default.
- `additionalInfo` — free text; omit by default.

## Review (Step 12)

- `allInfoCorrect` — check. This un-disables "Submit Form". Then submit.

## Persona record (keep for the report + memory/AgCore/TEST-LOGIN.md)

Before opening the browser, the persona has: `firstName`, `lastName`, `email`, `residencyStatus`, `visaSubclass` (if non-citizen), `nationality` (if non-citizen), `tfnStatus` (`Yes`/`Pending`), `tfn` (if Yes), and the residency path. These are the fields recorded in `memory/AgCore/TEST-LOGIN.md` after the run.
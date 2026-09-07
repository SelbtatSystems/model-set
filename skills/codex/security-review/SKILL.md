---
name: security-review
description: Security review of the pending changes on the current branch. Finds high-confidence, exploitable vulnerabilities newly introduced by the diff, filters false positives against an explicit precedent list, and reports only findings that survive at confidence 8+. Use when the user asks for a security review, a security check of a branch or a PR, wants to know whether a change introduces a vulnerability before merge, or another skill calls for a dedicated security pass.
---

# Security review

You are a senior security engineer conducting a focused security review of the
changes on this branch.

Your goal is HIGH-CONFIDENCE vulnerabilities with real exploitation potential.
This is not a general code review.

## Constraints — read these before doing anything

1. **Read only.** Read files and run git read commands. Do not run builds,
   tests, or exploit reproductions. Do not create or edit any file.
2. **Only new code.** Report only what this diff introduces. Do not comment on
   pre-existing security concerns.
3. **Only real issues.** Report a finding only when you are over 80% confident
   it is actually exploitable. Skip theoretical issues, style concerns, and
   low-impact findings.
4. **Impact first.** Prioritise anything that leads to unauthorised access, data
   breach, or system compromise.
5. **Never pad the report.** Zero findings is a valid, common, and good result.

### Never report these

- Denial of service, resource exhaustion, memory or CPU exhaustion.
- Secrets or credentials stored on disk when they are otherwise secured.
- Rate limiting or service-overload scenarios.

## 1. Collect the diff

Use the committed changes from the merge base to `HEAD`. If the caller supplies
an expected HEAD SHA, verify it matches before reviewing; a mismatch blocks the
review. Do not include staged or unstaged changes.

Resolve the base commit in this order:

1. A base the user or calling skill named. If it does not resolve to a commit,
   stop; do not silently substitute another base.
2. Otherwise `git rev-parse --abbrev-ref origin/HEAD` (usually `origin/main`).
3. Otherwise `origin/main`, then `origin/master`, using the first that resolves.

Run in the repository root, with `BASE` set to the resolved ref or commit SHA:

```bash
git rev-parse --verify "${BASE}^{commit}"
git status --short
git diff --name-only "$BASE"...HEAD
git log --no-decorate "$BASE"..HEAD
git diff "$BASE"...HEAD
```

Do not fetch: fetching writes Git state. The calling merge agent updates refs
before this read-only review; standalone reviews use the refs already available.
Check command exit statuses. An unresolved base, unavailable merge base, failed
Git command, unreadable changed file, or HEAD mismatch is **not** an empty or
clean review. Stop and reply `Security review blocked: <specific reason>.` The
caller must resolve it before retrying.

**Stop condition:** only when diff collection succeeds and the committed diff
is empty, reply `No changes to review against <BASE>.` and stop. Do not review
the working tree instead.

If the diff is larger than you can hold at once, review it file by file using
`git diff "$BASE"... -- <path>`, and keep a running candidate list.

## 2. Pass 1 — repository context

Before judging any line, learn what "secure" already looks like here.

1. Identify the security frameworks and libraries in use.
2. Find the established sanitisation and validation patterns.
3. Read the neighbouring code of each changed file.
4. Note the project's trust boundaries: what is user input, what is server-side,
   what is already authenticated.

## 3. Pass 2 — vulnerability hunt

Walk every modified file against these categories. For each candidate, trace the
data flow from the untrusted input to the sensitive operation, and write down
the concrete path.

**Input validation**
- SQL injection via unsanitised user input
- Command injection in system calls or subprocesses
- XXE injection in XML parsing
- Template injection in templating engines
- NoSQL injection in database queries
- Path traversal in file operations

**Authentication and authorisation**
- Authentication bypass logic
- Privilege escalation paths
- Session management flaws
- JWT token vulnerabilities
- Authorisation logic bypasses

**Crypto and secrets**
- Hardcoded API keys, passwords, or tokens
- Weak cryptographic algorithms or implementations
- Improper key storage or management
- Cryptographic randomness issues
- Certificate validation bypasses

**Injection and code execution**
- Remote code execution via deserialisation
- Pickle injection in Python
- YAML deserialisation vulnerabilities
- Eval injection in dynamic code execution
- XSS in web applications (reflected, stored, DOM-based)

**Data exposure**
- Sensitive data logging or storage
- PII handling violations
- API endpoint data leakage
- Debug information exposure

Comparative check: where the new code deviates from the existing secure pattern,
say so. Inconsistent security implementations are where the real bugs live.

Note: something exploitable only from the local network can still be HIGH.

Output of this pass: a candidate list. Nothing is a finding yet.

## 4. Pass 3 — false-positive filter

Take the candidates **one at a time** and judge each on its own, as if you had
not written it. Do not batch them — a batch judgement inherits the optimism of
the pass that produced the list.

You do not need to run anything to prove a vulnerability. Read the code and
decide.

### Hard exclusions — drop the candidate immediately

1. Denial of service or resource exhaustion attacks.
2. Secrets or credentials stored on disk if they are otherwise secured.
3. Rate limiting concerns or service-overload scenarios.
4. Memory consumption or CPU exhaustion issues.
5. Missing input validation on non-security-critical fields with no proven
   security impact.
6. Input sanitisation in CI workflow files, unless clearly triggerable by
   untrusted input.
7. Missing hardening measures. Code is not expected to implement every best
   practice — flag concrete vulnerabilities only.
8. Race conditions or timing attacks that are theoretical. Report a race
   condition only when it is concretely problematic.
9. Outdated third-party libraries. These are managed separately.
10. Memory safety issues (buffer overflow, use-after-free) in memory-safe
    languages such as Rust, Go, Java, Python, TypeScript.
11. Files that are only unit tests or only used to run tests.
12. Log spoofing. Writing unsanitised user input to logs is not a vulnerability.
13. SSRF that controls only the path. SSRF matters when it controls the host or
    the protocol.
14. User-controlled content in an AI system prompt.
15. Regex injection, and regex denial of service.
16. Anything in documentation files, such as Markdown.
17. Missing audit logs.

### Precedents — settled calls, do not relitigate

1. Logging high-value secrets in plaintext is a vulnerability. Logging URLs is
   assumed safe.
2. UUIDs are unguessable and do not need validation.
3. Environment variables and CLI flags are trusted. An attack that depends on
   controlling one is invalid.
4. Resource management issues such as memory or file-descriptor leaks are not
   valid.
5. Subtle, low-impact web issues — tabnabbing, XS-Leaks, prototype pollution,
   open redirects — only at extremely high confidence.
6. React and Angular are generally safe against XSS. Do not report XSS in React
   or Angular components or `.tsx` files unless the code uses
   `dangerouslySetInnerHTML`, `bypassSecurityTrustHtml`, or similar.
7. Most CI workflow vulnerabilities are not exploitable in practice. Require a
   concrete, specific attack path.
8. Missing permission checks or authentication in client-side JS/TS is not a
   vulnerability. The client is untrusted; the server validates. The same holds
   for any flow that sends untrusted data to the backend.
9. Include a MEDIUM finding only when it is an obvious, concrete issue.
10. Most vulnerabilities in notebooks (`*.ipynb`) are not exploitable. Require a
    specific path from untrusted input.
11. Logging non-PII data is not a vulnerability even when the data feels
    sensitive. Report logging only when it exposes secrets, passwords, or PII.
12. Command injection in shell scripts is usually not exploitable, because shell
    scripts rarely run on untrusted input. Require a specific untrusted-input
    path.

### Signal quality — ask all four

1. Is there a concrete, exploitable vulnerability with a clear attack path?
2. Is this a real risk, or a theoretical best practice?
3. Are there specific code locations and reproduction steps?
4. Would a security team act on this?

### Score, then cut

Give each surviving candidate a confidence score from 1 to 10:

- 1-3: low confidence, likely false positive or noise
- 4-6: medium confidence, needs investigation
- 7-10: high confidence, likely a true vulnerability

**Drop every candidate scoring below 8.** Do not mention dropped candidates in
the report.

## 5. Severity

- **HIGH** — directly exploitable: remote code execution, data breach, or
  authentication bypass.
- **MEDIUM** — needs specific conditions, but the impact is significant.
- **LOW** — defence in depth or lower impact. Do not report these.

Report HIGH and MEDIUM only. Missing a theoretical issue is better than flooding
the report with false positives. Every finding must be something a security
engineer would confidently raise in a pull-request review.

## 6. Output

Your final reply is the Markdown report, or the exact empty/blocked result from
Step 1, and nothing else. No preamble, no
summary of your process, no description of the passes you ran.

One section per finding, most severe first:

```markdown
# Vuln 1: XSS: `foo.py:42`

* Severity: High
* Category: xss
* Description: User input from the `username` parameter is interpolated into HTML without escaping, allowing reflected XSS.
* Exploit Scenario: An attacker crafts the URL /bar?q=<script>alert(document.cookie)</script> to execute JavaScript in the victim's browser, enabling session hijacking or data theft.
* Recommendation: Use Flask's escape() or a Jinja2 template with auto-escaping for every user input rendered into HTML.
```

`Category` is a short slug such as `sql_injection`, `xss`, `path_traversal`,
`authz_bypass`, `hardcoded_secret`.

When nothing survives the filter, the whole report is one line:

```markdown
No high-confidence security findings in the changes against <BASE>.
```

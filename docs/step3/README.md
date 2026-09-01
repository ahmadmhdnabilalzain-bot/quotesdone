# Step 3 — IT / Cybersecurity deep knowledge

Company knowledge is **universal** (every agent, veteran level). The app's **code and its security**
are the one extra layer, and only the **engineering + assurance** agents (`product_eng`, `assurance`)
carry it. This directory documents that layer.

## What the IT/cyber agents know

Built to the bar of a world-class senior engineer / security lead who has worked here 20 years —
the product of four dimensions, all mapped onto our exact stack (Postgres/Supabase/Deno/Next.js + an
AI agent workforce):

1. **Internal mastery** — our real edge-function attack surface, RLS/grants/`SECURITY DEFINER` surface,
   the kernel's own controls, the auth/identity model, and the baseline of normal.
2. **Professional body** — OWASP Top 10 and secure-coding, mapped to this codebase.
3. **Threat intelligence** — MITRE ATT&CK threat model + detection, and a dated CVE/hardening snapshot
   for our stack (explicitly refreshed against live advisories, never trusted as static).
4. **AI-security frontier** — OWASP LLM Top 10, prompt injection (incl. indirect via marketplace
   content), excessive agency, poisoned knowledge — where "smartest in the world" is actually won.

Plus the compliance posture (PCI-DSS SAQ A, UAE PDPL, SOC 2 / ISO 27001) mapped to our controls, and
SRE/operational excellence.

## How it is delivered (scoped, not universal)

- Records live in `ops_knowledge` at `layer = 'it_security_deep'` (see `scripts/sql/it_cyber_deep_knowledge.sql`).
- `fn_it_security_slice(dept, q, budget)` returns them **only** for `product_eng` / `assurance` — `[]`
  for every other department. It is folded into `fn_agent_context_v3` as `it_security_knowledge`, so
  those agents carry the depth automatically when they act.
- `fn_company_knowledge_search` (the universal veteran recall) **excludes** this layer, so code/security
  depth never leaks to non-IT agents.

## Always current

- `fn_it_security_live_posture()` recomputes the **derivable** posture every run (RLS coverage, definer
  surface, cron baseline, anon grants) — hourly cron `it_security_live_posture_hourly`. Nothing static.
- The **authored** records are a snapshot kept current with the code by re-running
  `regenerate_it_cyber_knowledge.workflow.js` and rebuilding `scripts/sql/seed/it_cyber_knowledge_seed.json`,
  then `node scripts/seed_it_cyber_knowledge.mjs`.

External threat intelligence (CVEs, npm/Supabase advisories) is **not** derivable from the database and
must be refreshed via `npm audit`, Supabase `get_advisors`, and CVE feeds — the records say so explicitly.

## The `os_*` edge-JWT decision (2 Sep 2026)

Building this layer surfaced a config drift: `supabase/config.toml`'s header comment claimed **20**
functions require a JWT and listed the 7 `os_*` operator-console functions, but only **13** actually
have `verify_jwt = true`, and all 7 `os_*` are `verify_jwt = false` live. An audit of every `os_*`
function, its callers, and the config generator settled it:

- `config.toml` is a **generated mirror** of the live project's `verify_jwt` values
  (`scripts/gen_supabase_config.mjs`, `--check` guards drift). The "20 + os_*" header had been
  hand-edited — the exact thing the file warns against. Fixed by **regenerating** (header now 13).
- The `os_*` are `verify_jwt=false` **by design**, not by oversight: they share a **build-mode open
  door** (`fn_os_open_access`) that, when open, runs the whole console with **no JWT** for
  operator/build-time recovery, and the OS frontend sends tokenless requests to use it. Enabling
  `verify_jwt=true` would sever that door at the edge (6 of 7 audited `would_break`). Off the
  build-mode path the `os_*` are guarded **in code** (`admin.auth.getUser` + `admin_emails`).
- **Decision: Option 2** — correct the doc, do **not** edge-gate. Edge-gating `os_*` is only correct
  **after build mode is retired** (a launch-time decision). The build-mode door is documented as a
  `critical`-risk record in the IT/cyber layer, since write-access to `os_open_access_log` is the real
  control on unauthenticated admin access.

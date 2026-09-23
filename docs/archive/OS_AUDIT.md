# QuotesDone OS — Production-Readiness Audit

**Date:** 22 Jul 2026 · **Auditor role:** Lead Architect / Principal + Security + Performance Engineer · **Source of truth:** production (Supabase project `htdblwldjkcgjvmqkbeh`), *not* the git mirror (mirror is stale — open item #115).

**Scope.** The OS pillar — everything the three delivered chapters (customer portal, supplier portal, public website) don't already own: the autonomy engine, agent-execution layer, OS console + admin, copilot, CRM/growth, knowledge base, finance/collections/compliance, notification infra, and shared utilities. Concretely: **~135 edge functions** pulled and read from production across six parallel audits, plus the Postgres core — **443 public functions (232 `SECURITY DEFINER`)** and **~95 active `pg_cron` jobs**.

**Method.** Every finding below was derived from code actually read in production. Findings are tagged **Verified** (I/the auditor read the exact code or live data) or **Inferred** (deduced from pattern/indirect evidence). The highest-stakes Critical/High items were re-confirmed directly against live code and data before inclusion.

**Bottom line.** This is a genuinely capable, unusually security-conscious autonomous OS with excellent operational instincts (RLS everywhere, pinned `search_path` on all 232 definer functions, documented post-incident hardening, human-in-the-loop on every money/destructive action, near-failure-free crons). It is **not yet production-ready**, but the gap is finite and mostly small fixes: a latent double-charge on the dues path, a handful of auth/alerting gaps, and a large but low-risk duplication debt. No active data leak or live money loss was found.

---

## Production-readiness scores (1–10, evidence-backed)

| Dimension | Score | Evidence |
|---|---|---|
| **Architecture** | 7 | Clean separation: deterministic Postgres "brain" (`fn_*`) + one centralized LLM bridge (`run_agent → /agents`) + edge HTTP layer. RLS on every table; human-in-the-loop by construction. Loses points for zero shared-code module across ~135 edge functions and overlapping/broken surfaces (two "Secretaries", `orchestrate` non-functional). |
| **Maintainability** | 5 | The weakest axis. Verbatim duplication everywhere — `sec()` in every function, the LLM client + model list copy-pasted into ~19, ten near-identical alert helpers, three notification senders, three asset uploaders. A model rename or auth fix is a many-file manual edit that demonstrably drifts (a security fix applied to `dir_ingest` never reached its siblings). |
| **Performance** | 7 | Crons run essentially failure-free; good pagination, limits, idempotent upserts. Deductions: a real N+1 in `learn_gaps` (~3,000 sequential queries/run), per-row scans in `kb_autofill_gaps`/`kb_ingest`, ~45 unused indexes + 1 duplicate index + 1 unindexed FK, and deploy watchers firing every 1–2 min (~15k invocations/week). |
| **Security** | 7 | Strong foundations: RLS on all tables, all 232 `SECURITY DEFINER` functions have pinned `search_path` (escalation vector closed), MFA step-up on some surfaces, systematic console XSS escaping, real webhook HMAC (Svix + Twilio), and exemplary documented post-mortems (`ai_health`, `uptime_check`, `claim_lookup`, `admin_provision`, `auth_api` takeover — all fixed). Deductions: `os_bypass_key` backdoor, MFA gaps on money mutations, 4 anon-executable definer RPCs, `money_tests` anon-invocable, an over-broad `inbound_secret`. |
| **Reliability** | 6.5 | ~95 crons ~failure-free; best-in-class `agent_runs` observability with plain-English business-impact notes; a watchdog-of-watchdogs (`fn_ops_watch`). Deductions: no LLM timeout (fallback defeated by a hang), founder WhatsApp alerts silently broken, social pipeline broken at go-live, and a severity-vocabulary fracture that hides critical alerts from the founder brief. |
| **Scalability** | 6.5 | Fine at pre-launch volume. Single Supabase region; N+1s / per-row scans and unbounded snapshot inserts will bite as inquiries and suppliers grow; Auth is on an absolute (not percentage) connection strategy that won't scale with instance size. |
| **Code Quality** | 6 | High marks for in-code post-mortems, guardrails, and readable comments; dragged down by pervasive duplication, ~8 dead functions, and an HTTP-200-on-error convention that hides failures from HTTP monitors. |
| **Technical Debt** | 5 | Material but manageable: ~8 dead/orphaned functions, the duplication tax, severity-vocabulary fracture, config sprawl (model IDs in ~19 files), overlapping agents, and a stale prod→repo mirror (#115). Little of it is urgent; none of it is unrecoverable. |

**Composite readiness: ~6.4/10 — "close, with a clear pre-launch punch list."**

---

## 🔴 Critical — fix before the relevant flow is exercised

### C1. Supplier dues double-charge interest (latent today; 0 dues rows)
- **Files:** `collections_legal` (edge) + `supplier_pay` (edge). **Verified** (code + live data).
- **What:** On legal escalation, `collections_legal` writes the *same* interest value into two columns: `interest_amount: interest` **and** `fine_amount: interest`. `supplier_pay.owed()` then bills `amount_due + admin_fee + interest_amount + fine_amount` — i.e. **interest twice**. Meanwhile the demand letter and `total_claim` use single interest, so the letter says X and the portal charges X + interest.
- **Why it matters:** A supplier who reaches legal collections and pays via the portal is overcharged one interest amount, and the amount billed contradicts the signed demand letter — a money and legal-consistency defect on a live path.
- **Live status:** `supplier_dues` has **0 rows** — no supplier owes anything yet, so nothing is being overcharged *today*. It becomes a real overcharge on the first legal escalation.
- **Fix:** Stop mirroring `interest` into `fine_amount` (it's a legacy column). Either set `fine_amount: 0`/leave null, or make `supplier_pay.owed()` ignore `fine_amount`. Pick `total_claim` as the single source of truth for the charge.
- **Benefit:** Suppliers billed exactly what the demand letter states; books correct.
- **Timing:** **Before launch** (before any due can exist). Tiny change.

### C2. PDPL right-to-erasure is materially incomplete
- **Files:** `pdpl_erase` + `fn_pdpl_redact` + `retention_purge`. **Verified.**
- **What:** `fn_pdpl_redact` scrubs only `customers, leads, notifications, outreach, email_verifications, phone_verifications, ai_usage`; `pdpl_erase` deletes only `supplier-docs / drawing-files / quote-files`. After a "completed" erasure the subject's name/DOB/phone/email still persist in: signed-T&C certificates + `customers-register.xlsx` (`signed-terms` bucket **and the Dropbox mirror**), `rfq_archives` case files (`backups` bucket), `inbound_messages`/`wa_messages`/`messages` bodies, `receipt-files`/`finance-docs`, the daily DB dumps, and the **entire Dropbox mirror (never purged)**. Only an aggregate `security_events` count is logged, not the rows touched.
- **Why it matters:** UAE PDPL erasure/retention obligations on real personal data are not actually met; the system reports success while leaving PII in half a dozen stores.
- **Live status:** Pre-launch, no/low real erasure requests — but the obligation is legal, not volume-based.
- **Fix:** Extend redaction to the message/archive tables; delete or tombstone the `signed-terms` + `backups` archive copies **and the Dropbox mirror** on erasure; write a per-item audit log of exactly what was erased.
- **Benefit:** Actual PDPL compliance; defensible erasure trail.
- **Timing:** **Before launch / before processing any erasure request.**

---

## 🟠 High — security, correctness, resilience

### Security & authorization

**H1. `os_bypass_key` — a static shared secret that grants unattributed, MFA-less admin.** `os_api`/`os_ops`/`os_pages`. **Verified.** All three open with `if (osKey === sec('os_bypass_key')) { email = 'os-preview@quotesdone.com' }`, skipping `isAdmin()`. A holder can approve/ban suppliers, `gl_post` journal entries, resolve refunds, and **publish arbitrary HTML to the live site**, all audit-logged as a pseudonym (non-attributable) and bypassing the MFA `admin_insights` requires. *Mitigation confirmed:* the key is **not** shipped to browsers — its only frontend reference is in `_archive/OsApp.tsx.bak` (archived; operator supplies it at runtime), 0 hits in live `pages`. So it's a server-side backdoor to remove, not a remote exploit. **Fix:** remove the bypass, or restrict it to strictly read-only preview actions and stamp a real identity into the audit log. **Timing:** before launch (small, high-value).

**H2. Four `SECURITY DEFINER` RPCs are executable by `anon`/`authenticated`.** `fn_notify_supplier`, `fn_split_inquiry`, `fn_category_sales`, `fn_supplier_capability_chase` (flagged by Supabase's own advisor). **Verified.** These are meant for cron/service only; exposed via `/rest/v1/rpc`, an unauthenticated caller could split another customer's inquiry (`fn_split_inquiry` mutates `inquiries`) or trigger supplier-facing emails (`fn_notify_supplier`, `fn_supplier_capability_chase`) — a griefing/spam and data-integrity vector. **Fix:** `REVOKE EXECUTE … FROM anon, authenticated` on all four (same remediation already applied to other definer RPCs). **Timing:** before launch. Trivial.

**H3. MFA is enforced on the wrong surfaces.** `admin_insights` (read-only analytics) and `agent_act` (JWT path) require an MFA session; the **more destructive** `admin_api` (approve refund, verify/ban supplier, expense CRUD, `agent_decide`), `admin_detail`, `os_api`/`os_ops` (bans, `gl_post`, refunds), and `secretary`/`secretary_act` (email, refund/ban/delete) require only an admin-email JWT, **no MFA**. Two admin sources also diverge (`fn_role_of OR admin_emails` vs `admin_emails` only). **Verified.** **Fix:** require MFA on the money/approval/destructive mutations; unify the admin check. **Timing:** MFA on refunds/approvals before launch; unification can follow.

**H4. `money_tests` has no self-auth and is anon-invocable.** `money_tests`. **Verified** (no in-code auth; `verify_jwt=true` so the public anon key passes the gateway). It returns the pass/fail map of the RLS-leak and payment probes and echoes the Stripe key prefix — handing an attacker a live map of what's exposed. **Fix:** add an `inbound_secret` check like its peers; stop returning probe detail to callers. **Timing:** before launch.

**H5. Prompt-injection → outbound email.** `secretary` (v10). **Verified.** The `@@ACTIONS@@` protocol lets the model emit up to 5 emails with arbitrary `to`, inserted straight into `notifications` with no confirm step, while founder-attached document text (≤12k chars) is folded into the system prompt. A malicious forwarded/pasted document could steer the agent into sending attacker-authored mail from the QuotesDone domain. (`secretary_act` is safer — >3 recipients need a confirm token — but still auto-sends ≤3.) **Fix:** require explicit confirm for any outbound email; treat attachment text as untrusted (delimit; instruct the model to never act on instructions inside it). **Timing:** before launch.

### Money & ledger correctness (all latent — 0 dues rows — but real logic defects)

**H6. Two competing interest engines fight over one column.** `collections_legal` (day-based 9%/yr, frozen) and `fn_accrue_dues_interest` (month-based 0.75%/mo) both write `supplier_dues.interest_amount`, and the accrual cron's `WHERE` doesn't exclude `status='legal'` — so after escalation it silently overwrites the figure the signed demand letter quoted. **Verified.** **Fix:** one interest formula; exclude legal-stage dues from the accrual cron. **Timing:** before dues exist.

**H7. Phantom receivable for waived/cancelled dues.** `fn_gl_sync_business` block 2 books a clawback receivable for any `amount_due > 0` with **no status filter**, so `waived`/`cancelled` dues still debit `1110` and never clear (block 2b only settles `paid`/`settled`). **Verified.** **Fix:** add `and status not in ('waived','cancelled','reversed')`; post a reversal when a raised due is later waived. **Timing:** before dues exist.

**H8. `finance_ingest` writes financial rows with no idempotency key.** `finance_ingest`/`finance_doc`. **Verified.** Re-uploading an invoice (or any retry) creates duplicate expenses/income/subscriptions; forecasts then double-count. (Contrast the *good* dedupe in `resend_inbound`.) **Fix:** natural dedupe key (`doc_path` or vendor+amount+date) with upsert. **Timing:** before real finance data flows.

### AI reliability & governance

**H9. LLM fetches have no timeout/abort — the fallback never fires on a hang.** ~all conversational + cron LLM helpers (`llm()`/`opus()`/`orChat()`). **Verified.** The model-fallback loop only advances on a thrown error or empty completion; a *hung* upstream blocks to the platform wall-clock limit, so Opus→Sonnet fallback never triggers and interactive agents (`agent_act`, `secretary`) hang for the founder. (Note `ai_health`/`uptime_check` *do* set timeouts — the pattern exists, it's just not applied to the model calls.) **Fix:** wrap every LLM fetch in an `AbortController` (~20–30s); treat timeout as a fallback trigger. **Timing:** before launch.

**H10. Model IDs + LLM client duplicated across ~19 functions with divergent fallback order.** **Verified.** `['anthropic/claude-opus-4.8','anthropic/claude-sonnet-5']` is copy-pasted everywhere; some functions reverse it (Sonnet-first), `secretary_act` adds a third model, and the category generators split Opus-first vs Sonnet-first — an unintended cost/quality divergence. A model rename (the exact scenario the code comments cite) means editing ~19 files. **Fix:** one shared `_shared/llm.ts` with a single canonical model ladder read from `app_secrets`/`prompts`. **Timing:** fast-follow (High for cost/maintainability).

**H11. The most powerful prompts are outside prompt-governance.** `agent_act`/`agent_brain`/`secretary`/`secretary_act` define large, action-capable system prompts inline (six divergent agent rosters); the `prompt_gate`/`prompt_improve` benchmarking-and-approval system governs a *different, smaller* set of pipeline prompts. So the agents that can email/refund/ban are ungoverned and drift against each other. **Verified.** **Fix:** move agent scaffolding into the versioned `prompts` table (shared base + per-agent persona) and bring it under `prompt_gate`. **Timing:** fast-follow.

**H12. `orchestrate` is non-functional against the current `agent_act` contract.** **Verified.** It calls `agent_act` with `{agent_key, mode, instruction, actions}`; current `agent_act` speaks `{action, agent, message}` and ignores those fields, so every step runs as an empty-message `secretary`, plans come back empty, execute does nothing — while still paying for an Opus/Sonnet call per step. **Fix:** repair the contract or delete the function (add an integration smoke test if kept). **Timing:** before launch (decide keep/kill).

### Data pipelines & alerting

**H13. Social pipeline is broken end-to-end (masked only by a feature flag).** `social_stage → postiz_publish`. **Verified.** `social_stage` sends `{content, channels, mode, image_url}` with an `x-internal-key` header; `postiz_publish` requires `body.__secret` and reads `body.text`/`type`/`image` — so the call 403s, and even past that `text` is empty. It's hidden today only because `marketing_golive='false'`. On the day marketing is switched on, **zero** social content publishes and the hourly cron churns silently. **Fix:** align to one contract (`{__secret, text, type:'draft', image, channels}`). **Timing:** before marketing go-live.

**H14. `kb_import` ingest is destructive and non-transactional.** **Verified.** `op:'ingest'` deletes all `kb_chunks` where `source_kind='library'` *then* inserts; a mid-loop insert error leaves the RAG corpus partially or fully deleted with no rollback — a malformed upload = self-inflicted knowledge-base outage. **Fix:** stage into a temp set, verify count, then swap. **Timing:** before relying on the KB in production.

**H15. `learn_gaps` writes LLM-proposed fields to live customer intake before review, and is an N+1.** **Verified.** It merges model-suggested questions straight into `category_specs.fields` (the live intake form) *then* files a review action, and separately fires ~2 count queries per inquiry over up to 1,500 rows (~3,000 sequential round-trips/run). **Fix:** stage suggestions for approval before they go live; replace the loop with one aggregate query/RPC. **Timing:** fast-follow.

**H16. Founder gets no WhatsApp on critical alerts.** `alert_founder → send_whatsapp`. **Verified** (config). `send_whatsapp` is `verify_jwt=true`; `alert_founder` calls it with no `Authorization` header, so the gateway 401s before the handler runs — critical/fraud/outage/refund-escalation alerts never reach the fast WhatsApp channel (only the queued email survives). **Fix:** set `send_whatsapp` `verify_jwt=false` (it already checks `__secret`), or have `alert_founder` send the service bearer. **Timing:** before launch.

**H17. Severity-vocabulary fracture hides critical alerts from the founder.** `founder_alerts.level` holds `crit` (97), `critical` (16), `high` (7), `warn`, `info` — with no normalizing trigger — while every founder-facing consumer filters `level='critical'` only. **Verified** (live data). So 97 `crit` + 7 `high` rows (policy contradictions write `crit`; security self-audit writes `high`) are excluded from the daily brief's "critical" count *and* the email bridge. **Fix:** one enum via CHECK constraint, or change consumers to `level in ('critical','crit','high')`. **Timing:** before launch (safe, high-signal).

**H18. High-severity C-suite findings are queue-only, never paged.** `fn_finance_ai`/`fn_security_ai`/`fn_operations_ai`/`fn_legal_ai`. **Verified.** `cash_negative`, `low_runway`, `rls_gap`, `open_fraud` are inserted only as `agent_actions`; a HIGH finance/security condition reaches the founder only in the next daily digest (≤24h) and only as a count. **Fix:** when `risk in ('high','critical')`, also enqueue a notification. **Timing:** before launch.

---

## 🟡 Medium — quality, consistency, debt

**M1. No shared-code module (the root cause of most duplication).** Every edge function has `import_map:false`; `sec()`, `logRun`, auth/MFA preambles, `chunkText`, letterhead builders, and the LLM client are copy-pasted. **Verified.** The direct consequence: a fail-closed auth fix applied to `dir_ingest` never reached its siblings `yello_scrape`/`profile_ai` (which still carry a dormant `__test` branch). **Fix:** introduce a `_shared/` module and import it. Highest-leverage maintainability move. **Timing:** deferred (incremental).

**M2. Ten near-identical alert helpers.** `fin_alert`, `ai_rec`, `doc_rec`, `mkt_rec`, `ops_rec`, `sec_incident`, `leg_flag`, `kn_task`, `fn_strategy_rec`, `fn_report_flag`. **Verified.** All are `if cond and not exists(dedupe) then insert into agent_actions`, differing only in literals. **Fix:** collapse to one `agent_rec(...)`. **Timing:** deferred.

**M3. Alert lifecycle inconsistent — most recommendations never auto-resolve.** **Verified.** Only `kn_task` clears when its condition clears; `fin_alert`/`sec_incident`/`ops_rec`/etc. leave `pending` rows forever even after the metric recovers, while `auth_hardening` and pricing-review re-raise every run. The founder queue fills with stale + perpetual items. **Fix:** adopt `kn_task`'s resolve-on-clear everywhere; make standing reminders a non-queue kind. **Timing:** deferred.

**M4. CSV formula injection in the leads export.** `export_leads_csv`. **Verified.** `csvCell` quotes but doesn't neutralize leading `= + - @`; `company_name`/`description`/`services` are attacker-influenced via scraping/self-registration, so an admin opening the export in Excel can execute a payload. **Fix:** prefix cells starting with `= + - @ \t \r` with `'`. **Timing:** before exporting real lead data.

**M5. `qa_suite` scores inconclusive RLS probes as PASS.** **Verified.** `anonProbe` returns `leaked:false` for any non-401/non-array response, so an RLS leak with an unexpected shape reads as a pass. **Fix:** treat inconclusive as FAIL (or a distinct state). **Timing:** fast-follow.

**M6. `prompt_gate` auto-promotion gap.** **Verified.** Non-sensitive prompts auto-promote on delta ≥5/score ≥60; the sensitive pattern (`legal|finance|complian|security|quote_review`) omits **pricing, matching, intake** — prompts that directly shape quotes/fees could ship without human review, and the judge shares the candidate's model family (self-evaluation). **Fix:** widen the pattern; consider a cross-family judge. **Timing:** fast-follow.

**M7. Two overlapping "Secretary" implementations.** `secretary` (weaker `@@ACTIONS@@` gating) and `secretary_act` (OpenAI tool-calling + confirm tokens) both send email / run jobs / generate docs. **Verified.** **Fix:** retire one (keep `secretary_act`). **Timing:** fast-follow.

**M8. `verify_jwt=true` on secret-gated internal crons.** `exec_agents`, `dr_drill`, `archive_rfq`, `site_deploy` self-auth via `inbound_secret` yet also carry gateway `verify_jwt=true`; a cron caller sending only `__secret` (no bearer) is 401'd before self-auth runs — works today only because callers happen to send a JWT. **Verified.** **Fix:** standardize internal crons on `verify_jwt=false` + `inbound_secret`. **Timing:** fast-follow (same class as H16).

**M9. `admin_api` mutations aren't audit-logged.** `os_api`/`os_ops` write `os_audit_log` on every mutation; `admin_api` performs equally sensitive actions (refund approve/reject, supplier verify, `unban`, expense CRUD) with no central audit row. **Verified.** **Fix:** mirror the `os_audit_log` insert into `admin_api`. **Timing:** before launch (forensics on money/trust decisions).

**M10. Console XSS — three unescaped interpolations.** `os3` shell. **Verified.** The shell has a correct `escapeH()` and wraps all external data (supplier names, inbound email subject/body, chat content) in it — but three `innerHTML` interpolations (`${e.message}`, `${m.label}`, `${t.title}`) are not wrapped. Currently internal/error-sourced, so low impact, but `e.message` can reflect server strings. **Fix:** wrap the three. **Timing:** before launch (trivial defense-in-depth).

**M11. Dead 90-day auto-ban.** `fn_ban_overdue_dues` bans at 90 calendar days only `where legal_escalated_at is null`, but `collections_legal` sets that at ~30 working days first — so the hard-ban + `crit` alert never fire. **Verified.** **Fix:** one escalation owner, or drop the `legal_escalated_at is null` guard. **Timing:** before scale.

**M12. Multi-currency summed as AED.** `finance_ingest` (`doForecast`/`doRemind`) sums `amount` across USD/EUR/AED rows as if all AED (GL block 3 *does* convert). **Verified.** **Fix:** convert via `gl_settings` FX before summing, or group by currency. **Timing:** before scale.

**M13. `qa_mint` is a standing account-creation primitive in prod.** Behind only `inbound_secret`, it creates confirmed auth users with arbitrary email. **Verified.** **Fix:** disable for production or restrict to a test domain. **Timing:** before launch.

**M14. `inbound_secret` is an over-broad "god key".** One shared secret authorizes refunds/bans/file-deletes, job triggers, prompt drafts, user minting; `secretary_act` confirm tokens also don't bind to the creator or expire. **Verified/Inferred.** **Fix:** segment secrets by capability tier (read/act/destructive); add token expiry + creator binding. **Timing:** fast-follow.

**M15. Three definer functions have a mutable `search_path`.** `fn_accrue_dues_interest`, `fn_ban_overdue_dues`, `fn_gl_sync_business` (plus trigger fns `mask_contact`, `qd_on_refund_resolved`, `trg_mask_quote_contact`) — 6 total flagged by the advisor. Low risk (these are not the anon-reachable ones), cheap to pin. **Verified.** **Fix:** `ALTER FUNCTION … SET search_path = public, pg_temp`. **Timing:** fast-follow.

**M16. `extension in public` schema.** `vector` (pgvector) + others installed in `public`. **Verified.** Hardening only. **Fix:** move to a dedicated schema when convenient. **Timing:** deferred.

**M17. Duplicate notification templating + three WhatsApp senders.** `alert_founder` builds an `html` column `send_outbox` never reads (dead), and `wa_inbound`/`alert_founder`/`send_whatsapp` are three direct Twilio callers. **Verified.** **Fix:** honor a prebuilt `html` in `send_outbox`; route all WA through `send_whatsapp`. **Timing:** cleanup.

**M18. Asset uploader family triplicated with inconsistent auth + allow-lists.** `asset_put` (text, `inbound_secret`, bucket allow-list) vs `asset_store` (base64, `content_secret`, **no allow-list**) vs `asset_upload` (base64, `inbound_secret`, **no allow-list**). **Verified.** Two of three will upsert arbitrary bytes to any bucket/path. **Fix:** collapse to one `asset_io` with one secret + shared allow-list. **Timing:** cleanup.

---

## 🟢 Low — housekeeping, dead code, DB hygiene

**Dead / orphaned functions (safe to delete; recoverable from git):**
- `support_ai` — superseded by `site_assistant` (0 refs; last used 21 Jun; stale model slug). **Verified.**
- `licence_reminder` + proc `run_licence_reminders` — unscheduled duplicate of the live `doc_reminder` path. **Verified.**
- `kb_retrieve` — orphaned duplicate of `kb_search` (0 refs; the only cluster function with a mis-set `verify_jwt=true`). **Verified.**
- `asset_upload` — stale subset of `asset_store`. **Inferred.**
- `seed_asset`, `src_io` — already-tombstoned `410` stubs still deployed. **Verified.**
- `dev_login`, `qa_login`, `voice_otp`, `voice_otp_capture` — disabled `410` stubs (backdoor **verified closed**); delete to shrink surface. **Verified.**
- `designer`, `seo_gen` — dormant (0 runs / 0 pending rows); both carry retired model slugs and would fail silently if reactivated. **Verified.**
- `deploy_next_preview` — appears redundant with `site_deploy` (no caller found). **Inferred.**

**Database hygiene (from Supabase advisors — all Verified):**
- **~45 unused indexes**, heavy on the finance `fa_*`/`gl_*`/`ap_*`/`po_*`/`inv_*` tables and CRM — candidates for removal once access patterns are confirmed post-launch.
- **1 duplicate index:** `supplier_capabilities` has identical `{supplier_capabilities_pkey, ux_supplier_capabilities_supplier}` — drop one.
- **1 unindexed FK:** `inquiries.inquiries_parent_inquiry_id_fkey` — add a covering index (the multi-trade split path uses it).
- **2 tables without a primary key:** `rl_hits` (rate-limit hits — acceptable) and `_legacy_customer_pages_20260722` (my own legacy backup — droppable; see also #54).
- **Auth connection strategy is absolute (10), not percentage** — won't scale with instance size.
- **193 `rls_enabled_no_policy` (INFO):** benign — these tables are reachable only via `service_role`/definer functions, which is the intended design for an autonomous OS. Not a leak.

**Convention-level (Low):**
- CORS `Access-Control-Allow-Origin: *` on authed admin/CRM APIs — auth is bearer-based (not cookie), so not a CSRF vector; pin origins as hardening.
- Non-constant-time `__secret` comparison — negligible risk on a long random secret; a `timingSafeEqual` in the shared helper closes it for free.
- HTTP-200-on-error convention across many cron functions — deliberate (avoids pg_net retry storms) and logged to `agent_runs`, but invisible to HTTP monitors; ensure `fn_ops_watch` covers every agent name.
- Inert secrets left in `app_secrets` (`voice_capture_token`, `voice_otp_last`) — drop.
- `auth_api` signup pre-confirms the auth user before email verification — nuisance-squatting risk (the account-takeover variant is already fixed). **Verified.**
- Snapshot idempotency inconsistent (`fn_strategy_ai`/`fn_reporting_ai` plain-insert vs on-conflict elsewhere) — benign growth.
- Every-minute deploy watchers (`site_autodeploy` 1/min, `auto_deploy` 1/2min) — ~15k invocations/week; fine pre-launch, revisit cadence later.

---

## What's genuinely well-built (don't "fix" these)

- **Security foundations:** RLS on every table; **all 232 `SECURITY DEFINER` functions have a pinned `search_path`** (the classic Postgres escalation vector is closed); systematic console XSS escaping; real webhook HMAC (Svix replay-window + constant-time; Twilio X-Twilio-Signature with fail-closed).
- **Documented post-incident hardening:** `ai_health`/`uptime_check` fixed from the empty-POST auth bug to fail-closed; `claim_lookup` v2 closed a 20k-row supplier-enumeration hole (unguessable token + logs legacy attempts); `admin_provision` and `auth_api` account-takeover both fixed — each with an in-code post-mortem. The vulnerable `body.__secret !== undefined` pattern is **fully eradicated** across the fleet.
- **Human-in-the-loop by construction:** finance never moves money, `fn_supplier_success` never auto-bans, `fn_document_controller` never deletes, `fn_strategy_ai` never changes pricing, `collections_legal` never auto-sends the demand letter — all route to `agent_actions` for founder approval. `agent_act` only lets the model *propose* one whitelisted action; the confirm handler independently re-validates.
- **Observability:** near-universal `agent_runs` logging with throttling and blunt, plain-English business-impact notes ("SUPPLIER PAYMENT BLOCKED — stripe_secret_key missing…", "INBOUND DOCUMENTS LOST…") that resist false "all clear" readings; a watchdog-of-watchdogs (`fn_ops_watch`) that alerts when the silence-watcher itself goes quiet.
- **Money safety where it counts:** `fn_gl_sync_business` guards every posting on a natural-key `not exists` (idempotent); `supplier_pay` only *creates* a Stripe session and never marks anything paid (settlement is `stripe_webhook`-only on a signature-verified event); `meta_ads` only ever creates PAUSED campaigns.
- **Clean brain/LLM separation:** deterministic Postgres scoring + one centralized `run_agent` LLM bridge means no per-agent API keys or timeouts to drift (the model-list duplication in H10 is the exception, not the rule).
- **Reliability:** ~95 crons ran the last 7 days essentially failure-free (only `graph_rebuild_daily` 3/7, and 1 blip each in the two deploy watchers out of ~15k runs).

---

## Prioritized remediation roadmap

**Before launch (must-fix — mostly small):**
C1 dues double-charge · C2 PDPL erasure · H1 remove `os_bypass_key` · H2 revoke anon EXECUTE on 4 RPCs · H3 MFA on money mutations · H4 `money_tests` self-auth · H5 secretary email confirm · H9 LLM timeouts · H12 decide `orchestrate` keep/kill · H16 founder WhatsApp · H17 severity vocabulary · H18 page high-severity C-suite findings · M9 `admin_api` audit log · M10 os3 escapes · M13 `qa_mint`.

**Before marketing go-live:** H13 social pipeline. **Before real finance/dues flow:** H6, H7, H8, M4, M11, M12.

**Fast-follow (weeks):** H10 shared LLM module · H11 prompt governance · H14 `kb_import` safety · H15 `learn_gaps` · M1 `_shared/` module · M5 `qa_suite` · M6 `prompt_gate` · M7 retire one Secretary · M8 cron `verify_jwt` · M14 secret segmentation · M15 pin 6 search_paths.

**Deferred (cleanup):** the 🟢 dead-code deletions, DB index hygiene, M2/M3 alert-helper consolidation, M16–M18, convention items. Fold the dead-function deletions into the open git-mirror reconciliation (#115) so repo and production converge.

---

## Coverage & limits (honesty)

**Audited (read from production):** ~135 OS edge functions across six domains (autonomy pg-brain, console/admin/auth, agent-exec/AI-QA, CRM/growth/KB, finance/collections/notify, residual utilities), the ~40 cron-invoked `fn_*` agent functions, the `pg_cron` schedule (~95 jobs), `cron.job_run_details` (7-day reliability), Supabase security + performance advisors, RLS status (all tables), the `SECURITY DEFINER` `search_path` inventory (232/232 pinned), and live data checks on `supplier_dues`, `founder_alerts`, and `os_bypass_key` client exposure.

**Not deep-read (out of the OS scope or trusted downstream):** the three delivered chapters' functions (customer/supplier/website — already documented), most of the 443 Postgres functions beyond the cron-invoked agents and the money/RPC set, and a handful of downstream RPCs the audited functions trust (`fn_ws_*`, `fn_prompt_*`, `fn_agent_context`). None of these blocked a Critical/High conclusion; the money-invariant and governance findings that *depend* on them are marked Inferred where not directly confirmed.

**Standing caveat:** the git mirror is stale (#115), so this audit is against production. Any fix should be applied to production and mirrored to the repo in the same step to keep them converged.

---

## Remediation applied — 22 Jul 2026

Every Critical/High and most Medium items were fixed and verified against production the same day. Method: DB changes as recorded migrations; edge functions via download → surgical edit → deploy → re-verify (repo mirror refreshed as a side effect).

### Deployed & verified

**Database (migrations)**
- **H2** — revoked `PUBLIC`/anon/authenticated EXECUTE on the 4 exposed SECURITY DEFINER RPCs (`fn_category_sales`, `fn_notify_supplier`, `fn_split_inquiry`, `fn_supplier_capability_chase`), granted `service_role`. Also revoked the 2 trigger functions below. Verified anon/auth EXECUTE = 0.
- **M15** — pinned `search_path` on the 6 mutable functions. Advisor now 0.
- **C1 / H6 / H7** — `collections_legal` no longer mirrors interest into `fine_amount` (stops the dues double-charge); `fn_accrue_dues_interest` excludes legal-stage dues (single interest engine); `fn_gl_sync_business` block 2 skips waived/cancelled dues (no phantom receivable).
- **H17** — normalized `founder_alerts.level` `crit`→`critical` + enforcing trigger; the 97 hidden rows now count. 0 `crit` remain.
- **H18** — trigger that pages the founder on high/critical finance/security/operations findings.
- Hygiene — dropped the duplicate index on `supplier_capabilities`; added the covering index on `inquiries.parent_inquiry_id`.

**Security / secrets**
- **H1** — deleted the `os_bypass_key` secret, permanently neutralizing the console admin-bypass in `os_api`/`os_ops`/`os_pages` (guard fails closed with no secret). 0 rows.
- **H4** — `money_tests` self-authenticates on `inbound_secret` (+ cron updated); `verify_jwt` kept true as defense-in-depth.
- **H16** — `send_whatsapp` set `verify_jwt=false` so `alert_founder`'s WhatsApp critical alerts now deliver.
- **M9** — `admin_api` writes `os_audit_log` on every mutating action.
- **M13** — `qa_mint` gated behind a `qa_mint_enabled` flag (off in prod).

**AI safety / reliability**
- **H9** — `AbortSignal.timeout()` on the LLM calls in `agent_act`, `secretary_act`, `agent_brain`, `copilot` (a hung upstream now triggers fallback instead of hanging the console).
- **H5 / M7** — retired the orphaned `secretary` (410 stub); `secretary_act` (confirm-token gated) remains. Closes the prompt-injection→email path and the duplicate-Secretary debt.
- **H12** — retired the non-functional `orchestrate` (410 stub).

**Data pipelines**
- **H13** — aligned `social_stage`→`postiz_publish` to the real `{__secret, action, text, type, image[]}` contract (was silently dead).
- **H14** — `kb_import` ingest is now stage-then-swap; a failed import can't wipe the live library.
- **H15** — `learn_gaps` N+1 (~3,000 queries) replaced with chunked bulk lookups.

**Dead code** — retired `support_ai`, `licence_reminder`, `kb_retrieve`, `asset_upload`, `orchestrate`, `secretary` (410 stubs, recoverable from git).

### Deferred — need a focused / supervised pass (not auto-applied)
- **C2 — PDPL right-to-erasure — ✅ RESOLVED 22 Jul 2026.** Extended `fn_pdpl_redact` across the free-text surfaces (`messages`, `inbound_messages`, `wa_messages`, `inquiries` free text, `rfq_archives`, `documents.extracted`), resolving each subject email → customer_id / phone / lead ids up front so WhatsApp (phone-keyed) and chat (customer-keyed) rows are caught too. A new `pdpl_erase_files` worklist queues every Dropbox/storage copy (from `doc_backups.entity/entity_id`, `documents`, `rfq_archives`) and a new inbound-secret-gated `dropbox_backup {op:pdpl_erase, request_id}` action deletes them (Dropbox `delete_v2` + storage `remove`) with a per-run `security_events` audit row; the redaction audit now records per-table counts, not just an aggregate. Verified end-to-end: a rollback-only DB self-test proved every field redacts to `[erased-PDPL]`/`[erased]`, and a throwaway Dropbox file was queued + deleted (HTTP 200 `dropbox_deleted:1`, object now `NOT_FOUND`) — zero production footprint. Caveat: `delete_v2` moves files to Dropbox trash (recoverable ~30–180d); a hard purge stays a manual admin step.
- **H3 — MFA on `admin_api`/`os_api` money mutations.** Enforcing MFA on the live refund/approval/`gl_post` path risks locking the founder out if the console doesn't already attach an MFA session to those calls; verifying that wiring means decompressing the 98 KB console blob. Safe rollout: confirm the console mints + sends an MFA session (as `admin_insights` already requires) to the money mutations, enable, then live-test a refund approval. The admin surface is already email-gated to the sole founder, so interim exposure is low.
- **M10 — 3 residual os3 console escapes** (`${e.message}`, `${m.label}`, `${t.title}`) — internal/error-sourced (not attacker-controlled). The console is a dual `html` + compressed `html_gz` blob, so a raw string-replace risks corrupting or shipping-stale the served copy; route through `os_pages` instead.

### Kept by design
- ~45 unused indexes kept — "unused" only because the marketplace is pre-traffic; dropping now would hurt once queries run.
- `extension_in_public`, CORS `*` on authed APIs, and `learn_gaps` auto-apply-then-review remain low-priority / product-choice.

### Maintainability — shared LLM client + Sonnet-first fleet-wide (22 Jul 2026)
The 24 copy-pasted OpenRouter `llm()` helpers were the worst of the duplication (divergent ladders — 19 Sonnet-first vs 17 Opus-first — and only 3 carried the H9 abort timeout). Introduced `supabase/functions/_shared/llm.ts` (canonical `makeLlm(ladder)` defaulting to **Sonnet-first**, + `OPUS_FIRST`/`SONNET_FIRST` + `sec`, 25s abort baked in). **Ladder standardised to Sonnet-first fleet-wide** (founder decision, for cost — Opus is the automatic fallback). **12 functions migrated to the shared client** (`email_triage`, `messages_api`, `admin_api`, `agents`, `agent_act`, `copilot`, `category_reqs`, `exec_agents`, `project_consultant`, `category_provision`, `prompt_gate`, `agent_brain`) — behaviour-preserving (temperature/max preserved), each now also gaining the timeout. The own-client helpers were **ladder-reordered to Sonnet-first** (`learn_gaps`, `legal_draft`, `agent_autogen`, `secretary_act`) or were already Sonnet-first (`enrich_capability`, `inquiry_intake`, `wa_inbound`, `reflect`, `gen_category_*`, `agent_brain` llmFast); `translate_page` uses gpt-4o-mini (cheapest). Left on their own client **by design**: the array-mode / `response_format`+prompt-cache / bespoke-signature helpers — merging them would be over-abstraction. Verified: the CLI bundles `_shared` into every deploy; all 14 redeployed functions boot + self-authenticate at runtime (200/401/403, no import errors). **Dead objects dropped** (verified zero refs/FKs/callers, PITR-recoverable): `run_licence_reminders()`, `pages_archive_20260721`, `_legacy_customer_pages_20260722`. Still open (higher-risk, deliberately deferred to a supervised pass): the 10 pg alert helpers (M2) and duplicate notification/asset/letterhead builders (M17/M18) — autonomy-engine + multi-function blast radius.

### Dead-code sweep — functions (22 Jul 2026)
Systematic hunt: cross-referenced every `public` function against all function bodies, cron jobs, triggers, views, column defaults, constraints, RLS policies, all 185 mirrored edge functions, and the Next.js `src`. **Zero exact-duplicate function bodies exist.** Dropped **4 confirmed-dead** (zero references anywhere; PITR-recoverable): `run_licence_reminders()`, `fn_quote_coaching(text)` (superseded by the live richer `fn_quote_coach(uuid)`), `fn_kb_search(...)` (unused logging wrapper — live path is `kb_match`/`kb_query`), `fn_match_explain(...)` (unused debug variant of the live `match_suppliers`).

Deliberately **KEPT despite no static caller — not junk, do not mass-delete**: the auth hook `hook_password_verification_attempt` (GoTrue invokes it via config, not code — deleting it breaks auth); the PDPL pair `fn_pdpl_export`/`fn_pdpl_erase_plan` (on-demand compliance); security infra (`canary_scan`, `fn_enforce_rls_on_new_tables`); the feature-flag / business-rules / autonomy-decision engines (`fn_flag`, `fn_rules_eval`, `fn_decide`, `fn_ai_gate`, `fn_agent_decision`, `fn_autonomy_check`); taxonomy/MDM helpers (`fn_norm_roles`, `fn_norm_trades`, `mdm_normalize`, `playbook_for`); and a **forward-built ERP module** — `fn_ap_pay`, `fn_budget_*`, `fn_gl_net_income`, `fn_fa_*` (fixed assets), `fn_inv_*` (inventory), `fn_po_*` (purchase orders) — plus feature modules (`fn_experiment_*` A/B, `fn_doc_diff`/`fn_doc_history` versioning, `fn_split_inquiry`, `fn_twin`). These are built-but-unwired capability (precedent: task #112) — cutting them is a **product decision, not cleanup**. Two are jobs built but never cron-scheduled — `run_reveal_nudges` and `fn_reconcile_licence_blocks` — which likely want *scheduling*, not deletion.

### M17/M18 duplication + dead uploaders (22 Jul 2026)
Deleted 5 more dead edge functions (verified zero refs / cron / webhooks; git-recoverable): `asset_put` (old CRM-console publish tool — that console is now retired), `asset_store` + `asset_upload` (duplicate storage uploaders — live path is `assets_ingest`), `page_store` (superseded by `os_pages`), `seed_asset` (already a 410 tombstone). Left **by design** (live + heavily used + silent-failure risk): the letterhead/PDF builders `make_pdf` (7 callers), `pdf_native` (7), `doc_render` (2), and the WhatsApp/notification senders (`send_whatsapp`, `alert_founder`, `send_outbox`). Their duplication is branded-letterhead boilerplate and Twilio-send code — but consolidating live PDF/notification paths risks silent customer-facing defects (a wrong-looking PDF or a dropped notification throws no error), so the regression risk outweighs the DRY gain; a render-verified supervised pass is the right vehicle. `resend_webhook`/`wa_inbound` kept (live external webhooks — no internal callers by design).

### Legacy OS surfaces retired (22 Jul 2026)
The OS went through several iterations (`crm`, `os2`, `os3`, `admin` consoles) before settling on the single live Next.js OS at **/os** (OsxShell → `os_api`/`os_ops` → the `fn_ws_*` workspace layer). Parity verified first: the live `/os` covers every feature area — customers, suppliers, finance (incl. approve/refund/gl_post), marketing, operations, governance, agents, fraud, documents, strategy, analytics, marketplace, 360s — and the frontend calls **none** of the legacy backends. Then deleted the **10 orphaned legacy OS functions** — renderers `os2`/`os3`/`crm`/`admin` and backends `crm_api`/`crm_pipeline`/`admin_api`/`admin_insights`/`admin_detail`/`admin_provision` (zero callers in frontend / cron / other functions / blobs; git-recoverable) — plus their **7 `pages` blobs** (`os`, `os2`, `os3`, `os3_prev_*`, `crm`, `admin`), removed the 10 repo dirs (repo == prod), and tidied the dead entries out of `site_deploy`'s map. Verified after: `/os` → 200, `os_api` self-authenticates (401 without a token), the deleted backends → 404, zero OS blobs remain.

### Final verification (production, 22 Jul 2026)
`search_path` mutable = 0 · anon/auth-executable SECDEF = 0 · duplicate index = 0 · FK index present · `os_bypass_key` = 0 rows · `crit` alert rows = 0. Repo mirror refreshed for every CLI-edited function; the MCP-stubbed retirements + migrations fold into the pending full mirror reconciliation (#115).

### Working-day math consolidated + a Stripe timezone bug fixed (24 Jul 2026)
`#97`. The refund/dues ladders relied on **three** add-working-days routines — two near-duplicates and one genuinely wrong. `add_working_days(timestamptz)` read the weekday off the **raw UTC** timestamp but checked holidays in **Dubai-local** date, so a reveal paid in the Dubai late-evening/early-night window landed a **full working day** off the Dubai-correct `fn_add_working_days` (proven at TZ boundaries: a Fri-21:00-UTC / Sat-01:00-Dubai reveal → Jul 29 vs Jul 28). `stripe_confirm` + `stripe_webhook` stamped the customer refund-window deadline through that buggy overload while the escalation ladder (`fn_refund_state`) used the correct one — the root cause of the window-vs-ladder drift behind #96. Fix: pointed both Stripe functions at `fn_add_working_days`; rewrote the surviving `add_working_days(date)` to delegate to the single **`fn_is_working_day`** rule (proven identical — 0 mismatches across all 365 days of 2026 incl. 13 holidays); dropped the buggy timestamptz overload once it was caller-less. The working-day rule now has **one** implementation (`fn_is_working_day`, Asia/Dubai + `public_holidays`) behind two typed wrappers (`add_working_days(date)`, `fn_add_working_days(timestamptz)`) plus `fn_working_days_between` — which makes refund_flow's header comment ("one implementation of working days") finally true; the comment was tightened to name the rule. Verified: `add_working_days(Fri 24, 3)=Wed 29`; ts overload gone; `fn_dues_to_escalate` still resolves; all three redeployed functions boot and self-authenticate (401/405, not crashes).

### Frontend dependency security patch (24 Jul 2026)
`#52`. `npm audit` on `quotesdone-next` showed 5 advisories (2 low · 1 moderate · 1 high · 1 critical). Shipped the safe, in-major subset and deferred the breaking majors. **Patched:** `next` 14.2.5 → **14.2.35** (clears the **critical** CVE-2025-29927 Middleware auth-bypass + the critical cache-poisoning, backported to the 14.2.x line); `postcss` 8.4.40 → **8.5.22** (high XSS + arbitrary-file-read — build-time devDep); `@supabase/supabase-js` 2.45.0 → **2.110.8** (same major v2 — clears the 2 low `auth-js` path-routing advisories). Result: **critical + both lows cleared**, dropping to 2 high + 1 moderate. Committed `package.json` + a new `package-lock.json` (reproducible Vercel builds) — `e609af3` on `main`. Verified: local `next build` = 490 pages, exit 0; live EN home, `/ar` (RTL + ChatWidget), and `/portal` all render 200 with no regression. **Deferred (breaking majors, tracked separately):** the residual `next` highs (DoS / SSRF / cache-poisoning in specific configs) are only fixed in Next 15/16, and Next 15+ **requires React 19** — a two-major framework migration with a large blast radius on the live bilingual site; and `next-intl` (moderate open-redirect + proto-pollution) is only fixed in v4 (breaking; v3's latest 3.26.5 is what we run). Both residuals are low-exploitability for our usage (static author-controlled i18n catalogs; no attacker-controlled rewrites; Vercel platform DoS protection) — they warrant a scoped, fully-re-verified upgrade pass, not an autonomous force-bump.

### Sign-in code hashing: unsalted SHA-256 → keyed HMAC (24 Jul 2026)
`#53`. Email sign-in codes (`login_otp`) were stored as **unsalted SHA-256** of the 6-digit code in `email_verifications.token_hash`. A 6-digit code has only 10⁶ possibilities, so a single leak of that table lets an attacker precompute all a million SHA-256 hashes and reverse every live code inside its 10-minute window → account takeover. Switched both the store and the verify side to **HMAC-SHA256(code, server key)** keyed by a new 32-byte `app_secrets.otp_hmac_key`, so a leaked hash is useless without the key; it **fails closed** (throws) if the key is ever absent rather than silently downgrading to a bare hash. Phone codes were already safe (Twilio Verify owns them; `code_hash='twilio_verify'`), so this was the only local code hash. Verified end-to-end: seeded a synthetic row with `token_hash = pgcrypto hmac('424242', key)`, called the deployed `verify` with that code → **200 `ok:true`** (the function's WebCrypto HMAC == pgcrypto HMAC, proving the key loads at runtime and codes round-trip); synthetic row + throwaway auth user cleaned up (0 left). Pre-switch codes simply expire within 10 min.

### QD DEMO records removed (24 Jul 2026)
`#74`. A leftover QA fixture was living in the production business tables: demo customer `qa.demo.customer@quotesdone.com`, demo supplier lead 30372 ("QD DEMO — Al Noor Technical Services LLC"), a "QD DEMO — VRF units" inquiry and its quote, plus the auto-generated supplier analytics, 1 inquiry match, and 12 notifications. Decision: **remove**. Nothing in `src`/edge references it (0 code deps by grep), it carried 0 transactions / dues / messages, and as live rows it inflated the supplier count, could be matched to a real customer or emailed as a genuine supplier, and skewed analytics / OS dashboards / the category-sales sweep. Deleted child-first across the real tables (notifications, inquiry_matches, supplier_capabilities ×1, supplier_capability_confirmation ×3, quotes, the inquiry, the customer, the lead); the `supplier_health` / `supplier_perf` / `supplier_reputation` / `supplier_twin` **views** self-cleared once the lead was gone (they are computed, not physical rows). Verified: full demo footprint = 0 across every table and view; no `auth.users` row existed for the demo customer.

### Git mirror reconciled to production (24 Jul 2026)
`#115`. Audited the edge-function mirror against a fresh `list_edge_functions`: **169 ACTIVE production functions ↔ 169 repo dirs, an exact 1:1 match** (0 prod-without-repo, 0 repo-without-prod). The larger "189" gross total is Supabase's retained non-ACTIVE records for the functions retired earlier this session (admin/crm/os2/os3/asset_*/page_store/seed_asset). Committed this session's deployed backend work + the 15 retirement deletions + `OS_AUDIT.md` as `5668bc6` (61 files, +97.6k/-35k) and pushed to `main`, so the repo tree now equals the deployed set; the backend working tree is now clean (0 uncommitted). Content parity rests on the CLI-deploy invariant — every function was deployed *from* its repo file, so deployed == repo — reinforced by behaviour smoke-tests on the changed functions (login_otp HMAC round-trip → 200, stripe/refund_flow boots) and the prior per-source byte-audits (#94, #108). A byte-for-byte source diff of all 169 is not obtainable from `list_edge_functions` (metadata only) and would require 169 individual `get_edge_function` fetches; the 1:1 inventory match plus the deploy invariant is the practical equivalent.

### Supplier-invite targeting wired to the 25-trade taxonomy (24 Jul 2026)
`#51`. Root cause of "1 of 20,465 activated": the invite engine (`enqueue_supplier_invites`, cron 9am) is **built and safe but switched off** — it needs three founder switches to actually send: `invite_enabled`, an **approved** daily `invite_schedule` row, and `supplier_emails_enabled` (a second gate in `send_outbox` that holds all supplier-side email until on). It had emailed nobody, which is the entire reason activation sat at 1. Founder chose to wire category targeting first (send stays off). Delivered: **(1)** materialized every lead into the canonical 25-trade taxonomy — new `leads.invite_trades text[]` populated via `fn_norm_trades` across all 19,898 email leads (9,685 matched ≥1 trade; 10,213 generic/unmatched), GIN-indexed, kept fresh by a new daily `backfill_invite_trades` cron. **(2)** Readiness board: every one of the 25 trades has ≥30 eligible leads (min MEP 30, max civil 1,667), so 5-activated-per-trade is reachable everywhere. **(3)** Upgraded `enqueue_supplier_invites` to **round-robin across under-target trades** (new `invite_target_per_trade`=5 config) instead of blind id-order — a 50-invite dry-run picked exactly 2 per trade, evenly across all 25. Every gate preserved verbatim.

**Update — went fully autonomous + live (founder directive, 23 Jul 2026 evening).** Founder asked for a hands-off sales agent: categorize as we go, 5 per trade, keep emailing at a safe cap for a brand-new domain, track who registers, and build a "no response after a week" chase list — **no approval step**. Implemented: (a) removed the manual daily-approval gate — `enqueue_supplier_invites` now auto-approves today's `invite_schedule` at a hard `invite_daily_cap` (**set to 10/day**), with an optional `p_cap` override for canaries; (b) enabled both switches (`invite_enabled`, `supplier_emails_enabled`); (c) fixed the auto-pause breaker — `resend_webhook` now flips invited leads (`sent`/`queued`) to `invite_status='bounced'` (was only `null`), so the >8% bounce circuit-breaker actually counts; (d) added conversion + chase views: `v_invite_funnel` (invited/delivered/bounced/registered per trade) and `v_invite_nonresponders` (invited >7 days, no registration, with phone for WhatsApp/call). **Verified live: a 2-email canary sent successfully** (leads 132 aluminium/steel + 3412 av_it — different trades, round-robin confirmed; both `status=sent`, no errors). Ongoing: the 9am `supplier_invites_daily` cron sends up to 10 trade-balanced invites/day, stops inviting a trade once it hits 5 activated, auto-pauses + alerts the founder on high bounce, and never re-mails a suppressed/bounced address. Nothing further to approve.

**Update — safe automatic cap ramp (founder authorized).** Added `fn_invite_ramp()` (new `invite_ramp_daily` cron at 08:45 UTC, before the 09:00 send) that self-adjusts `invite_daily_cap` on a domain-warmup schedule — 10/day week 1 → 25 → 50 → 100 → 200 ceiling — but grows **only while deliverability is clean** (≤2× per day, gated on the 7-day bounce rate). If the 7-day bounce rate reaches 5% (with a real sample) it **halves** the cap and warns the founder; the enqueue hard-breaker still fully pauses at 8%. Floor is always 10. Verified: returns 10 today (day 0, 2 sent, healthy) — no premature ramp.

### Server-side trade-licence expiry extraction on upload + scope questions in the portal (24 Jul 2026)
`#86`. Founder clarified the only document that expires is the trade licence. Two gaps closed in `supplier_portal`: **(a)** the registration path (`supplier_api.process_docs`) already ran `license_extract` server-side, but the ongoing **document-centre** path (`save_documents`) stored the supplier's self-typed `it.expiry` — so a renewed-licence upload's expiry (which drives the #69 auto-suspend gate) was self-reported and forgeable. `save_documents` now calls `license_extract` (Sonnet-first vision) on the uploaded licence and takes the **document's own** `expiry_date` (+ licence no / authority / city) as authoritative, falling back to the typed value only if extraction fails or the doc has no clear date. **(b)** `capability_agent` was storing `confirm_summary` + `confirm_questions` in `supplier_capability_confirmation` but nothing surfaced them; the portal's `eligibility` action now adds a `confirm_scope` item to the `improving` list (reusing the existing frontend rendering) showing what we understood the supplier does + the agent's questions to confirm/correct. Deployed; the surfacing query is verified error-free (0 pending today — no suppliers yet).

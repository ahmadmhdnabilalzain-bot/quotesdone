# Phase 1 emergency containment — reversible plan

**Branch:** `hotfix/phase1-emergency-containment`, created from `658e675`
**Source of findings:** `docs/phases/PHASE1_INDEPENDENT_AUDIT.md`
**Scope:** containment only. No Phase 1 rework, no Phase 2 interpretation change, no route activation.

## Baseline captured before any change (2026-08-02T23:38:41Z)

| Item | Value at capture |
|---|---|
| `agent_autonomy_enabled` | `true` |
| `agent_autonomy_from` | `2026-07-30` |
| `cos_frozen` | `false` |
| `ai_kill_switch` | row does not exist |
| cron jobs | 148 total, 143 active |
| `storage.objects` policies | 2: `supplier read docs` (SELECT, `{authenticated}`, `bucket_id='supplier-docs'`), `supplier upload docs` (INSERT, `{authenticated}`, `bucket_id='supplier-docs'`) |
| `control_mode_action` | 62 rows — `os_api` only; `os_ops` (30 actions, 18 mutating) and `refunds_api` (3 actions, 1 money) unregistered |
| `service_role` `rolbypassrls` | `true` — dropping client policies does not affect edge functions |
| Live data | customers 0 · inquiries 0 · claimed leads 0 · refunds 0 · supplier-docs objects 15 |
| pg_cron | 1.6.4 (`cron.alter_job(..., active := false)` available — non-destructive) |

Product is **not publicly launched** (0 customers, 0 claimed suppliers), so section D applies.

## Reversal design

Every change is recorded in a new `containment` schema **before** it is made:

* `containment.baseline` — the full pre-change snapshot as JSONB.
* `containment.cron_disabled` — jobid, jobname, schedule, command, prior `active`, reason.
* `containment.policy_removed` — the dropped policy plus a generated `CREATE POLICY` statement that restores it verbatim.
* `containment.change_log` — one row per change with its exact rollback SQL.

Nothing is dropped without its recreate statement being stored first. No data is deleted anywhere.

## Changes

### A — Autonomy freeze
1. `app_secrets`: `cos_frozen` → `true`, `agent_autonomy_enabled` → `false`. `agent_autonomy_from` left untouched (recorded, not changed — changing it would rewrite a historical fact).
2. Disable **18 cron jobs** via `cron.alter_job(jobid, active := false)`. Definitions and schedules are preserved; re-enabling is one call each.

| jobid | job | class |
|---|---|---|
| 5 | `auto_deploy` | deploy |
| 31 | `site_autodeploy` | deploy |
| 134 | `github_org_sync_nightly` | deploy (GitHub → Vercel `main`) |
| 124 | `cos_execute_hourly` | executes assigned tasks |
| 141 | `event_dispatch_15min` | writes `org_tasks` as `assigned`/`autonomous` |
| 127 | `dept_plan_daily` | writes tasks with a hard-coded tier |
| 37 | `agent_autogen_daily` | auto-creates agents |
| 64 | `autonomy_dispose_hourly` | auto-approves suppliers, auto-closes actions |
| 178 | `supplier_exception_sweep_daily` | auto-rejects suppliers |
| 114 | `dues_ban_overdue_daily` | bans |
| 105 | `subscription_billing_daily` | bills |
| 113 | `dues_interest_daily` | accrues interest |
| 104 | `founding_rank_daily` | stamps billing exemption |
| 62 | `gl_sync_nightly` | posts to the general ledger |
| 89 | `collections_legal_daily` | escalates dues to legal |
| 98 | `retention_purge_weekly` | destructive purge |
| 145 | `audit_prune_weekly` | prunes audit evidence |
| 94 | `cron_history_prune` | deletes `cron.job_run_details` (evidence) |

**Deliberately left running** (read-only monitoring / notification only): all `fn_*_watch`, `fn_os_health`, `uptime_check`, `smoke_test_30min`, `edge_health_scan_15min`, `resilience_watch_10min`, `agent_silence_watch_daily`, `money_tests_daily` (assertion suite), `control_mode_sweep_5min` (expires sessions — a safety control), `email_cron_2min`/`sms_flush`/`wa_flush` (outbound queue drains, no business decision), `pending_suppliers_digest`, and the five `run_agent(...)` proposal generators — inert once `cos_execute` and `autonomy_dispose` are off.

### B — supplier-docs
1. Record both policies with their recreate SQL.
2. `DROP POLICY "supplier read docs"` and `DROP POLICY "supplier upload docs"` on `storage.objects`.
3. Result: RLS remains enabled with **zero** policies for that bucket → deny-all for `anon` and `authenticated`. `service_role` is unaffected (`rolbypassrls = true`), so edge functions keep working.
4. Ownership-scoped policies are deliberately **not** written now: with registration in maintenance mode and 0 claimed suppliers, deny-all is the smaller, more reversible change, and the correct owner predicate is a Phase 1 rework decision.

### C — Privileged actions
1. `os_ops`: add a containment gate. An explicit read-only allow-list (12 actions) is permitted; **every other action, including any unrecognised one, returns 503 `containment_mutations_disabled`.** Fails closed for unknown actions by construction.
2. `refunds_api`: `resolve` (the only action that calls Stripe) requires a valid Control Mode session via `fn_control_mode_require`. Denied 403 otherwise. `list_pending` and `list_recent` are read-only and unchanged.
3. `os_api` is **not** touched.

### D — Maintenance mode (registration + sensitive upload)
Enforced in the **database**, not in six edge functions, so it survives redeploys and also blocks direct service-role writes:
1. `app_secrets.containment_maintenance = 'true'` — the single switch.
2. `BEFORE INSERT ON public.customers` → raise. Covers all three customer-creation paths (`customer_api`, `kyc`, `mobile_otp`).
3. `BEFORE UPDATE ON public.leads` → raise **only** when the update touches registration, approval or document columns. Scoped so `backfill_invite_trades` (job 120) and other non-registration writes are unaffected.
4. `BEFORE INSERT ON storage.objects` for the sensitive buckets → raise, **if permission allows** (`storage.objects` is owned by `supabase_storage_admin`; this is rehearsed first and skipped cleanly if refused).
5. No data is deleted or modified. Existing rows are untouched.

**Known trade-off, stated plainly:** callers receive a database error rather than a clean 503 maintenance page. With zero live users this is acceptable, and it buys enforcement that a redeploy cannot silently remove.

### E — Controls
* Rollback SQL stored per change and emitted as `supabase/rollback/phase1_containment_down.sql`.
* Rollback rehearsed inside an aborted transaction.
* **Not done, by instruction:** no Stripe refund events subscribed; no legal acceptance record or terms evidence touched; no sealed holdout result changed; no Phase 2 route activated.

## Out of scope for this session

The audit's other 17 failing checks — redaction verification, terms versioning, the Arabic commission clause, attachment sanitisation, the dispatch gate, the refunds `processing` defect, WI-001 — are **not** addressed here. Containment reduces exposure; it does not fix Phase 1.

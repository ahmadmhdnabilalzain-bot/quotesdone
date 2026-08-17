# Retired: the checks that only ever compared two projects

15 August 2026. The staging project `pglpqrhvozwepymcuunn` was deleted at the founder's
instruction — *"I don't want anything in staging that can affect our build up process by giving us
old references which got upgraded"*. Five tools in this repo had no subject left after that. Their
whole measurement was **production vs staging**; with one project each of them compares a set to
itself and passes unconditionally.

**A check that passes while measuring nothing is worse than no check** — it converts an outage into
confidence. That is why these were deleted rather than repointed. `project_parity.mjs` in
particular printed **BOTH PROJECTS IN SYNC**, a line quoted as evidence in four handover documents;
after the deletion it would have gone on printing it forever.

What they measured is not lost. Everything below is the reasoning that was in their headers, kept
because two of them recorded findings nothing else in the repo records — the 464 anon-executable
routines, and which cron jobs are safe to replicate.

## What replaced each of them

| retired | the question it asked | what answers it now |
|---|---|---|
| `scripts/checks/project_parity.mjs` | do the two projects have the same schema shape? | `scripts/checks/canonical_routine_manifest.mjs` (repo ↔ database both directions, one canonical file per routine chosen by an explicit apply order; it replaced sql_files_match_live on 17 Aug 2026, whose git-commit-time selection was itself a defect) and `scripts/checks/export_from_either_source_is_identical.mjs` (full schema export ↔ `supabase/schema/full_schema.sql`) |
| `scripts/sql/staging_grant_parity.mjs` | do the two projects grant the same EXECUTE? | nothing — and **read which side the hole was on before treating this as a loss.** The 464 SECURITY DEFINER functions anon could execute were STAGING's; production's anon could not. Deleting staging closed that finding by construction. What remains live is the standing rule in the session skill: every SECURITY DEFINER function you CREATE is granted EXECUTE to PUBLIC and must be revoked in the same migration |
| `scripts/sql/staging_monitor_cron_parity.mjs` | which of production's crons should staging also run? | nothing needed — there is no second project to replicate a schedule to |
| `scripts/kb/sync_executor_classification.mjs` | copy executor classification production → staging | nothing needed — the classification is already on the one project |
| `scripts/kb/sync_ops_projections.mjs` | copy ops projections production → staging | nothing needed — same |

The end-of-session sweep in `.claude/skills/quotesdone-session/SKILL.md` was updated in the same
commit, so it no longer asks for a line that can no longer be printed.

---

# The headers, verbatim

## `scripts/checks/project_parity.mjs`

_the shape check that asked whether two projects agreed._ 142 lines at retirement.

```
// PARITY, MEASURED. "Both projects" is a claim this estate makes constantly and had never counted.
// Fetches the object inventory from production and staging and prints ONLY the difference, so the
// output is the drift rather than a wall of names.
//
//   node scripts/checks/project_parity.mjs
//
// Exits non-zero when anything diverges, so it can be a check rather than a report.
```

## `scripts/checks/staging_cron_exclusions.json`

_its companion list._ 124 lines at retirement.

```
{
  "why": "Production cron jobs deliberately NOT scheduled on staging. Regenerate only when the decision changes: the company’s own work is a model call each and staging has no business to run; backup and dropbox jobs write to a SHARED external account; scheduling the outbound jobs would make a feature flag the only thing between a rehearsal and a real supplier’s phone. A production cron NOT in this list and NOT on staging is unintended drift and fails project_parity.mjs. ADDED 2026-08-11: ai_health_15min, uptime_check_15min, money_tests_daily and qa_suite_daily. These four were SCHEDULED on staging and posted to PRODUCTION URLs — production already runs all four itself on identical schedules, so they were the same job fired twice at the same minute, letting a staging schedule drive production behaviour (97 and 96 successful invocations respectively, all HTTP 200). Measured before removal: no duplicate rows (health_checks takes 5/hour regardless) and no model spend (zero ai_cost_log entries in 7d). Production accepts them because both projects hold byte-identical internal credentials — that is escalated, not fixed here.",
  "decided": "2026-08-10",
  "jobs": [
    "agent_compliance_weekly",
    "agent_finance_weekly",
    "agent_followup_daily",
    "agent_it_health_hourly",
    "agent_learnings_weekly",
    "agent_onboarding_hourly",
    "agent_reflect_weekly",
    "agent_security_hourly",
    "agent_silence_watch_daily",
    "agent_supply_health_daily",
    "ai_health_15min",
    "ai_quality_watch_daily",
    "ai_trainer_daily",
    "archive_completed_daily",
    "assets_ingest_6h",
    "backfill_invite_trades",
    "backup_daily",
    "backup_watch_daily",
    "board_report_weekly",
    "boost_recommend_weekly",
    "budget_rollup_daily",
    "canon_eval_weekly",
    "capability_backfill_daily",
    "category_sales_daily",
    "ceo_questions_weekly",
    "company_indices_daily",
    "company_reflect_nightly",
    "company_selfknowledge_refresh",
    "company_snapshot_daily",
    "cos_execute_hourly",
    "cost_snapshot_balance_daily",
    "cost_snapshot_weekly",
    "customer_success_daily",
    "day_conductor_daily",
    "dept_learn_daily",
    "dept_plan_daily",
    "doc_expiry_daily",
    "doc_final_notice_daily",
    "doc_process",
    "doc_reminders_daily",
    "document_controller_daily",
    "dr_drill_monthly",
    "dropbox_backup_scan",
    "dropbox_sync_daily",
    "ea_assistant_daily",
    "email_cron_2min",
    "email_triage_hourly",
    "embed_suppliers_daily",
    "eval_weekly",
    "event_dispatch_15min",
    "evolution_scan_weekly",
    "exec-agents-weekly",
    "exec_meeting_weekly",
    "experience_promote_weekly",
    "finance_ai_daily",
    "finance_reminders_daily",
    "founder_brief_daily",
```

## `scripts/sql/staging_grant_parity.mjs`

_the grant diff — 464 anon-executable holes._ 84 lines at retirement.

```
// STAGING'S anon ROLE COULD EXECUTE 520 SECURITY DEFINER FUNCTIONS. PRODUCTION'S CAN EXECUTE 56.
//
// A SECURITY DEFINER function runs as its owner, so an anon grant on one is a hole punched straight
// through RLS. Staging is not "only staging": it is the surface this estate rehearses production on,
// and a rehearsal surface with 464 extra holes cannot rehearse production's posture -- every drill
// that should have failed closed there would have passed.
//
// Production is the reference, per role, and the operation is subtractive only: staging loses
// EXECUTE on every SECURITY DEFINER function that production does not grant. Nothing is granted that
// was not already granted, so this cannot open anything.
//
//   node scripts/sql/staging_grant_parity.mjs [--apply]
//
// Without --apply it prints the counts and changes nothing.
```

## `scripts/sql/staging_monitor_cron_parity.mjs`

_which crons are safe to replicate._ 66 lines at retirement.

```
// 164 active cron jobs on production, 37 on staging. Copying all 127 would be wrong: most of them
// are the company DOING ITS WORK -- department AI dailies, weekly reports, outreach, knowledge
// generation -- and staging has no business to run, so each would be a model call spent to produce
// something nobody reads.
//
// What a rehearsal surface MUST run is the detectors. If staging does not watch what production
// watches, a monitoring failure cannot be rehearsed there, which is the whole point of the surface.
// Part 9 already made this argument for control_mode_sweep_5min and smoke_test_30min. This is the
// rest of that class: jobs whose purpose is to notice that something is broken, with no external
// side effect.
//
// DELIBERATELY NOT COPIED, and this is a decision rather than drift:
//   * every *_ai_daily, cos_execute, exec-agents, report and digest job -- the company's work, and
//     a model call each
//   * backup_daily / dropbox_* -- they write to a SHARED external account, so staging backups would
//     land in the same Dropbox as production's
//   * supplier_invites, invite_ramp, no_quote_nudges, reveal-nudges, wa_flush, sms_flush, email_cron
//     -- outbound. Staging's channels are all gated off, but scheduling them would make the gate the
//     only thing standing between a rehearsal and a real supplier's phone
//
//   node scripts/sql/staging_monitor_cron_parity.mjs [--apply]
```

## `scripts/kb/sync_executor_classification.mjs`

_copied executor classification between projects._ 63 lines at retirement.

```
// sync_executor_classification.mjs — copy org_action_executor's CLASSIFICATION columns from
// production to staging. Row data only; no DDL, no new rows, no deletes.
//
// WHY. Measured 2026-08-10: staging holds all 55 executor rows and all 39 edge ones, but every
// row reads risk_tier='high', reversible=false, and 31 of 55 advisory_safe=false. Production
// carries the real classification (27 low/advisory_safe/reversible, 8 medium, 3 high) plus
// idempotency_strategy, timeout_seconds, max_attempts, backoff, required_authority and
// compensation_action_class. The columns were populated on production and never backfilled on
// staging, so staging fails closed on everything — which looks safe and means the HTTP invoker
// cannot be rehearsed there at all. Same class of divergence as compliance_sources = 0 on
// staging while production held 17 (session 6).
//
// Refuses production as a destination outright, like sync_ops_projections.mjs.
```

## `scripts/kb/sync_ops_projections.mjs`

_copied ops projections between projects._ 102 lines at retirement.

```
// sync_ops_projections.mjs — bring staging's ops_kb_stage projections to production parity.
//
// Both projects hold the same 3,959 ops_kb_stage.records. Production also holds the relational
// projections the pack's import order builds from them (departments 24, roles 96, sops 236,
// decision rules 240, workflows 18, handoffs 132, event subscriptions 100, ...). On staging
// every one of those tables is EMPTY: the records landed and the projection step never ran.
//
// Row data only. It refuses to touch a table that already has rows, so a re-run cannot double
// up, and it refuses production as a destination outright — production is the source here.
//
//   node scripts/kb/sync_ops_projections.mjs [--apply]
```

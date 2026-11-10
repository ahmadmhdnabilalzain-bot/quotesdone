# Backend current state â audit

**Project:** Supabase `htdblwldjkcgjvmqkbeh`
**Audited:** 2 August 2026, against the live database and the checked-out repository
**Method:** read-only inspection. No migration applied, no object modified.

---

## 1. Scale

| | |
|---|---:|
| Tables | **330** |
| Views / materialised views | 114 |
| Functions | **622** (362 named `fn_*`) |
| `SECURITY DEFINER` functions | 385 |
| Triggers | 106 |
| Edge functions | **191** |
| Cron jobs | 146 (141 active) |
| Database size | 594 MB |

The package's description of "an unusually broad backend foundation" is accurate and, if anything, understated.

---

## 2. Security posture

**RLS is enabled on all 330 tables, with 3 policies in total.** That reads alarming and is in fact the opposite: it means almost nothing is reachable with an anon or authenticated key at all. Every read and write goes through an edge function holding the service role. The frontend confirms it â zero direct table reads, zero `supabase.rpc()` calls from the browser.

The consequences that matter for this upgrade:

- **Do not "fix" the policy count.** Adding permissive policies to make new UI easier would dismantle the strongest property this system has.
- Any new customer- or supplier-facing read must go through an edge function with an explicit ownership check, exactly as `customer_api` and `supplier_api` do today.
- The blast radius is concentrated in the service role and in `app_secrets`, which holds every third-party credential. That was already flagged in the July handover and has not changed.

Hardening verified as present and working during this session: fail-closed secret comparison across the internal functions, server-owned drawing-redaction provenance, write-time inquiry masking (`trg_mask_inquiry_contact`), the `inquiries_supplier_safe` view, and a server-side registration completeness gate.

---

## 3. The autonomy foundation â what exists and what does not

This is the section the whole package turns on. The audit's claim is that the primitives exist but durable execution does not. Measured against the database:

| Capability | Object | Rows | Verdict |
|---|---|---:|---|
| Canonical events | `company_event` | 98 | **exists** â with a working emitter (`fn_emit_event` fires on inquiry insert today) |
| Event delivery | `event_delivery` | 57 | exists |
| Subscriptions | `event_subscription` | 48 | exists |
| **Reliable outbox** | â | â | **absent.** No outbox table. A mutation that commits and then fails to emit is lost |
| Workflow definitions | `workflow` | 14 | exists |
| Workflow steps (definition) | `workflow_step` | 117 | exists |
| **Workflow runs** | â | â | **absent.** There is no `workflow_run`. Definitions exist; executions are not recorded |
| **Idempotency keys** | â | â | **absent** |
| **Leases / locks** | â | â | **absent** |
| **Dead-letter queue** | â | â | **absent** |
| **Retry / backoff state** | â | â | **absent** |
| Action executor registry | `org_action_executor` | **55** | **exists and is better than the audit assumed** |
| Decision trail | `decision_log` 986 / `decision_record` 3 / `agent_actions` 1,991 / `os_audit_log` 2,925 / `agent_action_log` 28 / `security_audit_log` 1,664 | ~7,600 | **exists but fragmented across six tables with no unified trace** |

**The single most important structural finding: `workflow` and `workflow_step` describe workflows, but nothing records that one ever *ran*.** No run id, no step status, no attempt count, no correlation id, no compensation record. Every requirement in Phase 1 â exactly-once, retry, compensation, replay, dead-letter â has no table to hang from. This is the correct first build and it is genuinely missing.

**The executor registry is further along than the package thinks.** 55 registered action classes, including real side-effecting ones: `outreach_send`, `invite`, `refund_within_window`, `collections_chase`, `incident_fix`, `code_selfheal`, `expense_log`, `pdpl_action`, `money_verify`, `supplier_verify`, `event_dispatch`. The audit's "only a limited set of action classes are wired to real executors" understates it. The gap is not registration â it is that there is no durable run to attach an execution to, no idempotency key to make a retry safe, and no dead-letter path when one fails.

---

## 4. Authority and governance

`org_authority` holds 33 (department, action_class) pairs across 15 departments and was re-tiered on 29 July: 24 of 33 action classes are `autonomous`, money movement / destruction / credentials / legal / third-party bans stay gated.

**Gap found during this audit:** the company-operations corpus defines **10 hard gates**, and only **2** of them (`ad_spend`, `money_move`) have any row in `org_authority`. The other eight â `authentication_identity`, `autonomy_framework`, `destructive_data`, `legal_commitment`, `production_deploy`, `public_claim_publish`, `secrets_security`, `supplier_enforcement` â have **no authority row at all**. `fn_ops_authority_check` (added today) fails closed to `gated` when no row exists, and 9/9 adversarial tests confirm that. But any other code path reading `org_authority` directly finds nothing and must invent its own default. This is reported, not fixed: filling those rows is itself an authority change and therefore hard-gated.

There is no Observe Mode / Control Mode concept anywhere in the database or the frontend. `os_api` exposes mutating actions (`review_decide`, `refund_resolve`, `fraud_resolve`, `blog_publish`, `prompt_approve`) with no mode gate and no MFA step. Implementing Observe/Control is new work, not a refactor.

---

## 5. Edge functions

191 functions. Repository and production agree exactly â verified today by downloading all 191 and diffing (clean tree). The `supabase functions download` sweep plus `scripts/archive/sync_migrations_from_prod.js` now make drift detectable in one command, which it was not before.

`os_api` exposes 35 actions; the frontend calls 26. `nav` and `search` â the two the Command Palette requirement needs â are built and unused.

**Naming collision to be aware of:** `kb_import` (a one-off `kb_chunks` loader) and `kb_corpus_import` (today's corpus writer) are different functions with similar names. The first was accidentally overwritten during this session and restored from git within minutes; it has no cron job and no code references.

---

## 6. Knowledge corpora â now present

Two corpora were imported earlier today and are directly relevant to Phases 2â5:

**Supplier categories** (`kb_stage`, 115,148 rows): 108,818 knowledge records, 16,588 qualification questions (14,051 with usable field keys, including all 7,079 mandatory), 12,929 decision rules, 4,696 validations, 3,324 scenario tests. Plus `kb_operational_route` (86 routes, all MAPPED), 426 routeâsubcategory mappings and 4,212 bilingual aliases.

Deterministic runtime already built and tested: `fn_kb_route_decide` (258/258 supplied English route tests, 86/86 Arabic, zero misroutes), `fn_kb_next_question` (next question EN+AR, completeness, `dispatch_eligible`), `fn_kb_retrieve`.

**This makes Phase 2 substantially cheaper than the roadmap assumes.** "Replace `profile_ai` legacy categories with the 86-route taxonomy" and "connect corpus aliases/questions/rules to inquiry routing and qualification" are largely *wiring* now, not building â the deterministic engine exists, is tested, and is not yet called by any production function.

**Company operations** (`ops_kb_stage`, 3,959 records): 24 departments, 96 roles, 236 SOPs, 240 decision rules, 240 exception playbooks, 216 KPIs, 18 cross-department workflows, 132 handoffs, 268 live-data bindings (262 resolved), 282 scenarios, 10 hard gates. Everything `enabled=false`; nothing approved.

Neither corpus is on the REST API. Both are service-role only through `SECURITY DEFINER` functions.

---

## 7. Quote comparison â the P0 item

`quote_compare` is called exactly once from the frontend and depends on a single large-model response for the top-three ranking. The corpus now supplies what a deterministic replacement needs: per-category mandatory questions with `on_missing` behaviour, 4,696 validation rules, and pricing/cost-driver records for every route.

The rebuild is: normalise line items â apply category compliance gates from `kb_stage.validation_rules` â compute evaluated cost â rank â **then** ask a model to explain the ranking in English and Arabic. A model-free fallback report is a hard acceptance gate and is achievable, because every input to the ranking is now relational.

---

## 8. Cron

146 jobs, 141 active. All authenticate to their edge function with the single shared `inbound_secret`. That remains the highest-value security change available and was flagged in the July handover: one string compromises most of the server-to-server surface. Not addressed in this session.

---

## 9. Duplicate systems and drift

| Finding | Assessment |
|---|---|
| Six decision/audit tables | Real duplication. `decision_log` (986) vs `decision_record` (3) vs `agent_actions` (1,991) vs three audit logs. Phase 1's unified decision trace should read from these, not add a seventh |
| `workflow_step` vs `employee_workflow` | Two workflow shapes. `employee_workflow` has 157 rows and **three columns** â it records that a workflow exists, not what it does. The corpus SOPs supersede it |
| Three memory tables | `institutional_memory` (30), `org_memory` (153), `agent_memory` (194). Not duplicates â different grains â but no unified retrieval |
| `agent_actions` at 1,991 rows, 80 in `needs_review` | 9 genuinely need the founder; 71 are work with no executor. Split is now visible in `v_founder_inbox` |
| `refunds` table | **Does not exist.** Refunds are implied by `stripe_transactions` plus a `decision_record`. Payments & Revenue cannot report a refund rate, approver or reconciliation |
| `org_objectives` | 0 rows. Chief-of-Staff objective decomposition is described as implemented; the objectives table is empty |

---

## 10. Honest scoring against the package's estimates

| Surface | Package estimate | This audit | Why |
|---|---|---|---|
| Ten-OS architecture | 85% backend | **agreed** | Primitives are all present and populated |
| Executive Command Center | 65% backend, UI unverifiable | backend agreed; **UI now verified: one 2,210-line component** | See the frontend audit |
| Customer marketplace | 75% backend | **agreed**, and Phase 2 is cheaper than estimated | The deterministic engine now exists and is tested |
| Supplier marketplace | 70% backend | **agreed** | Product intelligence genuinely absent |
| Unattended operations | 35â45% | **35% â the low end** | Executor registry is stronger than assumed (55 classes), but with no `workflow_run`, no idempotency key, no lease and no dead-letter, nothing can be retried safely. That caps real autonomy regardless of executor count |

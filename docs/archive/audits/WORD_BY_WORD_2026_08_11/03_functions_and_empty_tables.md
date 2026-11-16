> **Archived 16 Nov 2026** (simplification wave B, it_engineer): it describes the word-by-word audit of 11 Aug 2026, of the organisation before the 7-8 Sep 2026 deletions. 14 of the 32 routines it names are gone from production (SELECT pg_proc, 16 Nov 2026). History, not the build today.

# TASK 3 — FUNCTIONS WITH EMPTY TABLES

The mandate reads *"any functions with empty tables"*. That has **two** readings and the brief only
carried one. Both are answered here.

- **Reading A — functions with no table reference at all.** The brief's reading. 89 ours + 145
  extension-owned.
- **Reading B — functions whose backing tables are empty.** The literal reading, and the one that
  matches what the founder has been seeing on screen: **96 of 418 tables hold zero rows**, and the
  routines over them run, return `[]`, and report healthy.

---

# READING A — functions with no table reference

Reproduced exactly against production:

| | count |
|---|---|
| extension-owned (pgvector etc.) with no table | **145** |
| **ours**, with no table reference | **89** |
| ours, touching at least one table | **609** |
| total non-extension routines | **698** |

The 145 are excluded by the test the brief specified and it is the correct test:

```sql
exists (select 1 from pg_depend d join pg_extension e on e.oid=d.refobjid
         where d.objid=p.oid and d.deptype='e')   -- true = extension-owned
```

They are `l2_distance`, `cosine_distance`, `array_to_vector`, `vector_dims` and the rest of pgvector.
**Dropping them breaks the embedding search that all 120,530 `kb_chunks` are retrieved through.**
Excluded, with the reason, exactly as instructed.

## The 89 classified

Every one was checked against five kinds of caller, not one: other routine bodies, live triggers,
event triggers, view definitions, cron commands, and the repo.

| class | count | verdict |
|---|---|---|
| **A. trigger function bound to a live trigger** | **30** | correct — not dead |
| **B. pure helper with at least one database caller** | **40** | correct — not dead |
| **C. no database caller, but named by the repo** | **15** | correct — called over PostgREST/RPC |
| **D. no caller found anywhere** | **4 → 1** | see below |

### Class A — 30 trigger functions, all bound

`fn_governance_stamp`, `fn_ap_pay_block_held`, `fn_emit_customer_registered`,
`fn_emit_regulation_changed`, `fn_emit_rfq_classified`, `fn_emit_supplier_approved`,
`fn_gl_journal_immutable`, `fn_idea_rescore`, `fn_leads_licence_gate_rerun`,
`fn_normalize_founder_alert_level`, `fn_refunds_settled_at`, `qd_norm_customer_ver`,
`qd_norm_supplier_ver`, `trg_company_faq_sync`, `trg_holdout_expectations_immutable`,
`trg_holdout_record_immutable`, `trg_inquiry_gate_state_sync`, `trg_leads_lifecycle_stage`,
`trg_learn_customer_preference`, `trg_mask_quote_contact`, `trg_mep_pattern_norm`,
`trg_p2c1_append_only` (**bound to 6 tables**), `trg_pricing_facts`, `trg_quote_expiry`,
`trg_refunds_touch`, `trg_reg_gov_fn`, `trg_rfq_complete`, `trg_scenario_expected_needs_ledger`,
`trg_scope_marker_norm`, `trg_supplier_capability`.

A trigger function reaches its table through `NEW`/`OLD`, so it *cannot* name one in its body. **The
rule as written flags correct code.** This is the single largest reason the "89" number overstates
the problem: a third of it is triggers behaving normally.

### Class B — 40 helpers with callers

Led by `fn_norm_text` (7 callers), `fn_term_matches` (7), `fn_quote_spec_group` (6),
`fn_add_working_days` (4), `fn_report_skeleton` (3), `fn_scope_inverse` (3), `fn_term_position` (3),
`fn_ws_ea` (3), `mask_contacts` (3), then 31 more at 1–2 callers. Pure functions with callers are
exactly what a no-table routine *should* look like.

### Class C — 15 with no database caller, named by the repo

| function | called from |
|---|---|
| `kb_begin_run`, `kb_finish_run`, `kb_get_hashes`, `kb_dump_migrations`, `ops_begin_run`, `ops_finish_run`, `ops_get_files`, `ops_rollback_run`, `rollback_ingestion_run` | `supabase/functions/kb_corpus_import/index.ts` |
| `auth_uid_by_email` | `supabase/functions/login_otp/index.ts` |
| `fn_cron_liveness` | `supabase/functions/resilience_ping/index.ts` |
| `fn_enable_dropbox_sync` | `supabase/functions/dropbox_oauth/index.ts` |
| `fn_quote_score_json` | `supabase/functions/quote_compare/deterministic.ts` |
| `fn_agent_context_capped` | `scripts/staging/os_blueprint/the_ten_oses.mjs` |
| `fn_os_selftest` | 3 scripts |

### Class D — the four that looked dead, and the three that are not

This is where the brief's warning — *"named nowhere in the repository is evidence, not proof"* —
earned its place. Three of the four are load-bearing:

| function | why it looked dead | what it actually is |
|---|---|---|
| `fn_enforce_rls_on_new_tables` | no caller, no repo mention | **a live EVENT TRIGGER** — `trg_enforce_rls_new_tables`. Dropping it silently stops RLS being applied to every table created from then on. This is the most dangerous drop candidate in the set and it looks like the deadest. |
| `fn_company_brief` | no caller, no repo mention, not granted to `anon` or `authenticated` | **called by cron job `company_selfknowledge_refresh`** |
| `fn_jsonb_text_array` | no caller, no repo mention | **used in the view `inquiries_supplier_safe`** |
| `fn_simulate_growth` | no caller, no repo mention | **genuinely dead** — see below |

### The genuinely dead one: `fn_simulate_growth`

Checked against all six caller kinds and found in none:

```
database callers   0        live triggers   0
event triggers     0        views           0
cron commands      0        repo (src/scripts/supabase/.github)  0
```

It is `SECURITY INVOKER` and **executable by `anon` and `authenticated`**, so it is also a small
unused public surface. It is superseded in practice by `fn_simulate` and `fn_what_if`, both of which
are live and called.

**Verdict on Task 3, Reading A: of 698 routines, exactly one is dead.** The bar as the founder stated
it — "not a single function with no tables" — cannot be met and should not be: 145 belong to
pgvector, 30 are triggers that structurally cannot name a table, and 55 more are correct helpers or
RPCs. The number to act on is **1**.

For contrast, `scripts/checks/no_orphan_routines.mjs` baselines **58** as a ratchet. That check uses
a looser definition (not named by the repo) and would flag `fn_enforce_rls_on_new_tables`,
`fn_company_brief` and `fn_jsonb_text_array` among others. **The ratchet is useful as a ratchet and
must not be read as a list of things to delete.**

---

# READING B — functions over empty tables

**96 of 418 tables in `public` hold zero rows.** This is the reading that explains what the founder
actually sees: screens that load, return nothing, and report healthy.

The empty 96, grouped by what they mean:

**The entire demand side of the marketplace (the root cause of most of it)**
`customers`, `customer_organization`, `customer_organization_member`, `customer_preference`,
`customer_score`, `customer_calls`, `customer_layout`, `customer_phone_otps`, `inquiries`,
`inquiry_answer`, `inquiry_answer_conflict`, `inquiry_answer_conflict_value`,
`inquiry_answer_corroboration`, `inquiry_answer_document`, `inquiry_answer_scope`,
`inquiry_cancellations`, `inquiry_gate`, `inquiry_matches`, `inquiry_requirement`,
`inquiry_scope_disposition`, `inquiry_state_audit`, `inquiry_supplier_brief`,
`inquiry_trade_candidate`, `inquiry_trade_candidate_evidence`, `inquiry_trade_clarification`,
`inquiry_workstream`, `inquiry_workstream_group`, `inquiry_workstream_requirement`, `quotes`,
`quote_items`, `quote_committed_items`, `quote_comparisons`, `quote_requirements`, `quote_reviews`,
`quote_review_messages`, `quote_pdf_cache`, `qd_compare_cache`, `comparison_run_v2`,
`comparison_candidate_v2`, `transactions`, `reveal_invoices`, `refunds`, `refund_event_quarantine`,
`payment_dispute`, `stripe_events`, `rfq_archives`, `reviews`, `review_queue`, `feedback`,
`messages`, `contact_messages`, `chat_threads`, `chat_violations`, `questions`

**Finance and procurement modules that have never been used**
`ap_bills`, `budgets`, `budget_lines`, `po_orders`, `po_lines`, `po_vendors`, `fa_assets`,
`fa_depreciation`, `inv_items`, `inv_stock_moves`, `procurement_approval_policy`,
`procurement_approval_request`, `supplier_dues`, `shipment_leg`

**Features built and never exercised**
`ea_events`, `ea_meetings`, `ea_reminders`, `doc_reviews`, `drawing_redaction_runs`,
`experiment_events`, `model_outcome`, `promotion_record`, `idea`, `market_intel`, `brand_signal`,
`content_drafts`, `crm_notes`, `projects`, `project_component`, `hlm_state`, `hlm_digest_log`,
`hlm_watchlist`, `agent_pending_actions`, `supplier_capabilities`,
`supplier_capability_confirmation`, `supplier_opportunity_score`, `org_objectives`,
`field_definition_trade`, `email_verifications`, `pdpl_requests`, `pdpl_erase_files`,
`phase1_rollback_log`

## What this means, stated precisely

**A routine over an empty table is not broken and must not be "fixed".** `fn_customer_stats` returns
zero rows because there are zero customers; that is correct behaviour. The defect is never the
routine — it is that **nothing distinguishes "measured zero" from "never measured"**, and every
dashboard, KPI and gate downstream reports the second as the first.

Three concrete instances found while measuring:

1. **`fn_scenario_run`** writes `last_run` on all 19 scenarios and its verdict text reads
   `ORG READINESS READY`. It checks that the named departments exist and are staffed. It never
   injects the failure. A reader sees 19/19.
2. **The observability trace in spec #7 L1467–L1498** has a routine for all eight steps and
   `workflow_run` for `rfq_handling` = **0**. The health screens report observability healthy.
3. **`least(100.0, NULL)` returns 100.0** — already recorded in memory, and the same class: an
   unmeasured goal scoring as a perfect one.

**The single highest-value change this audit can recommend is not deleting a function.** It is that
any surface reporting a number derived from an empty table must say *"no data yet"* rather than
`0`, `100%` or `READY`. That distinction is what would have caught all three of the above, and it is
what turned a 126/152 into something the founder could not trust.

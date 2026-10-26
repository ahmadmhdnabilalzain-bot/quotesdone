-- DEPARTMENT AUTONOMOUS CAPABILITY — register missing executors, lift over-gating, and stop
-- wrong founder-escalations, per department. Founder confirmed 2 Sep 2026 ("turn it on now"; all
-- limits/frozen gates lifted except OpenRouter). Executors wrap REAL existing deterministic functions;
-- rpc targets are allow-listed; authority raises carry app.change_reason. Applied to production via
-- the management API and captured here for reproducibility (these are config rows, not routines).
--
--   node scripts/apply_sql.mjs scripts/sql/department_autonomous_capability.sql --apply --ddl

-- rpc targets allow-listed (only those that are real functions).
insert into public.org_action_executor_rpc_allowed(target, note)
select v.t, 'allow-listed 2 Sep 2026 for department autonomous action'
from (values
  ('action_class_gate'),
  ('action_class'),
  ('fn_cron_liveness'),
  ('fn_os_incident_open'),
  ('action_executor'),
  ('fn_llm_drift_watch'),
  ('fn_org_action_executor_guard'),
  ('cos_execute'),
  ('action_executor_rpc_allowed'),
  ('fn_eval_run'),
  ('fn_model_benchmark'),
  ('fn_model_catalog_drift'),
  ('fn_security_scan'),
  ('fn_resilience_watch'),
  ('fn_edge_health_scan'),
  ('fn_action_invoke_rpc'),
  ('fn_ops_authority_check'),
  ('fn_org_authority_guard'),
  ('fn_supplier_capability_derive'),
  ('fn_match_capability'),
  ('fn_finance_forecast'),
  ('fn_revenue_trajectory'),
  ('fn_cost_per_os'),
  ('fn_ws_finance'),
  ('fn_customers_board'),
  ('funnel_metrics'),
  ('fn_marketplace_analytics'),
  ('fn_kpi_scoreboard'),
  ('fn_knowledge_freshness_sweep'),
  ('fn_kb_corpus_integrity'),
  ('fn_kb_reconcile'),
  ('fn_category_readiness_recompute'),
  ('fn_legal_ai'),
  ('action_executor_guard'),
  ('action_executor_money_legal_second'),
  ('fn_workflow_step_sweep'),
  ('fn_brand_scan'),
  ('fn_kpi_review'),
  ('fn_employee_kpi_assign'),
  ('fn_knowledge_exam_summary'),
  ('fn_improvement_plan_refresh'),
  ('fn_onboarding_ingest_runs'),
  ('action_class_gate_known_gate'),
  ('fn_objective_review'),
  ('fn_strategy_scan'),
  ('fn_strategy_risk'),
  ('fn_org_scorecard')
) v(t)
where exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname = v.t)
on conflict (target) do nothing;

-- ====== product_eng ======
begin;
set local app.change_reason = 'Founder 2 Sep 2026: departments act autonomously — lift over-gating and register real deterministic executors so each department resolves its own domain issues without the founder.';
-- S1a. Un-gate code_selfheal: verified target resilience_ping is a read-only cron-liveness probe, not a deploy.
update public.action_class_gate
   set gate_action_class = null,
       rationale = 'Re-reviewed 2 Sep 2026 against the actual target code. code_selfheal invokes edge fn resilience_ping, a READ-ONLY cron-liveness probe: it reads fn_cron_liveness and, only when pg_cron is dead, pages the founder and force-flushes the outbox. It deploys no code and changes no production config; the prior ''promotes code to production'' rationale did not match the function. Ungated as routine reversible resilience work. The production_deploy hard gate (ops_kb_stage.hard_gates) still exists and still governs any real code_deploy executor.',
       reviewed_on = current_date,
       reviewed_by = 'founder'
 where action_class = 'code_selfheal';
-- S1b. Un-gate incident_fix: verified target os_incidents is incident CRUD (open/list/resolve), not a deploy.
update public.action_class_gate
   set gate_action_class = null,
       rationale = 'Re-reviewed 2 Sep 2026 against the actual target code. incident_fix invokes edge fn os_incidents, whose only actions are runbooks/list (read) and open/resolve of an incident tracking row (open emits an FYI founder notice via fn_os_incident_open). It changes no production configuration; the prior ''can change production configuration'' rationale did not match the function. Ungated as routine reversible engineering ops. The production_deploy hard gate remains for real deploys.',
       reviewed_on = current_date,
       reviewed_by = 'founder'
 where action_class = 'incident_fix';
-- S2. Raise product_eng authority for the two owned classes to autonomous (the autonomous grant already sat on assurance/it; the 14 Aug org move carried the executor here but left the grant at supervised).
update public.org_authority
   set max_tier = 'autonomous',
       note = 'Raised to autonomous 2 Sep 2026 (founder bar: product_eng solves in-domain issues as expert staff). Routine, reversible, non-money. Sibling grant already autonomous on assurance/it which own no executor for these classes.'
 where dept_key = 'product_eng'
   and action_class in ('code_selfheal','incident_fix')
   and max_tier <> 'autonomous';
-- S3. Retool the two owned executors so the dispatcher auto-runs them (needs low+advisory_safe+reversible, notifies_human=false, no second_authority). Idempotent note: strips any prior 2 Sep suffix before re-adding.
update public.org_action_executor
   set risk_tier = 'low',
       advisory_safe = true,
       reversible = true,
       unattended_ok = true,
       notifies_human = false,
       second_authority = null,
       idempotency_strategy = coalesce(idempotency_strategy, 'none_read_only'),
       note = regexp_replace(coalesce(note,''), '\s*\|\s*2 Sep 2026:.*$', '') || ' | 2 Sep 2026: set low/advisory_safe/reversible/unattended so product_eng runs incident triage and the resilience self-heal probe autonomously (target verified read-only/CRUD, not a production deploy); mirrors the assurance monitoring executors.'
 where action_class in ('code_selfheal','incident_fix')
   and department = 'product_eng';
-- S4. Reviewed, ungated gate row for the new AI drift-watch class (required: DECLARED-GATES-WIN forces gated for any class with no action_class_gate row).
insert into public.action_class_gate (action_class, gate_action_class, rationale, reviewed_on, reviewed_by)
values ('llm_drift_watch', null,
        'Read-only model-policy and model-cost watch (rpc fn_llm_drift_watch): reads llm_calls / v_llm_offpolicy, computes fallback and failure rates, and raises a deduped FYI alert only. No model call, no paid inference, no business write beyond an alert row. Reviewed ungated 2 Sep 2026.',
        current_date, 'founder')
on conflict (action_class) do update
   set gate_action_class = excluded.gate_action_class,
       rationale = excluded.rationale,
       reviewed_on = excluded.reviewed_on,
       reviewed_by = excluded.reviewed_by;
-- S5. Autonomous authority for product_eng on the new AI-monitoring class (AI Director + Optimisation Engineer own model cost, tier routing and drift).
insert into public.org_authority (dept_key, action_class, max_tier, threshold_aed, note)
values ('product_eng', 'llm_drift_watch', 'autonomous', null,
        'AI monitoring is product_eng''s charter (AI Director + Optimisation Engineer own model cost, tier routing and drift). Deterministic read+alert; autonomous 2 Sep 2026.')
on conflict (dept_key, action_class) do update
   set max_tier = 'autonomous', note = excluded.note;
-- S6. Register the missing executor wrapping the REAL, verified, deterministic function public.fn_llm_drift_watch() (no args, no LLM call). advisory_safe=true is load-bearing: the rpc dispatcher runs only low/advisory_safe/reversible executors.
insert into public.org_action_executor
 (action_class, kind, target, params, active, note, department, owner_os, risk_tier, reversible,
  advisory_safe, idempotency_strategy, timeout_seconds, max_attempts, backoff, required_authority,
  compensation_action_class, notifies_human, unattended_ok, second_authority)
values
 ('llm_drift_watch', 'rpc', 'fn_llm_drift_watch', '{}'::jsonb, true,
  'Autonomous AI model-policy & cost drift watch. Wraps public.fn_llm_drift_watch() (deterministic: reads llm_calls, flags off-policy models, >20% fallback, >5 failures; deduped FYI alert only). No paid inference.',
  'product_eng', 'technology', 'low', true,
  true, 'none_read_only', 60, 1, null, null,
  null, false, true, null)
on conflict (action_class) do update set
  kind = excluded.kind, target = excluded.target, params = excluded.params, active = true,
  note = excluded.note, department = excluded.department, owner_os = excluded.owner_os,
  risk_tier = 'low', reversible = true, advisory_safe = true, idempotency_strategy = 'none_read_only',
  timeout_seconds = 60, max_attempts = 1, required_authority = null, compensation_action_class = null,
  notifies_human = false, unattended_ok = true, second_authority = null;
commit;

-- ====== assurance ======
begin;
set local app.change_reason = 'Founder 2 Sep 2026: departments act autonomously — lift over-gating and register real deterministic executors so each department resolves its own domain issues without the founder.';
-- 1) Deliberately allow-list the seven assurance rpc targets. fn_org_action_executor_guard refuses any rpc
-- executor whose target is not here (cos_execute runs rpc executors as service-role), so this must land first.
insert into public.org_action_executor_rpc_allowed (target, note) values
 ('fn_eval_run','assurance model-eval executor; autonomous expert staff (founder bar 2 Sep 2026)'),
 ('fn_model_benchmark','assurance model-eval executor; autonomous expert staff (founder bar 2 Sep 2026)'),
 ('fn_llm_drift_watch','assurance model-eval executor; autonomous expert staff (founder bar 2 Sep 2026)'),
 ('fn_model_catalog_drift','assurance model-eval executor; autonomous expert staff (founder bar 2 Sep 2026)'),
 ('fn_security_scan','assurance security executor; autonomous expert staff (founder bar 2 Sep 2026)'),
 ('fn_resilience_watch','assurance SRE executor; autonomous expert staff (founder bar 2 Sep 2026)'),
 ('fn_edge_health_scan','assurance SRE executor; autonomous expert staff (founder bar 2 Sep 2026)')
on conflict (target) do nothing;
-- 2) Register the seven missing executors, each wrapping a REAL zero-arg SECURITY DEFINER function that already
-- exists (verified in pg_proc). rpc + low + advisory_safe + reversible so fn_action_invoke_rpc auto-runs them;
-- notifies_human=false, unattended_ok=true, no required/second authority. Deterministic: no OpenRouter/LLM call.
insert into public.org_action_executor
 (action_class, kind, target, department, owner_os, risk_tier, reversible, advisory_safe, unattended_ok, notifies_human, idempotency_strategy, active, note)
values
 ('eval_run','rpc','fn_eval_run','assurance','intelligence','low',true,true,true,false,'none_read_only',true,'Model Evaluation Specialist runs the eval harness (fn_eval_run) on demand. Reads run/usage history, writes eval results only. No money, no external send, no LLM call.'),
 ('model_benchmark','rpc','fn_model_benchmark','assurance','intelligence','low',true,true,true,false,'none_read_only',true,'Benchmarks task classes on success rate and cost (fn_model_benchmark). Read+aggregate over usage; advisory monitoring output.'),
 ('llm_drift_watch','rpc','fn_llm_drift_watch','assurance','intelligence','low',true,true,true,false,'none_read_only',true,'Watches output/quality drift (fn_llm_drift_watch). Deterministic monitoring; raises internal alerts only.'),
 ('model_catalog_drift','rpc','fn_model_catalog_drift','assurance','intelligence','low',true,true,true,false,'none_read_only',true,'Detects model catalog/version/price drift (fn_model_catalog_drift). Deterministic; internal telemetry only.'),
 ('security_scan','rpc','fn_security_scan','assurance','technology','low',true,true,true,false,'none_read_only',true,'Security engineer runs the internal security scan (fn_security_scan). Reads estate, writes findings only. Remediation stays a separate gated class.'),
 ('resilience_watch','rpc','fn_resilience_watch','assurance','technology','low',true,true,true,false,'none_read_only',true,'IT/SRE resilience sweep (fn_resilience_watch): probes own surfaces, records verdicts, opens/updates incidents. Reversible monitoring (own-surface HTTP, like uptime_verify).'),
 ('edge_health_scan','rpc','fn_edge_health_scan','assurance','technology','low',true,true,true,false,'none_read_only',true,'IT/SRE per-function silence detection (fn_edge_health_scan): flags silently-dead edge functions and opens an incident. Reversible monitoring.')
on conflict (action_class) do update set
 kind=excluded.kind, target=excluded.target, department=excluded.department, owner_os=excluded.owner_os,
 risk_tier=excluded.risk_tier, reversible=excluded.reversible, advisory_safe=excluded.advisory_safe,
 unattended_ok=excluded.unattended_ok, notifies_human=excluded.notifies_human,
 idempotency_strategy=excluded.idempotency_strategy, active=excluded.active, note=excluded.note;
-- 3) Register each new executor action_class in action_class_gate (reviewed, gate_action_class=null = no hard gate),
-- matching how the five existing assurance executor classes are registered. Keeps the governance registry complete
-- and stops fn_ops_authority_check treating them as unreviewed.
insert into public.action_class_gate (action_class, gate_action_class, rationale, reviewed_by) values
 ('eval_run', null, 'Runs the model eval harness and writes eval results. Read + internal telemetry; no external effect. Reviewed as autonomous expert-staff capability (founder bar 2 Sep 2026).','founder'),
 ('model_benchmark', null, 'Benchmarks task classes from usage history. Read-only aggregate + advisory output.','founder'),
 ('llm_drift_watch', null, 'Deterministic output/quality drift monitoring; raises internal alerts only.','founder'),
 ('model_catalog_drift', null, 'Deterministic model-catalog drift monitoring; internal telemetry only.','founder'),
 ('security_scan', null, 'Internal security scan; reads estate and records findings. Remediation is a separate gated class.','founder'),
 ('resilience_watch', null, 'SRE resilience monitoring; probes own surfaces and records verdicts/incidents. Reversible.','founder'),
 ('edge_health_scan', null, 'SRE per-function silence detection; opens an incident when a function goes silent. Reversible.','founder')
on conflict (action_class) do update set gate_action_class=excluded.gate_action_class, rationale=excluded.rationale, reviewed_by=excluded.reviewed_by;
-- 4) Fix over-gating: coordinate/exec_review/recommend are routine, reversible, non-money, no external effect and
-- carry no hard gate, so an expert should just act. Raise assurance's authority tier advisory -> autonomous.
-- The org_authority widen-guard requires a stated reason in the same transaction; a DO block supplies it.
-- Idempotent: the WHERE excludes rows already autonomous, so a re-run performs no widen.
do $$
begin
  perform set_config('app.change_reason',
    'Assurance autonomous expert staff (founder bar 2 Sep 2026): coordinate/exec_review/recommend are routine, reversible, non-money, no external effect - the expert acts, it does not seek approval.', true);
  update public.org_authority set max_tier='autonomous'
   where dept_key='assurance' and action_class in ('coordinate','exec_review','recommend') and max_tier <> 'autonomous';
end $$;
-- 5) Stop routine founder/human escalation: health_report ('summarises health signals already computed') and
-- security_review ('reads scan output and reports') are read-only reporting. An expert files them without pinging a
-- human on every run. Flip notifies_human off; they still auto-dispatch (unattended_ok already true). Idempotent.
update public.org_action_executor set notifies_human=false
 where action_class in ('health_report','security_review') and department='assurance' and notifies_human;
commit;

-- ====== marketplace ======
begin;
set local app.change_reason = 'Founder 2 Sep 2026: departments act autonomously — lift over-gating and register real deterministic executors so each department resolves its own domain issues without the founder.';
-- 1) OVER-GATING FIX: three built, reversible, non-money, non-hard-gated marketplace executors
--    become autonomous. Wrapped in a DO block because org_authority has a governance guard
--    (fn_org_authority_guard) that refuses a tier RAISE without app.change_reason set in the same tx.
--    Idempotent: 'is distinct from autonomous' makes a re-run a no-op (and the guard only fires on a raise).
do $$
begin
  perform set_config('app.change_reason',
    'Founder bar 2 Sep 2026: marketplace acts as autonomous expert staff on its built, reversible, non-money, non-hard-gated capabilities (capability enrichment, category routing, OCR-clean supplier auto-approval). These were gated only by a 14-Aug-2026 most-restrictive inheritance, not by a money/identity/irreversible reason.', true);
  update public.org_authority
     set max_tier = 'autonomous'
   where dept_key = 'marketplace'
     and action_class in ('capability_enrich','route_category','supplier_approve_clean')
     and max_tier is distinct from 'autonomous';
end $$;
-- 2) NEW EXECUTOR (prereq): allow-list the rpc target. fn_org_action_executor_guard refuses any rpc
--    executor whose target is not in org_action_executor_rpc_allowed, because cos_execute runs rpc
--    executors as service-role. fn_supplier_capability_derive is SECURITY DEFINER, a single set-based
--    INSERT, no dynamic SQL, no money, no outbound. Safe and deliberate.
insert into public.org_action_executor_rpc_allowed(target, note)
values ('fn_supplier_capability_derive',
        'Deterministic gap-fill of supplier_capabilities from the directory. SECURITY DEFINER, single set-based INSERT, no dynamic SQL, no money, no outbound; derived rows are review_status=derived and inert until the supplier confirms scope. Allow-listed for marketplace autonomy 2026-09-02.')
on conflict (target) do nothing;
-- 3) NEW EXECUTOR (prereq): action_class_gate row. fn_ops_authority_check forces any class with NO
--    action_class_gate row to 'gated' (unreviewed is not unrestricted). gate_action_class=NULL means
--    reviewed, no hard gate; rationale is NOT NULL. Governed thereafter purely by org_authority.
insert into public.action_class_gate(action_class, gate_action_class, rationale)
values ('supplier_capability_derive', null,
        'Reviewed: no hard gate. Bulk derivation of supplier capability from the existing directory is deterministic, reversible, moves no money, sends nothing, and its output is inert until the supplier confirms scope. Governed solely by org_authority (marketplace=autonomous).')
on conflict (action_class) do nothing;
-- 4) NEW EXECUTOR: department authority = autonomous. DO block to satisfy the change_reason guard.
do $$
begin
  perform set_config('app.change_reason',
    'New marketplace capability 2026-09-02: autonomous authority for supplier_capability_derive (deterministic, reversible, non-money bulk derivation feeding fn_match_capability).', true);
  insert into public.org_authority(dept_key, action_class, max_tier, note)
  values ('marketplace','supplier_capability_derive','autonomous',
          'Deterministic bulk derivation of supplier_capabilities feeding fn_match_capability; reversible, no money, no outbound. Executor: rpc fn_supplier_capability_derive.')
  on conflict (dept_key, action_class) do update
     set max_tier = 'autonomous', note = excluded.note;
end $$;
-- 5) NEW EXECUTOR row (runs only after statements 2 and 3 exist). rpc kind; low/reversible/advisory_safe
--    so both cos_execute (authority=autonomous) and the action-queue rpc invoker will run it unattended;
--    notifies_human=false (no human sign-off), unattended_ok=true. PK is action_class alone.
insert into public.org_action_executor
  (action_class, kind, target, params, active, note, department, owner_os,
   risk_tier, reversible, advisory_safe, idempotency_strategy, timeout_seconds,
   max_attempts, notifies_human, unattended_ok, compensation_action_class)
values
  ('supplier_capability_derive','rpc','fn_supplier_capability_derive','{}'::jsonb, true,
   'Derive structured supplier_capabilities for directory leads that have none (deterministic, no model call, gap-fill only; ~51 derivable in a 200-lead sample against a 15,357-row base on 2026-09-02). Feeds fn_match_capability. Reversible: derived rows are review_status=derived and inert until the supplier confirms scope.',
   'marketplace','marketplace','low', true, true, 'natural_key', 120,
   1, false, true, 'manual_reversal')
on conflict (action_class) do update set
   kind=excluded.kind, target=excluded.target, params=excluded.params, active=true,
   department=excluded.department, owner_os=excluded.owner_os, risk_tier=excluded.risk_tier,
   reversible=excluded.reversible, advisory_safe=excluded.advisory_safe,
   idempotency_strategy=excluded.idempotency_strategy, timeout_seconds=excluded.timeout_seconds,
   notifies_human=excluded.notifies_human, unattended_ok=excluded.unattended_ok,
   compensation_action_class=excluded.compensation_action_class, note=excluded.note;
commit;

-- ====== finance ======
begin;
set local app.change_reason = 'Founder 2 Sep 2026: departments act autonomously — lift over-gating and register real deterministic executors so each department resolves its own domain issues without the founder.';
-- 1) REGISTER THE FOUR MISSING FINANCE EXECUTORS (wrapping REAL, verified, read-only functions).
-- advisory_safe=true is REQUIRED here: fn_action_invoke_rpc refuses any executor that is not
-- (low AND advisory_safe AND reversible), so without it these rows register but never dispatch.
-- Each target was verified read-only: fn_finance_forecast/fn_revenue_trajectory/fn_cost_per_os are
-- STABLE (Postgres forbids writes), fn_ws_finance is plpgsql with zero INSERT/UPDATE/DELETE.
-- All four run headless as `select jsonb_agg(to_jsonb(t)) from public.<fn>() t` (0 required args).
insert into public.org_action_executor
  (action_class, kind, target, params, active, note, advisory_safe, department, owner_os,
   risk_tier, reversible, idempotency_strategy, timeout_seconds, max_attempts, backoff,
   required_authority, compensation_action_class, notifies_human, unattended_ok, second_authority)
values
  ('cashflow_forecast','rpc','fn_finance_forecast','{}'::jsonb,true,
     '2026-09-02 autonomy: deterministic 30/60/90-day cash-flow forecast from posted GL, supplier_dues (AR) and ap_open_bills (AP). STABLE, read-only, no LLM.',
     true,'finance','finance','low',true,'none_read_only',60,1,null,null,'none_required_read_only',false,true,null),
  ('revenue_trajectory','rpc','fn_revenue_trajectory','{}'::jsonb,true,
     '2026-09-02 autonomy: deterministic revenue-vs-annual-target run-rate from company_goals.measure_sql. STABLE, read-only, no LLM.',
     true,'finance','finance','low',true,'none_read_only',60,1,null,null,'none_required_read_only',false,true,null),
  ('cost_attribution','rpc','fn_cost_per_os','{}'::jsonb,true,
     '2026-09-02 autonomy: deterministic AI cost per operating-system/department over 30 days (fn_cost_per_os default window) with coverage. STABLE, read-only, no LLM.',
     true,'finance','finance','low',true,'none_read_only',60,1,null,null,'none_required_read_only',false,true,null),
  ('finance_snapshot','rpc','fn_ws_finance','{}'::jsonb,true,
     '2026-09-02 autonomy: deterministic finance readout (cash, P&L, 30d run-rate, runway, monetization, receivables, payables+AP aging, 6-mo cashflow, budgets, KPIs, embedded forecast). Verified no INSERT/UPDATE/DELETE. No LLM.',
     true,'finance','finance','low',true,'none_read_only',90,1,null,null,'none_required_read_only',false,true,null)
on conflict (action_class) do update set
  kind=excluded.kind, target=excluded.target, params=excluded.params, active=excluded.active,
  note=excluded.note, advisory_safe=excluded.advisory_safe, department=excluded.department,
  owner_os=excluded.owner_os, risk_tier=excluded.risk_tier, reversible=excluded.reversible,
  idempotency_strategy=excluded.idempotency_strategy, timeout_seconds=excluded.timeout_seconds,
  max_attempts=excluded.max_attempts, backoff=excluded.backoff,
  required_authority=excluded.required_authority, compensation_action_class=excluded.compensation_action_class,
  notifies_human=excluded.notifies_human, unattended_ok=excluded.unattended_ok, second_authority=excluded.second_authority;
-- 2) GRANT AUTONOMOUS AUTHORITY for the four new classes so fn_ops_authority_check does not
-- fall back to its fail-closed 'gated' default for an unknown (dept, action_class). Non-money,
-- reversible, read-only -> a finance expert simply acts.
insert into public.org_authority (dept_key, action_class, max_tier, threshold_aed, note)
values
  ('finance','cashflow_forecast','autonomous',null,'2026-09-02 autonomy expansion: read-only deterministic cash forecast (fn_finance_forecast); no money moves.'),
  ('finance','revenue_trajectory','autonomous',null,'2026-09-02 autonomy expansion: read-only deterministic revenue run-rate (fn_revenue_trajectory).'),
  ('finance','cost_attribution','autonomous',null,'2026-09-02 autonomy expansion: read-only deterministic cost attribution (fn_cost_per_os).'),
  ('finance','finance_snapshot','autonomous',null,'2026-09-02 autonomy expansion: read-only deterministic finance readout (fn_ws_finance).')
on conflict (dept_key, action_class) do update set max_tier='autonomous', note=excluded.note;
-- 3) RECORD an explicit no-hard-gate action_class_gate row for each new read-only class
-- (gate_action_class = NULL), matching the pattern already used for ap_duplicate_scan / spend_check /
-- invoice_review / money_verify. This keeps triage/probe/read actions off any ship-to-prod style gate
-- while leaving the actual money path (money_move) to keep its own gate.
insert into public.action_class_gate (action_class, gate_action_class, rationale, reviewed_by)
values
  ('cashflow_forecast', null, 'Read-only cash projection over posted GL/AR/AP. Changes no balance; the actual payout (money_move) keeps its own gate.', 'autonomy_expansion_2026_09_02'),
  ('revenue_trajectory', null, 'Read-only revenue run-rate vs target. Moves no money.', 'autonomy_expansion_2026_09_02'),
  ('cost_attribution', null, 'Read-only cost attribution over ai_cost_log. Moves no money.', 'autonomy_expansion_2026_09_02'),
  ('finance_snapshot', null, 'Read-only finance readout; verified no writes. Moves no money.', 'autonomy_expansion_2026_09_02')
on conflict (action_class) do update set gate_action_class=null, rationale=excluded.rationale, reviewed_by=excluded.reviewed_by;
-- 4) HYGIENE: mark the two existing read-only finance rpc scans unattended_ok=true so they stay
-- dispatchable even if notifies_human is ever set on them later. Guarded so it only touches rows
-- that are already read-only/low/advisory_safe (no behavioural change today; notifies_human is false).
update public.org_action_executor
   set unattended_ok=true
 where action_class in ('ap_duplicate_scan','spend_check')
   and department='finance' and notifies_human=false and advisory_safe=true
   and risk_tier='low' and reversible=true and unattended_ok=false;
commit;

-- ====== customer_experience ======
begin;
set local app.change_reason = 'Founder 2 Sep 2026: departments act autonomously — lift over-gating and register real deterministic executors so each department resolves its own domain issues without the founder.';
-- 1) Register the ONE safe, real, deterministic executor: a read-only customer-experience board.
-- fn_customers_board is VERIFIED to exist (single signature, all args defaulted so callable as fn()),
-- STABLE/read-only (writes nothing), returns jsonb. As kind='rpc' the rpc invoker calls public.fn_customers_board()
-- directly, with NO edge/HTTP and NO LLM. Classified low + advisory_safe + reversible + notifies_human=false so
-- fn_action_invoke_rpc dispatches it fully autonomously (no approval tier, no founder). Idempotent.
insert into public.org_action_executor
  (action_class, kind, target, params, active, note, department, owner_os,
   risk_tier, reversible, idempotency_strategy, timeout_seconds, max_attempts, backoff,
   required_authority, compensation_action_class, notifies_human, unattended_ok,
   second_authority, advisory_safe)
values
  ('cx_customer_board','rpc','fn_customers_board','{}'::jsonb, true,
   'Read-only customer-experience situational board (KPIs, accounts, behaviour). Deterministic SQL, writes nothing, no LLM. advisory_safe+reversible+not-notifying so the rpc invoker runs it fully autonomously for the department. Wired 2 Sep 2026.',
   'customer_experience','operations',
   'low', true, 'none_read_only', 30, 1, null,
   null, 'none_required_read_only', false, true,
   null, true)
on conflict (action_class) do update set
   kind=excluded.kind, target=excluded.target, department=excluded.department, owner_os=excluded.owner_os,
   risk_tier=excluded.risk_tier, reversible=excluded.reversible, advisory_safe=excluded.advisory_safe,
   notifies_human=excluded.notifies_human, unattended_ok=excluded.unattended_ok,
   compensation_action_class=excluded.compensation_action_class, idempotency_strategy=excluded.idempotency_strategy,
   required_authority=excluded.required_authority, active=excluded.active, note=excluded.note;
-- 2) Authorise the department to run its own board autonomously (routine, reversible, read-only, non-money).
insert into public.org_authority (dept_key, action_class, max_tier, threshold_aed, note)
values ('customer_experience','cx_customer_board','autonomous', null,
        'Read-only customer board: the department owns its own situational awareness. Non-money, read-only, reversible. Added 2 Sep 2026.')
on conflict (dept_key, action_class) do update set max_tier=excluded.max_tier, note=excluded.note;
commit;

-- ====== growth ======
begin;
set local app.change_reason = 'Founder 2 Sep 2026: departments act autonomously — lift over-gating and register real deterministic executors so each department resolves its own domain issues without the founder.';
-- 1) MISSING DETERMINISTIC EXECUTOR. Wire growth's autonomous, founder-reviewed action class
--    'pipeline_review' (org_authority=autonomous, action_class_gate row present, NO executor) to the
--    REAL existing read-only function public.funnel_metrics(days integer DEFAULT 30). It is STABLE
--    SECURITY DEFINER and selects only from inquiries/quotes/transactions, so it is deterministic,
--    reversible (writes nothing) and carries no live-inference dependency. PK is action_class alone;
--    pipeline_review is currently unclaimed. advisory_safe/reversible/low/notifies_human=false/
--    unattended_ok=true are set precisely so BOTH dispatch paths run it: cos_execute (autonomous tier)
--    and fn_action_invoke_rpc (which calls the target with ZERO args and requires
--    low+advisory_safe+reversible+not-founder+not notifies_human-without-unattended). Idempotent upsert;
--    the DO UPDATE is guarded so it can never steal a row another department legitimately claims later.
INSERT INTO public.org_action_executor
  (action_class, kind, target, params, active, note, department, owner_os,
   risk_tier, reversible, idempotency_strategy, timeout_seconds, max_attempts, backoff,
   required_authority, compensation_action_class, notifies_human, unattended_ok,
   second_authority, advisory_safe)
VALUES
  ('pipeline_review','rpc','funnel_metrics','{}'::jsonb, true,
   '2 Sep 2026 (founder autonomy bar): growth''s first DETERMINISTIC executor. Deterministic sales-pipeline / funnel read via public.funnel_metrics() (inquiries -> matched -> quoted -> revealed -> reveal_fees; STABLE, SECURITY DEFINER, read-only, no model call). Lets sales_director / crm_pipeline_mgr / marketing_analyst review the pipeline autonomously with inference OFF instead of escalating a routine read. Publishes/moves nothing.',
   'growth','commercial',
   'low', true, 'none_read_only', 30, 1, NULL,
   NULL, 'none_required_read_only', false, true,
   NULL, true)
ON CONFLICT (action_class) DO UPDATE SET
   kind=excluded.kind, target=excluded.target, params=excluded.params, active=excluded.active,
   note=excluded.note, department=excluded.department, owner_os=excluded.owner_os,
   risk_tier=excluded.risk_tier, reversible=excluded.reversible,
   idempotency_strategy=excluded.idempotency_strategy, timeout_seconds=excluded.timeout_seconds,
   max_attempts=excluded.max_attempts, backoff=excluded.backoff,
   required_authority=excluded.required_authority,
   compensation_action_class=excluded.compensation_action_class,
   notifies_human=excluded.notifies_human, unattended_ok=excluded.unattended_ok,
   second_authority=excluded.second_authority, advisory_safe=excluded.advisory_safe
 WHERE public.org_action_executor.department IS NULL
    OR public.org_action_executor.department = 'growth';
-- 2) OVER-GATING FIX. coordinate resolves to 'supervised' for growth (org_authority.max_tier, no hard
--    gate). The founder's own action_class_gate rationale for coordinate is 'Routes existing work between
--    departments; creates no external effect.' Routine, reversible, non-money, no external side effect ->
--    a growth manager should just do it. Raise to 'autonomous'. Guarded so a re-run is a no-op, and fully
--    reversible by setting max_tier back to 'supervised'.
UPDATE public.org_authority
   SET max_tier = 'autonomous',
       note = coalesce(note,'') || ' | 2 Sep 2026 founder autonomy bar: raised supervised->autonomous - internal work-routing creates no external effect, is reversible and non-money.'
 WHERE dept_key = 'growth'
   AND action_class = 'coordinate'
   AND max_tier <> 'autonomous';
commit;

-- ====== data_intel ======
begin;
set local app.change_reason = 'Founder 2 Sep 2026: departments act autonomously — lift over-gating and register real deterministic executors so each department resolves its own domain issues without the founder.';
-- 1) FIX OVER-GATING (authority tier): grant data_intel autonomous authority for its six domain classes.
--    fn_ops_authority_check defaults any (dept,class) with no org_authority row to 'gated', so the row IS the fix.
insert into public.org_authority (dept_key, action_class, max_tier, threshold_aed, note) values
 ('data_intel','marketplace_analytics','autonomous',null,'Read-only marketplace analytics rollup (fn_marketplace_analytics); deterministic, no model call. Founder 2 Sep 2026: expert acts autonomously.'),
 ('data_intel','kpi_scoreboard','autonomous',null,'Read-only KPI scoreboard (fn_kpi_scoreboard); deterministic. Founder 2 Sep 2026.'),
 ('data_intel','knowledge_freshness','autonomous',null,'Idempotent knowledge freshness sweep (fn_knowledge_freshness_sweep). Founder 2 Sep 2026.'),
 ('data_intel','kb_integrity','autonomous',null,'KB corpus integrity report (fn_kb_corpus_integrity); read plus append report. Founder 2 Sep 2026.'),
 ('data_intel','kb_reconcile','autonomous',null,'Idempotent KB reconcile (fn_kb_reconcile). Founder 2 Sep 2026.'),
 ('data_intel','category_readiness','autonomous',null,'Idempotent category readiness recompute (fn_category_readiness_recompute). Founder 2 Sep 2026.')
on conflict (dept_key, action_class) do update set max_tier=excluded.max_tier, note=excluded.note;
-- 2) FIX OVER-GATING (review registry): register the six classes as REVIEWED and ungated (gate_action_class = NULL).
--    Without a row here fn_ops_authority_check forces 'gated' regardless of org_authority. NULL gate = no hard gate tightens it.
insert into public.action_class_gate (action_class, gate_action_class, rationale, reviewed_on, reviewed_by) values
 ('marketplace_analytics',null,'Read-only analytics rollup over marketplace state; commits no external effect. Registered ungated so the authority check does not default it to gated.','2026-09-02','data_intel_autonomy'),
 ('kpi_scoreboard',null,'Read-only KPI computation; writes no live state.','2026-09-02','data_intel_autonomy'),
 ('knowledge_freshness',null,'Recomputes knowledge freshness stamps in place; idempotent, reversible by the next sweep.','2026-09-02','data_intel_autonomy'),
 ('kb_integrity',null,'Reads the corpus and appends an integrity report; changes no published knowledge.','2026-09-02','data_intel_autonomy'),
 ('kb_reconcile',null,'Reconciles derived knowledge-base bookkeeping in place; idempotent.','2026-09-02','data_intel_autonomy'),
 ('category_readiness',null,'Recomputes category readiness from data already held; idempotent.','2026-09-02','data_intel_autonomy')
on conflict (action_class) do nothing;
-- 3) REGISTER MISSING EXECUTORS: six rpc executors wrapping REAL zero-arg deterministic functions verified in pg_proc.
--    All low/advisory_safe/reversible, notifies_human=false, no founder gate -> fn_action_invoke_rpc runs them unattended.
insert into public.org_action_executor
 (action_class, kind, target, params, active, note, department, owner_os, risk_tier, reversible,
  idempotency_strategy, timeout_seconds, max_attempts, backoff, required_authority,
  compensation_action_class, notifies_human, unattended_ok, second_authority, advisory_safe)
values
 ('marketplace_analytics','rpc','fn_marketplace_analytics','{}'::jsonb,true,'data_intel: marketplace analytics rollup. Read-only (STABLE), deterministic, no model call.','data_intel','intelligence','low',true,'none_read_only',120,1,null,null,null,false,true,null,true),
 ('kpi_scoreboard','rpc','fn_kpi_scoreboard','{}'::jsonb,true,'data_intel: KPI scoreboard. Read-only, deterministic.','data_intel','intelligence','low',true,'none_read_only',120,1,null,null,null,false,true,null,true),
 ('knowledge_freshness','rpc','fn_knowledge_freshness_sweep','{}'::jsonb,true,'data_intel: knowledge freshness sweep. Idempotent in-place recompute; no delete, no external call.','data_intel','knowledge','low',true,'natural_key',120,1,null,null,null,false,true,null,true),
 ('kb_integrity','rpc','fn_kb_corpus_integrity','{}'::jsonb,true,'data_intel: KB corpus integrity report. Reads corpus, appends a report row.','data_intel','knowledge','low',true,'natural_key',120,1,null,null,null,false,true,null,true),
 ('kb_reconcile','rpc','fn_kb_reconcile','{}'::jsonb,true,'data_intel: KB reconcile. Idempotent in-place bookkeeping.','data_intel','knowledge','low',true,'natural_key',120,1,null,null,null,false,true,null,true),
 ('category_readiness','rpc','fn_category_readiness_recompute','{}'::jsonb,true,'data_intel: category readiness recompute. Idempotent recompute from data already held.','data_intel','knowledge','low',true,'natural_key',120,1,null,null,null,false,true,null,true)
on conflict (action_class) do update set
  kind=excluded.kind, target=excluded.target, department=excluded.department, owner_os=excluded.owner_os,
  risk_tier=excluded.risk_tier, reversible=excluded.reversible, advisory_safe=excluded.advisory_safe,
  idempotency_strategy=excluded.idempotency_strategy, timeout_seconds=excluded.timeout_seconds,
  max_attempts=excluded.max_attempts, required_authority=excluded.required_authority,
  compensation_action_class=excluded.compensation_action_class, notifies_human=excluded.notifies_human,
  unattended_ok=excluded.unattended_ok, second_authority=excluded.second_authority,
  active=excluded.active, note=excluded.note;
commit;

-- ====== legal ======
begin;
set local app.change_reason = 'Founder 2 Sep 2026: departments act autonomously — lift over-gating and register real deterministic executors so each department resolves its own domain issues without the founder.';
-- 1) Add fn_legal_ai to the rpc service-role allow-list FIRST. trg_org_action_executor_guard refuses a kind='rpc' executor whose target is not on this list. fn_legal_ai is SECURITY DEFINER, zero-arg, deterministic (no model call, no external HTTP, no money): reads legal_kpis, upserts legal_kpi_snapshots, refreshes legal_checklist, raises advisory legal_flags.
insert into public.org_action_executor_rpc_allowed (target, note)
select 'fn_legal_ai',
       'Deterministic legal-health routine (SECURITY DEFINER, zero-arg): recomputes legal_kpis, upserts legal_kpi_snapshots, refreshes legal_checklist, raises founder-facing legal_flags. Already run by cron legal_ai_daily. No model call, no money, no external HTTP. Added deliberately so it can be registered as an autonomous legal rpc executor (2026-09-02 expert-staff standard).'
where not exists (select 1 from public.org_action_executor_rpc_allowed where target = 'fn_legal_ai');
-- 2) Register the missing executor: legal_health_scan -> fn_legal_ai (rpc). advisory_safe=true is REQUIRED by fn_action_invoke_rpc's eligibility gate. risk_tier='low' keeps it clear of the org_action_executor_money_legal_second CHECK (which only binds medium/high finance|legal rows).
insert into public.org_action_executor
  (action_class, kind, target, params, active, note, department, owner_os, risk_tier, reversible,
   advisory_safe, idempotency_strategy, timeout_seconds, max_attempts, backoff,
   required_authority, compensation_action_class, notifies_human, unattended_ok, second_authority)
values
  ('legal_health_scan','rpc','fn_legal_ai','{}'::jsonb, true,
   'Autonomous deterministic legal-health scan. Wraps existing fn_legal_ai(): recomputes legal KPIs, upserts the daily legal_kpi_snapshots row, refreshes legal_checklist presence, and raises founder-visible legal_flags (missing core docs / terms-acceptance gaps / stale policies / regulatory change) that are the correct escalation for licensed-lawyer decisions. No model call. Executed by fn_action_invoke_rpc (5-min cron) / fn_workflow_step_sweep.',
   'legal','legal_gov','low', true,
   true, 'natural_key', 60, 1, null,
   null, 'none_required_read_only', false, true, null)
on conflict (action_class) do update set
   kind=excluded.kind, target=excluded.target, department=excluded.department, owner_os=excluded.owner_os,
   risk_tier=excluded.risk_tier, reversible=excluded.reversible, advisory_safe=excluded.advisory_safe,
   idempotency_strategy=excluded.idempotency_strategy, required_authority=excluded.required_authority,
   compensation_action_class=excluded.compensation_action_class, notifies_human=excluded.notifies_human,
   unattended_ok=excluded.unattended_ok, second_authority=excluded.second_authority,
   active=excluded.active, note=excluded.note;
-- 3) Agent-decision gate for the new class: autonomous. Without this row fn_ops_authority_check defaults it to gated.
insert into public.org_authority (dept_key, action_class, max_tier, threshold_aed, note)
values ('legal','legal_health_scan','autonomous', null,
  '2026-09-02 legal-autonomy: deterministic legal-health scan (fn_legal_ai). Read-mostly, reversible, no money, no external commitment; its founder-facing flags are the correct escalation for licensed-lawyer decisions. Expert legal staff run this unattended.')
on conflict (dept_key, action_class) do update set max_tier=excluded.max_tier, threshold_aed=excluded.threshold_aed, note=excluded.note;
-- 4) Declared-gate review row for the new class (null gate). fn_ops_authority_check forces 'gated' for any class with no action_class_gate row, so this is required for autonomy to hold.
insert into public.action_class_gate (action_class, gate_action_class, rationale, reviewed_on, reviewed_by)
values ('legal_health_scan', null,
  'Recomputes legal KPIs and raises advisory legal flags; commits no external position, moves no money, deletes nothing. Acting on a flag is a different, separately gated class. Reviewed for autonomy under the 2 Sep 2026 expert-staff standard.',
  '2026-09-02','legal_autonomy_review')
on conflict (action_class) do nothing;
-- 5) Un-gate compliance_check (was 'advisory'). compliance_archive is deterministic, reversible (manual_reversal) and refuses without a recorded acceptance; its action_class_gate row already carries a null gate, so this alone yields autonomous.
update public.org_authority set max_tier='autonomous',
  note='2026-09-02 legal-autonomy: compliance_archive is deterministic and legal-owned - issues T&C-acceptance certificates and the customer register (records of fact, SHA-256 hashed) and refuses when no acceptance is on record. Reversible (manual_reversal), no money, no external commitment, no model call. Expert compliance staff act unattended. Supersedes the 2026-08-04 advisory caution under the founder''s 2 Sep 2026 expert-staff standard.'
where dept_key='legal' and action_class='compliance_check';
-- 6) Un-gate brand_scan by adding the missing org_authority row (autonomous). The brand_scan action_class_gate row already exists with a null gate, so this row alone flips fn_ops_authority_check from the default 'gated' to autonomous.
insert into public.org_authority (dept_key, action_class, max_tier, threshold_aed, note)
values ('legal','brand_scan','autonomous', null,
  '2026-09-02 legal-autonomy: fn_brand_scan is a deterministic, read-only fraud/impersonation/scam-RFQ scan writing advisory brand_signal rows (no model call). Previously had NO org_authority row, so fn_ops_authority_check defaulted it to gated - over-gating a routine reversible scan the department owns. Expert staff run this unattended.')
on conflict (dept_key, action_class) do update set max_tier=excluded.max_tier, threshold_aed=excluded.threshold_aed, note=excluded.note;
-- 7) Executor-level metadata alignment: mark the two now-autonomous routine executors unattended_ok. This does NOT fire trg_org_action_executor_guard (it triggers only on UPDATE OF kind, target) and is behaviourally a no-op today (both have notifies_human=false, so the runner gates already pass); it makes the 'acts unattended' intent explicit and correct if a future gate reads unattended_ok directly.
update public.org_action_executor set unattended_ok=true
 where department='legal' and action_class in ('brand_scan','compliance_check') and unattended_ok is distinct from true;
commit;

-- ====== people_ops ======
begin;
set local app.change_reason = 'Founder 2 Sep 2026: departments act autonomously — lift over-gating and register real deterministic executors so each department resolves its own domain issues without the founder.';
-- 1) Allow-list the 5 new rpc targets FIRST. fn_org_action_executor_guard (BEFORE INSERT on org_action_executor) rejects any rpc target not present here, because cos_execute runs rpc executors as service-role. Idempotent via NOT EXISTS (table has no unique constraint).
insert into public.org_action_executor_rpc_allowed (target, note)
select v.target, v.note from (values
  ('fn_kpi_review','people_ops autonomy 2026-09-02: weekly KPI review opens remediation + practice training for missed targets (deterministic, no model call)'),
  ('fn_employee_kpi_assign','people_ops autonomy 2026-09-02: ensures every active employee has a KPI tied to its department objective (deterministic)'),
  ('fn_knowledge_exam_summary','people_ops autonomy 2026-09-02: read-only exam-performance summary across the workforce (deterministic)'),
  ('fn_improvement_plan_refresh','people_ops autonomy 2026-09-02: rebuilds each employee improvement_plan from recorded findings/KPIs (deterministic)'),
  ('fn_onboarding_ingest_runs','people_ops autonomy 2026-09-02: advances the onboarding/certification lifecycle from eval runs (deterministic)')
) as v(target, note)
where not exists (select 1 from public.org_action_executor_rpc_allowed a where a.target = v.target);
-- 2) Mark the 5 NEW action classes reviewed with NO hard gate. fn_ops_authority_check forces any class with no action_class_gate row to gated ("unreviewed is not unrestricted"), so this row is required for autonomy. gate_action_class NULL passes action_class_gate_known_gate. PK is action_class -> idempotent. (qa_gate and self_review already have reviewed gate rows.)
insert into public.action_class_gate (action_class, gate_action_class, rationale, reviewed_by) values
 ('performance_review', null, 'Reviews employee KPI attainment and opens internal remediation/practice-training tasks. Reversible, non-money, internal org state only; no external effect. Reviewed for people_ops launch autonomy 2 Sep 2026.', 'people_ops_autonomy_2026_09_02'),
 ('kpi_assign', null, 'Assigns/retires employee KPIs tied to department objectives. Reversible (active flag), non-money, internal. No hard gate.', 'people_ops_autonomy_2026_09_02'),
 ('exam_summary', null, 'Read-only summary of exam performance across employees. No writes, no external effect. No hard gate.', 'people_ops_autonomy_2026_09_02'),
 ('improvement_plan_refresh', null, 'Rebuilds each employee improvement_plan text from recorded findings and missed KPIs. Reversible update, internal. No hard gate.', 'people_ops_autonomy_2026_09_02'),
 ('onboarding_ingest', null, 'Advances onboarding/certification lifecycle from deterministic eval runs. Reversible status transitions, internal. No hard gate.', 'people_ops_autonomy_2026_09_02')
on conflict (action_class) do nothing;
-- 3) Register the 5 missing executors, each wrapping a verified existing zero-arg deterministic SECURITY DEFINER function (no ai_gateway/http). kind=rpc so cos_execute invokes admin.rpc(target, {}). notifies_human=false (none writes a person-facing channel). PK action_class -> idempotent. Runs AFTER statement 1 so the rpc guard passes.
insert into public.org_action_executor
 (action_class, kind, target, params, active, note, department, owner_os, risk_tier, reversible,
  idempotency_strategy, timeout_seconds, max_attempts, backoff, required_authority,
  compensation_action_class, notifies_human, unattended_ok, second_authority, advisory_safe)
values
 ('performance_review','rpc','fn_kpi_review','{}'::jsonb,true,'Culture & Performance: weekly KPI review; opens remediation + practice training for missed targets. Deterministic SQL, no model call.','people_ops','operations','low',true,'natural_key',120,1,null,null,'manual_reversal',false,true,null,true),
 ('kpi_assign','rpc','fn_employee_kpi_assign','{}'::jsonb,true,'HR Director: every active employee gets a KPI tied to its department objective; retires KPIs of departed staff. Deterministic.','people_ops','operations','low',true,'natural_key',90,1,null,null,'manual_reversal',false,true,null,true),
 ('exam_summary','rpc','fn_knowledge_exam_summary','{}'::jsonb,true,'Learning & Development: read-only exam-performance summary across the workforce. No writes.','people_ops','knowledge','low',true,'none_read_only',60,1,null,null,'none_required_read_only',false,true,null,true),
 ('improvement_plan_refresh','rpc','fn_improvement_plan_refresh','{}'::jsonb,true,'Process Improvement: rebuilds each employee improvement_plan from recorded findings and missed KPIs. Reversible text update.','people_ops','operations','low',true,'natural_key',120,1,null,null,'manual_reversal',false,true,null,true),
 ('onboarding_ingest','rpc','fn_onboarding_ingest_runs','{}'::jsonb,true,'Recruitment/Onboarding: advances the onboarding and re-certification lifecycle from deterministic eval runs. Reversible status transitions.','people_ops','operations','low',true,'upsert_on_conflict',90,1,null,null,'manual_reversal',false,true,null,true)
on conflict (action_class) do nothing;
-- 4) Raise the 7 people_ops classes to autonomous. fn_org_authority_guard requires app.change_reason (>=12 chars) on any widen and audits to autonomy_control_audit, so this MUST run as one transaction with SET LOCAL. WHERE clause on the upsert makes re-runs no-ops (no trigger, no audit noise). people_ops is not finance/legal so no second_authority is required.
begin;
set local app.change_reason = 'Launch autonomy 2 Sep 2026: people_ops acts as autonomous expert staff on routine, reversible, non-money HR/knowledge/QA work using deterministic executors; money/refunds, destructive/irreversible and founder-only decisions remain gated.';
insert into public.org_authority (dept_key, action_class, max_tier, note) values
 ('people_ops','performance_review','autonomous','deterministic HR KPI review; reversible, non-money, internal'),
 ('people_ops','kpi_assign','autonomous','deterministic KPI assignment; reversible, non-money, internal'),
 ('people_ops','exam_summary','autonomous','read-only exam summary; no writes'),
 ('people_ops','improvement_plan_refresh','autonomous','deterministic improvement-plan refresh; reversible'),
 ('people_ops','onboarding_ingest','autonomous','deterministic onboarding lifecycle; reversible status transitions'),
 ('people_ops','qa_gate','autonomous','deterministic QA suite (RLS + invariant probes); read-only verdict'),
 ('people_ops','self_review','autonomous','agent self-assessment; reversible, writes self_review proposals only')
on conflict (dept_key, action_class) do update
  set max_tier = excluded.max_tier, note = excluded.note
  where public.org_authority.max_tier is distinct from excluded.max_tier;
commit;
commit;

-- ====== exec ======
begin;
set local app.change_reason = 'Founder 2 Sep 2026: departments act autonomously — lift over-gating and register real deterministic executors so each department resolves its own domain issues without the founder.';
-- 1/7  Authority: exec may run the deterministic strategic risk scan autonomously (new, reviewed class).
insert into public.org_authority (dept_key, action_class, max_tier, threshold_aed, note)
values ('exec','strategy_scan','autonomous', null,
  '2026-09-02: exec (CEO/Strategy Director) runs the deterministic strategic risk scan autonomously. Reversible internal risk register only (strategy_risks, upsert on category+title); no money, no external effect, no LLM.')
on conflict (dept_key, action_class) do update
  set max_tier=excluded.max_tier, note=excluded.note;
-- 2/7  Authority: exec may compute the org performance scorecard autonomously (new, reviewed class).
insert into public.org_authority (dept_key, action_class, max_tier, threshold_aed, note)
values ('exec','org_scorecard','autonomous', null,
  '2026-09-02: exec (Strategy Director) computes the org performance scorecard autonomously. Read-only; commits nothing.')
on conflict (dept_key, action_class) do update
  set max_tier=excluded.max_tier, note=excluded.note;
-- 3/7  Gate review row for strategy_scan (NULL gate = reviewed, no hard gate). Without a gate row fn_ops_authority_check forces the class to gated, so this is required for the autonomous tier to hold.
insert into public.action_class_gate (action_class, gate_action_class, rationale)
values ('strategy_scan', null,
  'Scans live marketplace and finance state and records strategic risks (strategy_risks, upsert on category+title). No external effect; internal and reversible. Any remediation of a risk is filed as its own class with its own gate.')
on conflict (action_class) do update
  set gate_action_class=excluded.gate_action_class, rationale=excluded.rationale;
-- 4/7  Gate review row for org_scorecard (NULL gate = reviewed, read-only).
insert into public.action_class_gate (action_class, gate_action_class, rationale)
values ('org_scorecard', null,
  'Reads department state and returns a performance scorecard. Read-only, commits nothing.')
on conflict (action_class) do update
  set gate_action_class=excluded.gate_action_class, rationale=excluded.rationale;
-- 5/7  Executor: wire the EXISTING autonomous authority initiative_create (already has a gate row) to its deterministic target. fn_objective_review opens corrective initiatives as internal org_tasks (advisory tier, needs_founder=false) and honours the founder stand-down. Closes the 'authority but no wired executor' finding echoed in every exec agent's improvement plan.
insert into public.org_action_executor
 (action_class, kind, target, params, active, note, department, owner_os, risk_tier, reversible,
  advisory_safe, idempotency_strategy, timeout_seconds, max_attempts, backoff,
  required_authority, compensation_action_class, notifies_human, unattended_ok, second_authority)
values
 ('initiative_create','rpc','fn_objective_review','{}'::jsonb, true,
  '2026-09-02: wires exec initiative_create (autonomous authority, already reviewed in action_class_gate) to its deterministic executor. fn_objective_review scans off-target department_objective and goal_period rows and opens corrective initiatives as internal org_tasks (advisory tier, needs_founder=false), honouring company_stand_down. No LLM, no money, reversible (tasks closeable), title-guarded idempotency. Lets cos_execute run it on the deterministic executor path instead of the OpenRouter-off advisory path.',
  'exec','leadership','low', true,
  true,'natural_key',120,1,null,
  null,null,false,true,null)
on conflict (action_class) do update set
  kind=excluded.kind, target=excluded.target, params=excluded.params, active=excluded.active,
  note=excluded.note, department=excluded.department, owner_os=excluded.owner_os,
  risk_tier=excluded.risk_tier, reversible=excluded.reversible, advisory_safe=excluded.advisory_safe,
  idempotency_strategy=excluded.idempotency_strategy, timeout_seconds=excluded.timeout_seconds,
  max_attempts=excluded.max_attempts, backoff=excluded.backoff,
  required_authority=excluded.required_authority, compensation_action_class=excluded.compensation_action_class,
  notifies_human=excluded.notifies_human, unattended_ok=excluded.unattended_ok, second_authority=excluded.second_authority;
-- 6/7  Executor: strategy_scan -> fn_strategy_scan (deterministic risk register; idempotent upsert on category+title).
insert into public.org_action_executor
 (action_class, kind, target, params, active, note, department, owner_os, risk_tier, reversible,
  advisory_safe, idempotency_strategy, timeout_seconds, max_attempts, backoff,
  required_authority, compensation_action_class, notifies_human, unattended_ok, second_authority)
values
 ('strategy_scan','rpc','fn_strategy_scan','{}'::jsonb, true,
  '2026-09-02: exec strategic risk scan. fn_strategy_scan reads live quotes/finance_kpis/market_intel and upserts strategy_risks via fn_strategy_risk (on conflict (category,title) do update), so repeated runs refresh rather than duplicate. Deterministic, no LLM, no money, reversible (risks are dismissable).',
  'exec','intelligence','low', true,
  true,'natural_key',120,1,null,
  null,null,false,true,null)
on conflict (action_class) do update set
  kind=excluded.kind, target=excluded.target, params=excluded.params, active=excluded.active,
  note=excluded.note, department=excluded.department, owner_os=excluded.owner_os,
  risk_tier=excluded.risk_tier, reversible=excluded.reversible, advisory_safe=excluded.advisory_safe,
  idempotency_strategy=excluded.idempotency_strategy, timeout_seconds=excluded.timeout_seconds,
  max_attempts=excluded.max_attempts, backoff=excluded.backoff,
  required_authority=excluded.required_authority, compensation_action_class=excluded.compensation_action_class,
  notifies_human=excluded.notifies_human, unattended_ok=excluded.unattended_ok, second_authority=excluded.second_authority;
-- 7/7  Executor: org_scorecard -> fn_org_scorecard (read-only org performance scorecard; none_read_only idempotency).
insert into public.org_action_executor
 (action_class, kind, target, params, active, note, department, owner_os, risk_tier, reversible,
  advisory_safe, idempotency_strategy, timeout_seconds, max_attempts, backoff,
  required_authority, compensation_action_class, notifies_human, unattended_ok, second_authority)
values
 ('org_scorecard','rpc','fn_org_scorecard','{}'::jsonb, true,
  '2026-09-02: exec org performance scorecard. fn_org_scorecard is STABLE and read-only (open tasks / escalations / dept queue per active department). No writes, no LLM, no money; trivially reversible.',
  'exec','intelligence','low', true,
  true,'none_read_only',60,1,null,
  null,null,false,true,null)
on conflict (action_class) do update set
  kind=excluded.kind, target=excluded.target, params=excluded.params, active=excluded.active,
  note=excluded.note, department=excluded.department, owner_os=excluded.owner_os,
  risk_tier=excluded.risk_tier, reversible=excluded.reversible, advisory_safe=excluded.advisory_safe,
  idempotency_strategy=excluded.idempotency_strategy, timeout_seconds=excluded.timeout_seconds,
  max_attempts=excluded.max_attempts, backoff=excluded.backoff,
  required_authority=excluded.required_authority, compensation_action_class=excluded.compensation_action_class,
  notifies_human=excluded.notifies_human, unattended_ok=excluded.unattended_ok, second_authority=excluded.second_authority;
commit;


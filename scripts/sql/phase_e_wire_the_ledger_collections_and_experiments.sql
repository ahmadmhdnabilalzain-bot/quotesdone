-- PHASE E (7a): WIRE THE FINANCE LEDGER, COLLECTIONS, THE A/B SUBSTRATE AND ONE CHORE — measured first.
--
-- MASTER_PLAN §5.1: "the 66 no-caller functions — a whole double-entry ERP (fn_gl_*/ap/po/inv/fa/
-- budget) and an experiment/A-B framework … Wire the GL/ERP into Finance & Collections or delete;
-- delete the rest. Audit the ERP / A-B framework first." Measured 4 Sep 2026 over the 168
-- phase_c_component rows classified DEFERRED_RUNTIME_IMPLEMENTATION: 91 are pg_trgm / pgvector
-- extension members (pg_depend deptype 'e' — not the estate's to drop, mis-registered as components),
-- 77 are application routines. The audit of the two families:
--
--   GL PROPER  fn_gl_post / fn_gl_entry / fn_gl_reverse / fn_gl_sync_business / fn_gl_net_income are NOT
--              orphans: fn_gl_sync_business posts reveal-fee revenue (net of the Stripe fee) and refunds
--              from public.transactions into gl_journal (73 rows), and cron gl_sync_nightly (jobid 62,
--              '0 2 * * *') calls it — the job has been INACTIVE since the 16 Aug stand-down. The ledger
--              immutability guards (fn_gl_journal_immutable / fn_gl_lines_immutable) are DO-NOT-TOUCH.
--              -> WIRED: the nightly sync is re-enabled through the kernel wrap, owned by the
--              financial_controller seat in finance. Deterministic, no model, sends nothing.
--   SUB-LEDGERS AP/PO/INV/FA/BUDGET (fn_ap_pay, fn_po_*, fn_inv_*, fn_fa_*, fn_budget_create/
--              _set_annual): a marketplace that holds no inventory, no fixed assets and raises no
--              purchase orders; ap_bills 0, po_orders 0, inv_items 0, inv_stock_moves 0, fa_assets 0,
--              budgets 0 rows; expenses reach the company through the expenses mailbox and the
--              invoice_approval workflow, and the live budget mechanism is department_budget
--              (fn_budget_available, called by fn_ai_spend_guard / fn_check_spend).
--              -> DROPPED in phase_e_retire_the_no_caller_functions.sql (13 routines).
--   COLLECTIONS  fn_collections() reminds a supplier, on the portal channel only, of an outstanding
--              non-response charge (supplier_dues.status in due/pending/reminded, every 4 days, max 3);
--              it creates no dues and no commission (founder policy) and emails nobody. The Finance &
--              Collections "Collections" agent (STAFF_ORG #69) has no other deterministic act.
--              -> WIRED: cron collections_reminders_daily, owned by collections_and_revenue_assurance.
--   A/B FRAMEWORK  experiments (2 running since 6 Jul), experiment_assignments (1), experiment_events
--              (0); fn_experiment_assign / _record / _results are the Data & Experimentation "Experiment
--              agent" substrate (STAFF_ORG #48: "sets up, runs, and concludes an experiment").
--              Assignment and recording are calls a product surface makes when it shows a variant;
--              CONCLUDING is the deterministic act nothing performed.
--              -> WIRED: fn_experiment_conclude() (new, below) reads every running experiment through
--              fn_experiment_results, concludes it once every variant has reached the sample floor, and
--              files the winner through fn_agent_decision (which gains its first caller). Cron
--              experiment_conclude_daily, owned by data_intelligence_director.
--   ONE CHORE  fn_blueprint_result_prune() deletes os_blueprint_result rows older than 90 days (7,478
--              rows today, growing on every Row #3 scorer run, no pruner anywhere).
--              -> WIRED: cron blueprint_result_prune_weekly, owned by it_operations_engineer.
--
-- Every cron here runs through fn_kernel_cron_exec (fn_kernel_wrap_and_enable_cron), so its ticks are
-- traced and its component row is owned, and none of them calls a model or sends outbound mail.
-- Reversal: scripts/sql/down/phase_e_wire_the_ledger_collections_and_experiments_down.sql.
--
--   node scripts/apply_sql.mjs scripts/sql/phase_e_wire_the_ledger_collections_and_experiments.sql --apply --ddl

begin;

-- ---------------------------------------------------------------- the concluding act
create or replace function public.fn_experiment_conclude(p_min_subjects integer default 100)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  e record; res jsonb; v_min int; n_var int; winner text; v_open int := 0; v_concluded int := 0; v_action bigint;
begin
  -- The floor is per VARIANT: an experiment concludes only when its smallest arm has p_min_subjects,
  -- so a lopsided assignment cannot crown a winner on a handful of subjects.
  if coalesce(p_min_subjects, 0) < 0 then raise exception 'p_min_subjects must be >= 0'; end if;
  for e in select * from public.experiments where status = 'running' order by key loop
    v_open := v_open + 1;
    res := public.fn_experiment_results(e.key);
    if res is null or jsonb_typeof(res) <> 'object' then continue; end if;
    select min((x.v->>'subjects')::int), count(*) into v_min, n_var from jsonb_each(res) x(k, v);
    if n_var < 2 or coalesce(v_min, 0) < p_min_subjects then continue; end if;
    select x.k into winner from jsonb_each(res) x(k, v)
     order by coalesce((x.v->>'conv_rate_pct')::numeric, 0) desc, x.k limit 1;
    update public.experiments set status = 'concluded', stopped_at = now() where key = e.key;
    -- The decision is filed where every other agent decision is filed. fn_agent_decision escalates
    -- low-confidence or sensitive kinds; an experiment verdict is neither, so it lands as 'pending'
    -- for the Data lead to adopt — the concluding is done, the adoption is the department's act.
    v_action := public.fn_agent_decision(
      'experiment_agent', 'experiment_concluded',
      format('Experiment %s concluded: variant %s wins on %s', e.key, winner, e.metric),
      format('Adopt variant %s for %s (%s). Per-variant results attached.', winner, e.key, e.metric),
      0.9,
      jsonb_build_array(jsonb_build_object('experiment', e.key, 'results', res)),
      'low',
      jsonb_build_object('experiment', e.key, 'winner', winner, 'metric', e.metric, 'results', res,
                         'min_subjects_per_variant', p_min_subjects));
    v_concluded := v_concluded + 1;
  end loop;
  return jsonb_build_object('ok', true, 'running_before', v_open, 'concluded', v_concluded,
                            'min_subjects_per_variant', p_min_subjects);
end $fn$;
comment on function public.fn_experiment_conclude(integer) is
  'Data & Experimentation, Experiment agent: concludes every running experiment whose smallest variant has reached the sample floor, picks the winner by conversion rate (fn_experiment_results) and files it through fn_agent_decision. Deterministic; no model. Cron experiment_conclude_daily.';
-- A plain CREATE grants EXECUTE to PUBLIC; this is SECURITY DEFINER, so close it in the same file.
revoke all on function public.fn_experiment_conclude(integer) from public;
revoke all on function public.fn_experiment_conclude(integer) from anon;
revoke all on function public.fn_experiment_conclude(integer) from authenticated;
grant execute on function public.fn_experiment_conclude(integer) to service_role;

-- ---------------------------------------------------------------- the four entry points
-- The wrap keeps a row's classification; cron:gl_sync_nightly carries INACTIVE_HISTORICAL from the stand-down, and
-- the component classification guard refuses an INACTIVE_* row the moment the job it names becomes reachable.
-- Record what is about to be true first.
update public.phase_c_component set classification = 'WIRE_TO_CANONICAL' where component_id = 'cron:gl_sync_nightly';

do $wire$
declare v jsonb; v_job bigint; r record;
begin
  -- 1. the GL nightly sync, stood down 16 Aug, back under a finance owner
  v := public.fn_kernel_wrap_and_enable_cron(62, 'financial_controller', 'finance', 'routine_operational_decision');
  if coalesce((v->>'ok')::boolean, false) is not true then raise exception 'gl_sync_nightly wrap failed: %', v; end if;
  raise notice 'gl_sync_nightly: %', v->>'action';

  -- 2..4 new jobs, each created idempotently by name and wrapped the same way
  for r in select * from (values
      ('collections_reminders_daily',   '20 6 * * *', 'select public.fn_collections();',           'collections_and_revenue_assurance', 'finance'),
      ('experiment_conclude_daily',     '40 2 * * *', 'select public.fn_experiment_conclude();',   'data_intelligence_director',        'data_intel'),
      ('blueprint_result_prune_weekly', '15 3 * * 0', 'select public.fn_blueprint_result_prune();', 'it_operations_engineer',            'product_eng')
    ) t(jobname, sched, cmd, role_id, dept) loop
    select jobid into v_job from cron.job where jobname = r.jobname;
    if v_job is null then
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.
    end if;
    v := public.fn_kernel_wrap_and_enable_cron(v_job, r.role_id, r.dept, 'routine_operational_decision');
    if coalesce((v->>'ok')::boolean, false) is not true then raise exception '% wrap failed: %', r.jobname, v; end if;
    raise notice '% (jobid %): %', r.jobname, v_job, v->>'action';
  end loop;
end $wire$;

update public.phase_c_component c
   set accountable_role_id = o.role_id, department_id = o.dept, authority_class = 'routine_operational_decision',
       activation_state = 'active',
       repair_or_keep_action = o.why
  from (values
      ('cron:gl_sync_nightly',             'financial_controller',              'finance',     'Phase E 4 Sep 2026: the GL nightly sync (fn_gl_sync_business -> fn_gl_entry -> fn_gl_post) re-enabled under Finance & Collections; stood down 16 Aug with everything else'),
      ('cron:collections_reminders_daily', 'collections_and_revenue_assurance', 'finance',     'Phase E 4 Sep 2026: fn_collections() given its entry point — portal-channel reminders of outstanding non-response charges, max 3, every 4 days; no dues created, no commission, no email'),
      ('cron:experiment_conclude_daily',   'data_intelligence_director',        'data_intel',  'Phase E 4 Sep 2026: the Experiment agent concludes experiments deterministically (fn_experiment_conclude -> fn_experiment_results -> fn_agent_decision)'),
      ('cron:blueprint_result_prune_weekly','it_operations_engineer',           'product_eng', 'Phase E 4 Sep 2026: fn_blueprint_result_prune() given its entry point — os_blueprint_result rows older than 90 days are pruned weekly')
    ) o(component_id, role_id, dept, why)
 where c.component_id = o.component_id;

-- ---------------------------------------------------------------- the routines behind them are owned
insert into public.phase_c_component(
    component_id, component_type, source_path_or_db_object, entry_method, current_callers, external_entry,
    schedule_or_trigger, mutates_state, current_actor, canonical_system_actor, accountable_role_id,
    department_id, workflow_id, step_id, authority_class, trace_policy_id, idempotency_strategy, retry_policy,
    activation_state, classification, gap, repair_or_keep_action, evidence, measured_at)
values (
    'dbfn:fn_experiment_conclude(p_min_subjects integer)', 'database_function', 'public.fn_experiment_conclude',
    'called by cron experiment_conclude_daily through fn_kernel_cron_exec', 'cron:experiment_conclude_daily', 'no',
    '', true, 'service_role', 'system.scheduler', 'data_intelligence_director',
    'data_intel', 'SYSTEM_SCOPE', '', 'routine_operational_decision', 'TRACE-ROLE-ACTION',
    'experiment_key:status_transition_running_to_concluded', 'next_scheduled_tick',
    'active', 'WIRE_TO_CANONICAL', '', 'keep: the Experiment agent''s concluding act',
    'phase_e_wire_the_ledger_collections_and_experiments.sql 2026-09-04: new; concludes running experiments once every variant reaches the sample floor', now()::date)
on conflict (component_id) do update set
    current_callers = excluded.current_callers, activation_state = 'active', classification = 'WIRE_TO_CANONICAL',
    accountable_role_id = excluded.accountable_role_id, department_id = excluded.department_id,
    trace_policy_id = excluded.trace_policy_id, evidence = excluded.evidence, gap = '';

update public.phase_c_component c
   set activation_state = 'active', classification = 'WIRE_TO_CANONICAL', current_callers = o.callers,
       accountable_role_id = o.role_id, department_id = o.dept, workflow_id = case when c.workflow_id in ('', 'OUT_OF_SCOPE') then 'SYSTEM_SCOPE' else c.workflow_id end,
       canonical_system_actor = case when c.canonical_system_actor = '' then 'system.scheduler' else c.canonical_system_actor end,
       authority_class = case when coalesce(c.authority_class, '') = '' then 'routine_operational_decision' else c.authority_class end,
       -- TRACE-ROLE-ACTION, the estate's policy for a routine a traced cron calls (fn_gl_sync_business,
       -- fn_doc_expiry_scan, fn_budget_rollup carry it; 827 of 836 deployed routine components do). The
       -- TRACE is the cron tick's, written by fn_kernel_cron_exec; putting the routine itself on
       -- TRACE-SYSTEM-EXECUTION would add a component that can never carry its own trace to the
       -- fn_kernel_trace_integrity ratchet.
       trace_policy_id = 'TRACE-ROLE-ACTION',
       entry_method = 'called through fn_kernel_cron_exec from ' || o.callers,
       gap = '', repair_or_keep_action = 'wired 4 Sep 2026 (Phase E)', evidence = o.evidence, measured_at = now()::date
  from (values
      ('dbfn:fn_collections()',                        'cron:collections_reminders_daily', 'collections_and_revenue_assurance', 'finance',    'phase_e_wire_the_ledger_collections_and_experiments.sql 2026-09-04: measured 0 callers (routine/cron/trigger/view/RLS/repo); wired as the Collections agent''s daily reminder run'),
      ('dbfn:fn_experiment_results(p_key text)',       'dbfn:fn_experiment_conclude(p_min_subjects integer)', 'data_intelligence_director', 'data_intel', 'phase_e_wire_the_ledger_collections_and_experiments.sql 2026-09-04: measured 0 callers; now read by fn_experiment_conclude for every running experiment'),
      ('dbfn:fn_experiment_assign(p_key text, p_subject text)', 'product surface (variant exposure) + experiment_conclude_daily reads its assignments', 'data_intelligence_director', 'data_intel', 'phase_e_wire_the_ledger_collections_and_experiments.sql 2026-09-04: the A/B substrate the Experiment agent concludes over; assignment is the product surface''s call at exposure time'),
      ('dbfn:fn_experiment_record(p_key text, p_subject text, p_event text, p_value numeric)', 'product surface (conversion event) + experiment_conclude_daily reads its events', 'data_intelligence_director', 'data_intel', 'phase_e_wire_the_ledger_collections_and_experiments.sql 2026-09-04: the A/B substrate the Experiment agent concludes over; recording is the product surface''s call at conversion'),
      ('dbfn:fn_agent_decision(p_agent text, p_kind text, p_title text, p_recommendation text, p_confidence numeric, p_evidence jsonb, p_risk text, p_detail jsonb)', 'dbfn:fn_experiment_conclude(p_min_subjects integer)', 'data_intelligence_director', 'data_intel', 'phase_e_wire_the_ledger_collections_and_experiments.sql 2026-09-04: measured 0 callers; fn_experiment_conclude files every concluded experiment through it; owner moved from agent_workforce_capability_director (no longer resolves as an active canonical role) to the caller''s seat'),
      ('dbfn:fn_blueprint_result_prune()',             'cron:blueprint_result_prune_weekly', 'it_operations_engineer', 'product_eng', 'phase_e_wire_the_ledger_collections_and_experiments.sql 2026-09-04: measured 0 callers; wired as a weekly retention chore over os_blueprint_result')
    ) o(component_id, callers, role_id, dept, evidence)
 where c.component_id = o.component_id;

insert into public.kernel_routine_ownership(schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file, justification, recorded_at)
values ('public', 'fn_experiment_conclude', 'p_min_subjects integer', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT',
        'defined by scripts/sql/phase_e_wire_the_ledger_collections_and_experiments.sql (Phase E, 4 Sep 2026)', 'MANIFEST',
        'scripts/sql/phase_e_wire_the_ledger_collections_and_experiments.sql', null, now())
on conflict do nothing;

-- ---------------------------------------------------------------- proof, in the same transaction
do $proof$
declare v_raw int; v_probe text; v_j jsonb; v_before int; v_after int; v_actions int;
begin
  select count(*) into v_raw from cron.job
   where jobname in ('gl_sync_nightly', 'collections_reminders_daily', 'experiment_conclude_daily', 'blueprint_result_prune_weekly')
     and (not active or command not ilike '%fn_kernel_cron_exec%');
  if v_raw > 0 then raise exception '% of the four jobs are raw or inactive', v_raw; end if;
  if (select count(*) from cron.job where jobname in ('gl_sync_nightly', 'collections_reminders_daily', 'experiment_conclude_daily', 'blueprint_result_prune_weekly')) <> 4 then
    raise exception 'not all four jobs exist';
  end if;
  if (select count(*) from public.phase_c_component where component_id in ('cron:gl_sync_nightly', 'cron:collections_reminders_daily', 'cron:experiment_conclude_daily', 'cron:blueprint_result_prune_weekly') and activation_state = 'active' and accountable_role_id in (select role_id from public.org_role where status = 'active')) <> 4 then
    raise exception 'the four cron components are not all active under an active role';
  end if;
  if has_function_privilege('anon', 'public.fn_experiment_conclude(integer)', 'execute') then raise exception 'anon can execute fn_experiment_conclude'; end if;
  if has_function_privilege('authenticated', 'public.fn_experiment_conclude(integer)', 'execute') then raise exception 'authenticated can execute fn_experiment_conclude'; end if;

  -- the concluding act, driven and rolled back. Today homepage_cta has ONE assignment (one variant)
  -- and supplier_invite_count none, so at any floor neither may conclude — a lopsided arm is exactly
  -- what the per-variant floor refuses. The probe gives homepage_cta one ZZ-DEMO subject per variant,
  -- concludes at a floor of 1, and expects exactly that experiment to conclude with one agent_actions
  -- row filed; the sub-block raises so nothing survives.
  begin
    select count(*) into v_before from public.experiments where status = 'running';
    select count(*) into v_actions from public.agent_actions where kind = 'experiment_concluded';
    v_j := public.fn_experiment_conclude(1);
    if (v_j->>'concluded')::int <> 0 then raise exception 'PROBE|FAIL a lopsided experiment concluded: %', v_j; end if;
    insert into public.experiment_assignments(experiment, subject, variant)
      select 'homepage_cta', 'zz-demo-phase-e-probe-' || v.name, v.name
        from jsonb_to_recordset((select variants from public.experiments where key = 'homepage_cta')) v(name text, weight int);
    v_j := public.fn_experiment_conclude(1);
    select count(*) into v_after from public.experiments where status = 'running';
    raise exception 'PROBE|running_before=%|concluded=%|running_after=%|actions_added=%|homepage_cta=%',
      v_before, v_j->>'concluded', v_after,
      (select count(*) from public.agent_actions where kind = 'experiment_concluded') - v_actions,
      (select status from public.experiments where key = 'homepage_cta');
  exception when others then
    v_probe := sqlerrm;
  end;
  if v_probe not like 'PROBE|running_before=%' then raise exception 'fn_experiment_conclude probe failed: %', v_probe; end if;
  if v_probe not like '%|concluded=1|%' or v_probe not like '%|actions_added=1|%' or v_probe not like '%|homepage_cta=concluded' then
    raise exception 'fn_experiment_conclude did not conclude the experiment it should have: %', v_probe;
  end if;
  if exists (select 1 from public.experiment_assignments where subject like 'zz-demo-phase-e-probe-%') then
    raise exception 'probe residue: fixture assignments survived the aborted block';
  end if;
  if (select count(*) from public.experiments where status = 'running') <> v_before then
    raise exception 'probe residue: experiments changed outside the aborted block';
  end if;
  -- at the real floor nothing concludes today (1 assignment across 2 experiments), and that is the point
  v_j := public.fn_experiment_conclude();
  if (v_j->>'concluded')::int <> 0 then raise exception 'the default floor concluded an experiment on % subject(s)', v_j; end if;
  raise notice 'proof: four jobs wrapped and active; aborted drive %; default floor run %', v_probe, v_j;
end $proof$;

commit;

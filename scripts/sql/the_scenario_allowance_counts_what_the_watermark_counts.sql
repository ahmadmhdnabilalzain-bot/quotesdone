-- THE SCENARIO ALLOWANCE COUNTS WHAT THE WATERMARK COUNTS (6 Sep 2026). Follows the_scenario_watermark_ignores_the_schedulers_own_traces.sql.
--
-- MEASURED in the aborted probe after that file: "watermark drift: public.phase_c_trace 1079 -> 1080".
-- The scenario writes five traces (workflow_run, step_run x2, task, and one system_execution for
-- fn_kernel_trigger_submit); close() keeps the anchored chain — the system_execution trace and its
-- parent task — so v_ao was 2, while the filtered watermark counts only the parent: 1079 + 1 = 1080
-- against an allowance of 1081. The allowance now counts retained traces the way the watermark
-- counts traces, and the Q04 rule ("exactly v_ao above, not one row more") holds again. Nothing
-- else in the door changes; the retained rows are still disclosed on the scenario row.
--
--   node scripts/apply_sql.mjs scripts/sql/the_scenario_allowance_counts_what_the_watermark_counts.sql --apply --ddl

CREATE OR REPLACE FUNCTION public.fn_phase_d_committed_scenario_close(p_scenario_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_ao bigint := 0;      -- Q04: traces retained because an execution record references one
  v_keep bigint[] := '{}';  -- Q04: those traces AND their ancestors
  s         public.phase_d_committed_scenario%rowtype;
  v_removed jsonb := '{}'::jsonb;
  v_n       bigint;
  v_wm      jsonb;
  v_drift   text;
  v_cust    uuid;
  v_inq     uuid;
  v_lead    bigint;
  -- A NULL SUBJECT MAKES EVERY `like '%'||subject||'%'` RETURN NULL AND DELETE NOTHING, SILENTLY.
  -- The scenario no longer creates an inquiry (see open()), so these are text sentinels that match
  -- no row rather than nulls that match no row for the wrong reason.
  v_cust_t  text;
  v_inq_t   text;
  v_mail    text;
  v_runs    bigint[];
  v_xid     bigint := mod(pg_current_xact_id()::text::bigint, 4294967296);
begin
  select * into s from public.phase_d_committed_scenario where scenario_id = p_scenario_id;
  if not found then
    raise exception 'fn_phase_d_committed_scenario_close: no scenario % (pdcs_unknown)', p_scenario_id using errcode = '22023';
  end if;
  if s.state <> 'OPEN' then
    raise exception 'fn_phase_d_committed_scenario_close: scenario % is % (pdcs_not_open)', p_scenario_id, s.state using errcode = '23514';
  end if;

  v_cust := (s.created->>'customer_id')::uuid;
  v_inq  := (s.created->>'inquiry_id')::uuid;
  v_lead := (s.created->>'lead_id')::bigint;
  v_cust_t := coalesce(v_cust::text, '00000000-0000-0000-0000-000000000000');
  v_inq_t  := coalesce(v_inq::text,  '00000000-0000-0000-0000-000000000000');
  v_mail := coalesce(s.created->>'customer_email','');
  select coalesce(array_agg(x::bigint), '{}'::bigint[]) into v_runs
    from jsonb_array_elements_text(coalesce(s.created->'phase_c_workflow_run_ids','[]'::jsonb)) x;

  perform set_config('kernel.maintenance_reason',
    format('phase_d_committed_scenario %s (%s): reversing the committed fixture', s.scenario_id, s.label), true);

  -- dependency order: the kernel's own rows first, then the derived queues, then the business rows.
  delete from public.phase_d_effect_ledger where run_id = any(v_runs);
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.phase_d_effect_ledger', v_n); end if;

  delete from public.phase_d_dispatch where run_id = any(v_runs);
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.phase_d_dispatch', v_n); end if;

  delete from public.phase_c_step_completion where run_id = any(v_runs);
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.phase_c_step_completion', v_n); end if;

  delete from public.phase_c_handoff_run where run_id = any(v_runs);
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.phase_c_handoff_run', v_n); end if;

  delete from public.phase_c_task where run_id = any(v_runs);
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.phase_c_task', v_n); end if;

  -- Q04. A TRACE AN APPEND-ONLY EXECUTION RECORD REFERENCES CANNOT BE DELETED, AND MUST NOT BE.
  -- phase_c_system_execution.trace_id is ON DELETE CASCADE, and
  -- z10_phase_c_system_execution_append_only refuses every DELETE with no maintenance door — by
  -- design: 'an execution record that can be edited after the fact records the editor, not the
  -- execution.' So this statement used to succeed only because nothing in the scenario produced
  -- one. phase_d_q03 attached the canonical customer-created adapter to public.customers, this
  -- scenario's fixture INSERTS a customer, and the adapter now writes a TRACE-SYSTEM-EXECUTION
  -- trace with its execution row. The cascade then hit the guard and the whole close threw.
  --
  -- The reversal is not weakened; it is made truthful. Those traces are COUNTED, retained, and
  -- disclosed on the scenario row, and the watermark assertion below allows phase_c_trace to sit
  -- exactly v_ao above its watermark and not one row more. Everything else still fails hard.
  -- The retained set is the append-only-backed traces AND EVERY ANCESTOR OF ONE.
  -- phase_c_trace_parent_trace_id_fkey is a self-reference with no cascade, so deleting the parent
  -- of a retained trace is refused too — found on the first rehearsal of this file, which is what
  -- rehearsing is for. The recursion walks parent_trace_id upward, which terminates because a trace
  -- ledger is a tree.
  with recursive anchored as (
    select t.trace_id, t.parent_trace_id
      from public.phase_c_trace t
     where t.run_id = any(v_runs)
       and exists (select 1 from public.phase_c_system_execution se where se.trace_id = t.trace_id)
    union
    select p.trace_id, p.parent_trace_id
      from public.phase_c_trace p
      join anchored a on a.parent_trace_id = p.trace_id
  )
  select coalesce(array_agg(distinct trace_id), '{}') into v_keep from anchored;

  -- 6 SEP 2026: v_ao is the retained rows the WATERMARK counts. The watermark for phase_c_trace
  -- excludes the scheduler's own executions (phase_d_committed_scenario_watch.count_filter =
  -- subject_kind <> 'system_execution'), so a retained system_execution trace must not be added to
  -- the allowance either, or Q04 asks for one row more than the filtered count can ever show.
  select count(*) into v_ao from public.phase_c_trace t
   where t.run_id = any(v_runs) and t.trace_id = any(v_keep)
     and t.subject_kind <> 'system_execution';

  delete from public.phase_c_trace t
   where t.run_id = any(v_runs) and not (t.trace_id = any(v_keep));
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.phase_c_trace', v_n); end if;
  if v_ao > 0 then
    v_removed := v_removed || jsonb_build_object('public.phase_c_trace_retained_append_only', v_ao);
  end if;

  delete from public.phase_c_workflow_step_run where run_id = any(v_runs);
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.phase_c_workflow_step_run', v_n); end if;

  delete from public.phase_c_event_outbox
   where workflow_run_id = any(v_runs) or payload::text like '%'||v_inq_t||'%';
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.phase_c_event_outbox', v_n); end if;

  delete from public.phase_c_workflow_run where run_id = any(v_runs);
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.phase_c_workflow_run', v_n); end if;

  delete from public.kernel_trigger_inbox
   where run_id = any(v_runs) or source_ref like '%'||v_inq_t||'%'
      or business_object_id like '%'||v_inq_t||'%' or raw_payload::text like '%'||v_inq_t||'%';
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.kernel_trigger_inbox', v_n); end if;

  delete from public.inquiry_matches where inquiry_id = v_inq;
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.inquiry_matches', v_n); end if;

  delete from public.notifications where inquiry_id = v_inq or (v_mail <> '' and to_email = v_mail);
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.notifications', v_n); end if;

  delete from public.event_delivery where event_id in
    (select id from public.company_event where entity_id in (v_inq_t, v_cust_t)
        or payload::text like '%'||v_inq_t||'%' or payload::text like '%'||v_cust_t||'%');
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.event_delivery', v_n); end if;

  delete from public.event_assessment where event_id in
    (select id from public.company_event where entity_id in (v_inq_t, v_cust_t)
        or payload::text like '%'||v_inq_t||'%' or payload::text like '%'||v_cust_t||'%');
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.event_assessment', v_n); end if;

  delete from public.company_event where entity_id in (v_inq_t, v_cust_t)
     or payload::text like '%'||v_inq_t||'%' or payload::text like '%'||v_cust_t||'%';
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.company_event', v_n); end if;

  delete from public.customer_preference where customer_id = v_cust;
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.customer_preference', v_n); end if;

  delete from public.doc_versions where entity_id in (v_inq_t, v_cust_t);
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.doc_versions', v_n); end if;

  delete from public.founder_alerts where detail::text like '%'||v_inq_t||'%' or detail::text like '%'||v_cust_t||'%';
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.founder_alerts', v_n); end if;

  delete from public.documents where ref_id in (v_inq_t, v_cust_t);
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.documents', v_n); end if;

  delete from public.doc_backups where entity_id in (v_inq_t, v_cust_t)
     or dedupe_key in ('C:'||v_cust_t||':details', 'I:'||v_inq_t||':summary');
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.doc_backups', v_n); end if;

  delete from public.quotes where inquiry_id = v_inq;
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.quotes', v_n); end if;

  delete from public.inquiries where id = v_inq;
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.inquiries', v_n); end if;

  delete from public.leads where id = v_lead;
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.leads', v_n); end if;

  delete from public.customers where id = v_cust;
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.customers', v_n); end if;

  delete from public.undo_log where public.fn_phase_d_row_is_ours(xmin);
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.undo_log', v_n); end if;

  -- (f) ASSERT. Every watermark restored, every queue empty of our rows, residue zero.
  v_wm := public.fn_phase_d_committed_scenario_watermarks();
  select string_agg(format('%s %s -> %s', k, s.watermarks->>k, v_wm->>k), '; ')
    into v_drift
    from jsonb_object_keys(s.watermarks) k
   where (v_wm->>k) is distinct from (s.watermarks->>k)
     -- Q04: phase_c_trace is allowed to sit EXACTLY v_ao above its watermark and not one row more.
     -- v_ao is counted, not assumed, and it is disclosed on the scenario row.
     and not (k = 'public.phase_c_trace'
              and (v_wm->>k)::bigint = (s.watermarks->>k)::bigint + v_ao)
     -- kernel_maintenance_write is the RECEIPT fn_kernel_write_guard demands for the deletes above.
     -- Removing it would defeat the guard that permitted them. Counted and disclosed, never hidden.
     and k <> 'public.kernel_maintenance_write'
     -- net.http_request_queue's max id is monotone and shared; its assertion is the one below.
     and k <> 'net.http_request_queue_max_id';

  select count(*) into v_n from net.http_request_queue q
   where q.url like '%'||v_inq_t||'%' or q.body::text like '%'||v_inq_t||'%'
      or q.url like '%'||v_cust_t||'%' or q.body::text like '%'||v_cust_t||'%';

  if v_drift is not null or v_n > 0 then
    update public.phase_d_committed_scenario
       set state = 'FAILED', closed_at = now(), removed = v_removed,
           assertions = jsonb_build_object('watermark_drift', coalesce(v_drift,'(none)'),
                                           'phase_c_trace_retained_append_only', v_ao,
                                           'outbound_requests_naming_the_fixture', v_n)
     where scenario_id = p_scenario_id;
    raise exception 'fn_phase_d_committed_scenario_close: a survivor is a hard stop. watermark drift: %; outbound requests naming the fixture: % (pdcs_residue_survived)',
      coalesce(v_drift,'(none)'), v_n using errcode = '23514';
  end if;

  select count(*) into v_n from public.fn_phase_d_fixture_residue();
  if v_n > 0 then
    raise exception 'fn_phase_d_committed_scenario_close: fn_phase_d_fixture_residue() reports % relation(s) (pdcs_fixture_residue)', v_n
      using errcode = '23514';
  end if;

  update public.phase_d_committed_scenario
     set state = 'CLOSED', closed_at = now(), removed = v_removed,
         assertions = jsonb_build_object(
           'every_watched_relation_back_at_its_watermark', true,
           'relations_compared', (select count(*) from jsonb_object_keys(s.watermarks) k),
           'outbound_requests_naming_the_fixture', 0,
           'fn_phase_d_fixture_residue', 0,
           'phase_c_trace_retained_because_an_append_only_execution_references_it', v_ao,
           'kernel_maintenance_write_receipts_added',
             (v_wm->>'public.kernel_maintenance_write')::bigint - (s.watermarks->>'public.kernel_maintenance_write')::bigint)
   where scenario_id = p_scenario_id;

  return jsonb_build_object('ok', true, 'scenario_id', p_scenario_id, 'removed', v_removed);
end $function$;

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_scenario_allowance_counts_what_the_watermark_counts.sql',
       evidence = 'the retained-trace allowance follows the watermark filter (6 Sep 2026)'
 where schema_name = 'public' and routine_name = 'fn_phase_d_committed_scenario_close';

-- Q04 DOWN. RE-APPLY THE BODY THAT COULD NOT REVERSE AN APPEND-ONLY EXECUTION RECORD.
--
-- NO TRANSACTION CONTROL. One statement.
--
-- Read out of production with pg_get_functiondef before Q04 ran. APPLYING THIS RESTORES THE
-- FAILURE: fn_phase_d_committed_scenario_close throws 23514 on every close, because the fixture
-- customer phase_d_q03 routes into the kernel leaves an execution record the delete cascade is
-- refused. kernel_positive_controls goes back to 20 of 21.

CREATE OR REPLACE FUNCTION public.fn_phase_d_committed_scenario_close(p_scenario_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
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

  delete from public.phase_c_trace where run_id = any(v_runs);
  get diagnostics v_n = row_count; if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.phase_c_trace', v_n); end if;

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
           'kernel_maintenance_write_receipts_added',
             (v_wm->>'public.kernel_maintenance_write')::bigint - (s.watermarks->>'public.kernel_maintenance_write')::bigint)
   where scenario_id = p_scenario_id;

  return jsonb_build_object('ok', true, 'scenario_id', p_scenario_id, 'removed', v_removed);
end $function$;

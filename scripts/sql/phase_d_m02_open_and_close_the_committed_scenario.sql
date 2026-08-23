-- M02 — open and close the committed scenario, and prove the reversal rather than assert it
--
-- One audited operation, in two halves that cannot disagree because they measure through the same
-- function (public.fn_phase_d_committed_scenario_watermarks).
--
-- open()  refuses unless every guard in fn_phase_d_committed_scenario_guards() is green, takes a
--         watermark for every watched relation, creates the fixture through the product's own
--         relations, quarantines both cron jobs that could reach it, removes every queue row the
--         transaction produced, and asserts that nothing outbound was enqueued. It is ONE
--         statement and therefore ONE transaction: it commits a scenario it has already proved it
--         can reverse, or it commits nothing at all.
--
-- close() removes what open() recorded, in dependency order, then re-measures every watermark and
--         refuses to record success while one row survives.
--
-- WHY DELETE IS THE RIGHT VERB HERE AND NOWHERE ELSE. public.phase_d_object_record refuses DELETE
-- outright -- pd_object_delete_refused, "business records are never deleted" -- and has no
-- maintenance door. A scenario that produced one could not be reversed, so open() asserts that
-- relation is back at its watermark before it commits and aborts the whole transaction if it is
-- not. Nothing this operation creates is a business record in that sense.
--
-- EVERY COLUMN NAMED BELOW WAS READ OUT OF information_schema FIRST. The first draft of this file
-- named inquiries.title, inquiries.description and inquiries.contact_email, none of which exist;
-- a cleanup statement that names a column the table does not have is a cleanup that silently does
-- nothing, which is the whole failure this operation exists to make impossible.
--
-- REQUIRES: M01.
-- ROLLBACK: scripts/sql/down/phase_d_m02_open_and_close_the_committed_scenario_down.sql

-- ================================================================================================
create or replace function public.fn_phase_d_committed_scenario_open(p_input jsonb)
returns jsonb
language plpgsql
set search_path to 'public','pg_temp'
as $function$
declare
  v_label   text := nullif(btrim(coalesce(p_input->>'label','')),'');
  v_id      bigint;
  v_guards  jsonb;
  v_bad     text;
  v_wm      jsonb;
  v_net0    bigint;
  v_cust    uuid;
  v_inq     uuid;
  v_lead    bigint;
  v_created jsonb;
  v_removed jsonb := '{}'::jsonb;
  v_n       bigint;
  v_xid     bigint := mod(pg_current_xact_id()::text::bigint, 4294967296);
  r         record;
  v_email   text;
  v_runs    jsonb;
begin
  if v_label is null then
    raise exception 'fn_phase_d_committed_scenario_open: label is required; it is what makes the rows findable (pdcs_label_missing)'
      using errcode = '22023';
  end if;

  -- (a) REFUSE TO START unless every door is provably closed. Measured, not assumed.
  select jsonb_agg(jsonb_build_object('check', g.check_name, 'ok', g.ok, 'detail', g.detail)),
         string_agg(g.check_name || ': ' || g.detail, ' | ') filter (where not g.ok)
    into v_guards, v_bad
    from public.fn_phase_d_committed_scenario_guards() g;
  if v_bad is not null then
    raise exception 'fn_phase_d_committed_scenario_open: refused, a guard is red -- % (pdcs_guard_red)', v_bad
      using errcode = '23514';
  end if;

  -- (b) a watermark for every watched relation and every derived queue
  v_wm := public.fn_phase_d_committed_scenario_watermarks();
  select coalesce(max(id),0) into v_net0 from net.http_request_queue;

  -- the unique partial index refuses a second concurrent OPEN
  insert into public.phase_d_committed_scenario (label, state, guards, watermarks)
  values (v_label, 'OPEN', v_guards, v_wm) returning scenario_id into v_id;

  perform set_config('kernel.maintenance_reason',
    format('phase_d_committed_scenario %s (%s): removing the queue rows this transaction produced so no consumer can act on a fixture',
           v_id, v_label), true);

  -- (c) the fixture, through the product's own relations. ZZ DEMO and @example.invalid are the
  --     estate's existing marker convention, which fn_phase_d_fixture_residue() already scans for.
  v_email := format('zz-phase-d-cs-%s@example.invalid', v_id);
  insert into public.customers (full_name, email, phone)
  values (format('ZZ DEMO — committed scenario %s', v_id), v_email, '+971500000000')
  returning id into v_cust;

  -- quarantine cron 88 for this customer, in the same instant the customer exists. The dedupe key
  -- is fn_enqueue_doc_backups's own: 'C:'||customers.id||':details'. status 'done' is outside the
  -- ('pending','error') set the edge processor selects.
  insert into public.doc_backups (entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key, status)
  values ('customer', v_cust::text, 'Customer Details', 'generated', 'customer_details', v_cust::text,
          '/QuotesDone Backup/ZZ DEMO PHASE D COMMITTED SCENARIO/Customer Details.pdf',
          'C:'||v_cust||':details', 'done');

  -- AN INQUIRY IS REFUSED HERE, AND THE REASON IS A MEASUREMENT, NOT A PREFERENCE.
  -- The founder's list permits one. The estate does not, while zero residue also holds:
  -- public.inquiries AFTER INSERT fires trg_inquiry_received_a, which is a registered ACTIVE
  -- class A NEW_WORK_REQUEST source; fn_kernel_trigger_submit starts a real W05 run, and
  -- phase_c_workflow_step_run AFTER INSERT writes public.phase_c_trace. Rehearsed 23 Aug 2026
  -- in an aborted transaction, close() then failed on
  --   "phase_c_system_execution is append-only: DELETE on trace 1931857 refused"
  -- -- public.phase_c_system_execution is reached by ON DELETE CASCADE from phase_c_trace and its
  -- z10 trigger refuses DELETE unconditionally, with no kernel.maintenance_reason door. Both
  -- relations are the FROZEN Phase C subject 'trace_ledger'. Deleting from them needs a Phase C
  -- change request and the founder's approval; weakening the trigger to let this operation clean
  -- up after itself would be the same thing by another route. So a committed inquiry is refused
  -- here by name, and PD-PRIV-004 -- the one defect that needs one -- is recorded as a permanent
  -- exemption carrying exactly this reason rather than closed by leaving ledger rows behind.
  if coalesce((p_input->>'create_inquiry')::boolean, false) then
    raise exception 'fn_phase_d_committed_scenario_open: a committed inquiry starts a kernel run whose phase_c_trace cascades to phase_c_system_execution, which refuses DELETE and is a frozen Phase C subject; this operation would not be able to return every persistent count to its watermark (pdcs_inquiry_is_irreversible)'
      using errcode = '23514';
  end if;

  -- A supplier the assignment path can be shown. Unapproved and unverified, so
  -- enrich_capability_on_approve does not fire and fn_assign_founding_rank assigns no rank --
  -- the same two conditions the section 8 harness measured and asserts.
  insert into public.leads (company_name, email, approval_status, verified, source)
  values (format('ZZ DEMO — committed scenario %s supplier', v_id),
          format('zz-phase-d-cs-%s-sup@example.invalid', v_id), 'pending', false, 'phase_d_committed_scenario')
  returning id into v_lead;

  select coalesce(jsonb_agg(w.run_id), '[]'::jsonb) into v_runs
    from public.phase_c_workflow_run w where public.fn_phase_d_row_is_ours(w.xmin);

  -- (d) NEUTRALISE every queue row THIS TRANSACTION produced, before it commits. xmin attribution,
  --     not a watermark delta over a shared table: another session's row is not ours to remove.
  for r in select relation from public.phase_d_committed_scenario_watch
            where is_queue and relation not in ('public.doc_backups','public.undo_log')
            order by case relation
                       when 'public.org_tasks'            then 1
                       when 'public.event_delivery'       then 2
                       when 'public.event_assessment'     then 3
                       when 'public.company_event'        then 4
                       when 'public.phase_c_event_outbox' then 5
                       when 'public.kernel_trigger_inbox' then 6
                       else 9 end
  loop
    execute format('delete from %s where public.fn_phase_d_row_is_ours(xmin)', r.relation);
    get diagnostics v_n = row_count;
    if v_n > 0 then v_removed := v_removed || jsonb_build_object(r.relation, v_n); end if;
  end loop;
  -- deleting org_tasks writes undo_log; that is ours too
  delete from public.undo_log where public.fn_phase_d_row_is_ours(xmin);
  get diagnostics v_n = row_count;
  if v_n > 0 then v_removed := v_removed || jsonb_build_object('public.undo_log', v_n); end if;

  -- (e) NOTHING OUTBOUND. The xmin helper J04 wrote, not a max(id) delta.
  select r2.n into v_n from public.fn_phase_d_outbound_requests_by_this_transaction(v_net0) r2;
  if coalesce(v_n,0) > 0 then
    raise exception 'fn_phase_d_committed_scenario_open: the fixture enqueued % outbound HTTP request(s); the whole transaction is refused (pdcs_outbound_request_produced)', v_n
      using errcode = '23514';
  end if;

  -- (f) A RECORD THIS OPERATION CANNOT REVERSE IS A STOP, NOT A NOTE.
  select count(*) into v_n from public.phase_d_object_record;
  if v_n <> (v_wm->>'public.phase_d_object_record')::bigint then
    raise exception 'fn_phase_d_committed_scenario_open: phase_d_object_record moved % -> %, and that relation refuses DELETE, so this scenario could not be reversed (pdcs_irreversible_record)',
      v_wm->>'public.phase_d_object_record', v_n using errcode = '23514';
  end if;

  v_created := jsonb_build_object(
    'customer_id', v_cust, 'lead_id', v_lead, 'customer_email', v_email,
    'doc_backups_dedupe_keys', jsonb_build_array('C:'||v_cust||':details'),
    'phase_c_workflow_run_ids', v_runs);

  update public.phase_d_committed_scenario
     set created = v_created, removed = v_removed,
         assertions = jsonb_build_object(
           'outbound_http_requests_by_this_transaction', 0,
           'phase_d_object_record_unchanged', true,
           'queue_rows_removed_before_commit', v_removed)
   where scenario_id = v_id;

  return jsonb_build_object('ok', true, 'scenario_id', v_id, 'created', v_created,
                            'removed_before_commit', v_removed);
end $function$;

revoke all on function public.fn_phase_d_committed_scenario_open(jsonb) from public;

-- ================================================================================================
create or replace function public.fn_phase_d_committed_scenario_close(p_scenario_id bigint)
returns jsonb
language plpgsql
set search_path to 'public','pg_temp'
as $function$
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

revoke all on function public.fn_phase_d_committed_scenario_close(bigint) from public;

-- =================================================================================================
-- Phase D — D9d. A canonical object write that emails a supplier, and an object that cannot reach
-- the state its own dispatch requires.
--
-- BOTH FOUND BY EXECUTION, running the D9c scenario factory once. Stage 140 came back:
--
--   pd_object_write_produced_nothing — the write to public.inquiry_matches returned no key
--
-- `fn_phase_d_object_write` is right to refuse: the statement "succeeded" and inserted no row. Two
-- BEFORE INSERT triggers sit on that table and pulling on the thread found two separate defects.
--
-- DEFECT 1 — AN OBJECT THAT CANNOT REACH THE STATE ITS OWN DISPATCH REQUIRES.
-- `trg_gate_incomplete_match` returns NULL — silently, by its own comment — unless
-- `public.inquiries.rfq_ready` is true. The D2 write map for `inquiry` maps id, spec, status,
-- summary, category and customer_id, and NOT `rfq_ready`. So no canonical Phase D path could ever
-- produce an inquiry that a supplier assignment is permitted to reference, and W12 could never be
-- driven. This is the same shape as `supplier_account` being unable to write `verified` and so
-- unable to reach its own `approved` state, repaired in D9c. Both were invisible until a write ran.
--
-- DEFECT 2 — A CANONICAL WRITE THAT PRODUCES AN OUTBOUND NOTIFICATION.
-- `notify_matched_supplier` is an AFTER INSERT trigger on the same table and it does this:
--
--     insert into notifications(type,to_email,...,status) values('new_inquiry', v_email, ... ,'queued')
--
-- for any supplier whose `email` contains '@'. So writing the `supplier_assignment` business object
-- through the canonical service queues an outbound email. The D7 board check
-- `phase_d_write_maps_into_the_outbound_notification_table` reads the WRITE MAPS and is green — it
-- was never going to see this, because the row is written by a trigger underneath the map. A green
-- number measuring something other than what it names is the recurring shape in this estate, and
-- this is another instance: the board's name says "Phase D does not write the outbound table" and
-- what it measures is "no Phase D write map targets it".
--
-- WHAT IS DONE ABOUT IT HERE:
--   * The write map for `inquiry` gains `rfq_ready`, so the object can reach its own state.
--   * The factory now COUNTS public.notifications and public.kernel_trigger_inbox before and after
--     every stage and aborts the whole scenario with pd_fixture_external_effect_produced if either
--     moves. That is an executable guarantee, not a claim in a document.
--   * The fixture supplier is created with NO email. That is not a trick to dodge the trigger: 569
--     of the 20,465 real supplier rows have no email, so it is an ordinary business state, and the
--     assertion above is what actually enforces the zero.
--   * A new board check measures the exposure BY EXECUTION rather than by reading the map.
--
-- WHAT IS DELIBERATELY NOT DONE: the trigger is not disabled, altered or dropped. It is live
-- product behaviour outside Phase D's scope to change, the outbound senders are held, and a Phase D
-- increment that quietly removed a notification path would be changing behaviour to make a check
-- green — the exact thing this phase exists to remove.
-- =================================================================================================

begin;

-- ---- 1. the inquiry object can reach the state dispatch requires --------------------------------

update public.phase_d_object_write_map
   set column_map = column_map || jsonb_build_object('rfq_ready','rfq_ready')
 where object_id = 'inquiry'
   and not (column_map ? 'rfq_ready');

-- ---- 2. the factory proves zero external effect, per stage --------------------------------------

create or replace function public.fn_phase_d_fixture_scenario(p_input jsonb)
returns jsonb
language plpgsql
set search_path to 'public', 'pg_temp'
as $fn$
declare
  st       public.phase_d_fixture_stage%rowtype;
  v_label  text := nullif(btrim(coalesce(p_input->>'label','')),'');
  v_ctx    text := lower(coalesce(nullif(btrim(p_input->>'execution_context'),''),''));
  v_upto   int  := coalesce(nullif(p_input->>'up_to_stage','')::int, 9999);
  v_actor  text := coalesce(nullif(btrim(p_input->>'created_by'),''), 'phase_d_fixture_factory');
  v_refs   jsonb := '{}'::jsonb;
  v_man    jsonb := '[]'::jsonb;
  v_w      jsonb;
  v_pay    jsonb;
  v_key    text;
  v_owner  text;
  v_state  text;
  v_email  text;
  v_name   text;
  v_missing text[];
  v_ref_n  bigint;
  v_err    text;
  v_ok     int := 0; v_blocked int := 0;
  v_notif_before bigint; v_notif_after bigint;
  v_inbox_before bigint; v_inbox_after bigint;
  v_notif_start  bigint; v_inbox_start  bigint;
begin
  if v_label is null then
    raise exception 'fn_phase_d_fixture_scenario: label is required; it is what makes the ids deterministic and the residue findable (pd_fixture_label_missing)'
      using errcode = '22023';
  end if;
  if v_ctx <> 'test' then
    raise exception 'fn_phase_d_fixture_scenario: execution_context is %; this factory runs only in test (pd_fixture_not_test_context)',
      coalesce(nullif(v_ctx,''),'(unset)') using errcode = '23514';
  end if;
  if coalesce(nullif(btrim(current_setting('app.phase_d_test_context', true)),''),'') <> 'on' then
    raise exception 'fn_phase_d_fixture_scenario: app.phase_d_test_context is not set to on in this transaction (pd_fixture_no_test_context)'
      using errcode = '23514',
            hint = 'set local app.phase_d_test_context = ''on''; and abort the transaction when finished.';
  end if;
  if current_user in ('anon','authenticated') then
    raise exception 'fn_phase_d_fixture_scenario: % may not build fixtures (pd_fixture_untrusted_caller)',
      current_user using errcode = '42501';
  end if;

  select count(*) into v_notif_start from public.notifications;
  select count(*) into v_inbox_start from public.kernel_trigger_inbox;

  for st in select * from public.phase_d_fixture_stage where stage_no <= v_upto order by stage_no
  loop
    select array_agg(r) into v_missing
      from unnest(st.requires_stages) r
     where not exists (select 1 from jsonb_array_elements(v_man) m
                        where m->>'stage_key' = r and m->>'status' = 'CREATED');
    if v_missing is not null then
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status', 'SKIPPED_PARENT_NOT_CREATED', 'detail', array_to_string(v_missing, ', ')));
      v_blocked := v_blocked + 1;
      continue;
    end if;

    if st.reference_relation is not null then
      execute format('select count(*) from %s', st.reference_relation) into v_ref_n;
      if v_ref_n = 0 then
        v_man := v_man || jsonb_build_array(jsonb_build_object(
          'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
          'status', 'BLOCKED_NO_REFERENCE_DATA', 'detail',
          format('%s holds 0 rows and this factory does not create business reference data',
                 st.reference_relation)));
        v_blocked := v_blocked + 1;
        continue;
      end if;
    end if;

    v_email := format('zz-phase-d-%s-%s@example.invalid', v_label, st.stage_key);
    v_name  := format('ZZ DEMO — %s %s', v_label, st.stage_key);
    v_key   := md5(format('%s:%s', v_label, st.stage_key))::uuid::text;
    v_owner := v_key;
    v_state := 'open';
    v_pay   := jsonb_build_object('fixture_label', v_label, 'stage', st.stage_key,
                                  'phase_d_test_context', true);

    if st.stage_key = 'customer_account' then
      v_state := 'active';
      v_pay := v_pay || jsonb_build_object('email', v_email, 'full_name', v_name,
                                           'phone', '+971500000000', 'locale', 'en');

    elsif st.stage_key = 'customer_terms_acceptance' then
      v_owner := v_refs->>'customer_id'; v_state := 'accepted';
      v_pay := v_pay || jsonb_build_object(
        'terms_version', 'zz-terms-v1',
        'terms_hash', encode(sha256(convert_to('zz-terms-v1','UTF8')),'hex'),
        'accepted_by', v_refs->>'customer_id');

    elsif st.stage_key = 'inquiry' then
      -- rfq_ready is what trg_gate_incomplete_match reads before it will allow a supplier
      -- assignment to reference this inquiry. Without it the assignment row is dropped silently.
      v_owner := v_refs->>'customer_id'; v_state := 'quote_ready';
      v_pay := v_pay || jsonb_build_object('summary', v_name, 'spec', 'ZZ DEMO — fixture specification',
                                           'category', 'general', 'rfq_ready', true);

    elsif st.stage_key = 'inquiry_answer' then
      v_owner := v_refs->>'inquiry_id'; v_state := 'recorded';
      v_pay := v_pay || jsonb_build_object(
        'answer_scope','inquiry_shared', 'source_kind','customer', 'precedence', 1,
        'value', to_jsonb('ZZ DEMO — fixture answer'::text),
        'field_id', (select id from public.field_definition order by id limit 1),
        'group_id', (select id from public.inquiry_workstream_group order by id limit 1));

    elsif st.stage_key = 'inquiry_version' then
      v_owner := v_refs->>'inquiry_id'; v_state := 'frozen';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id', 'version', 1);

    elsif st.stage_key = 'inquiry_route_set' then
      v_owner := v_refs->>'inquiry_id'; v_state := 'confirmed';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'route_state','confirmed', 'routes', '["general"]'::jsonb,
                                           'evidence','ZZ DEMO — fixture route evidence');

    elsif st.stage_key = 'inquiry_document' then
      v_owner := v_refs->>'inquiry_id'; v_state := 'validated';
      v_pay := v_pay || jsonb_build_object('kind','boq', 'mime','application/pdf',
                                           'bucket','zz-phase-d-fixtures',
                                           'path', format('zz/%s/%s.pdf', v_label, st.stage_key),
                                           'file_name', format('zz-%s.pdf', v_label));

    elsif st.stage_key = 'document_extraction' then
      v_owner := v_refs->>'document_id'; v_state := 'extracted';
      v_pay := v_pay || jsonb_build_object('document_id', v_refs->>'document_id',
                                           'method','deterministic', 'paid_model_used', false);

    elsif st.stage_key = 'supplier_safe_package' then
      v_owner := v_refs->>'inquiry_id'; v_state := 'approved';
      v_pay := v_pay || jsonb_build_object(
        'inquiry_id', v_refs->>'inquiry_id',
        'safe_package_ref', v_key,
        'safe_package_approved_by', 'compliance_and_privacy_officer',
        'contents','ZZ DEMO — scope and quantities only; no customer identity');

    elsif st.stage_key = 'supplier_account' then
      -- NO EMAIL, AND THE REASON IS DEFECT 2 AT THE TOP OF THIS FILE. notify_matched_supplier fires
      -- on the supplier_assignment insert and queues an outbound email for any supplier whose
      -- address contains '@'. 569 of the 20,465 real supplier rows carry no email, so this is an
      -- ordinary business state rather than a contrivance — and the notifications assertion below
      -- is what actually enforces the zero, not this choice.
      v_state := 'approved';
      v_pay := v_pay || jsonb_build_object('company_name', v_name, 'verified', true);

    elsif st.stage_key = 'supplier_terms_acceptance' then
      v_owner := v_refs->>'supplier_id'; v_state := 'accepted';
      v_pay := v_pay || jsonb_build_object('terms_version','zz-supplier-terms-v1',
        'terms_hash', encode(sha256(convert_to('zz-supplier-terms-v1','UTF8')),'hex'),
        'supplier_id', v_refs->>'supplier_id');

    elsif st.stage_key = 'supplier_capability' then
      v_owner := v_refs->>'supplier_id'; v_state := 'approved';
      v_pay := v_pay || jsonb_build_object('trades', '["general"]'::jsonb);

    elsif st.stage_key = 'supplier_verification_case' then
      v_owner := v_refs->>'supplier_id'; v_state := 'verified';
      v_pay := v_pay || jsonb_build_object('supplier_id', v_refs->>'supplier_id',
                                           'evidence','ZZ DEMO — fixture verification evidence',
                                           'verified_by','supplier_verification');

    elsif st.stage_key = 'supplier_assignment' then
      v_owner := v_refs->>'supplier_id'; v_state := 'dispatched';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'similarity', 0.9,
                                           'match_reason','ZZ DEMO — fixture assignment');

    elsif st.stage_key = 'quotation' then
      v_owner := v_refs->>'supplier_id'; v_state := 'submitted';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id', 'quote_amount', 1000);

    elsif st.stage_key = 'quotation_revision' then
      v_owner := v_refs->>'supplier_id'; v_state := 'submitted';
      v_pay := v_pay || jsonb_build_object('quote_id', v_refs->>'quote_id',
                                           'quote_revision_ref', v_key, 'platform_edited', false);

    elsif st.stage_key = 'quotation_comparison' then
      v_owner := v_refs->>'customer_id'; v_state := 'published';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'analysis', jsonb_build_object('note','ZZ DEMO — fixture comparison'),
                                           'quote_count', 1,
                                           'signature', encode(sha256(convert_to(v_key,'UTF8')),'hex'));

    elsif st.stage_key = 'customer_selection' then
      v_owner := v_refs->>'customer_id'; v_state := 'selected';
      v_pay := v_pay || jsonb_build_object('comparison_id', v_refs->>'comparison_id',
                                           'selected_quote_id', v_refs->>'quote_id');

    elsif st.stage_key = 'payment_transaction' then
      v_owner := v_refs->>'customer_id'; v_state := 'payment_reconciled';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'quote_id', v_refs->>'quote_id',
                                           'quote_amount', 1000, 'reveal_fee', 100,
                                           'payment_ref', format('zz-pay-%s', v_label));

    elsif st.stage_key = 'provider_event' then
      v_owner := v_refs->>'transaction_id'; v_state := 'succeeded';
      v_key := format('evt_zz_%s', v_label);
      v_pay := v_pay || jsonb_build_object('event_type','checkout.session.completed');

    elsif st.stage_key = 'reconciliation_case' then
      v_owner := v_refs->>'transaction_id'; v_state := 'reconciled';
      v_pay := v_pay || jsonb_build_object('transaction_id', v_refs->>'transaction_id',
                                           'monetary_state','reconciled');

    elsif st.stage_key = 'reveal_transaction' then
      v_key := v_refs->>'transaction_id';
      v_owner := v_refs->>'customer_id'; v_state := 'reveal_authorized';
      v_pay := v_pay || jsonb_build_object('reveal_fee', 100,
                                           'payment_ref', format('zz-pay-%s', v_label),
                                           'revealed_at', now(),
                                           'supplier_id', (v_refs->>'supplier_id')::bigint);

    elsif st.stage_key = 'refund_dispute_case' then
      v_owner := v_refs->>'customer_id'; v_state := 'requested';
      v_pay := v_pay || jsonb_build_object('transaction_id', v_refs->>'transaction_id',
                                           'amount_fils', 10000, 'reason_code','other',
                                           'reason_note','ZZ DEMO — fixture refund case; no refund is executed',
                                           'requested_by', v_refs->>'customer_id');

    elsif st.stage_key = 'review_record' then
      v_state := 'approved';
      v_pay := v_pay || jsonb_build_object('verdict','approved',
                                           'subject_type','phase_d_fixture', 'subject_id', v_label,
                                           'author_agent','customer_onboarding',
                                           'reviewer_role_id','customer_success_director',
                                           'stage', st.stage_key, 'notes','ZZ DEMO — fixture review');
    end if;

    -- ---- ZERO EXTERNAL EFFECT, ASSERTED PER STAGE ------------------------------------------------
    -- Counted around EVERY stage, because the row that would be produced is written by a trigger
    -- underneath the object service and nothing in the write map mentions it. A board that read the
    -- map would stay green while a supplier was queued an email.
    select count(*) into v_notif_before from public.notifications;
    select count(*) into v_inbox_before from public.kernel_trigger_inbox;

    begin
      v_w := public.fn_phase_d_object_write(jsonb_build_object(
        'object_id', st.object_id, 'business_key', v_key, 'owner_ref', v_owner,
        'created_by', v_actor, 'state', v_state, 'payload', v_pay));

      select count(*) into v_notif_after from public.notifications;
      if v_notif_after <> v_notif_before then
        raise exception 'fn_phase_d_fixture_scenario: stage % wrote % row(s) into public.notifications. A fixture may not queue an outbound message. (pd_fixture_external_effect_produced)',
          st.stage_key, v_notif_after - v_notif_before using errcode = '23514';
      end if;

      if st.contributes_ref is not null then
        v_refs := v_refs || jsonb_build_object(st.contributes_ref,
          case when st.stage_key = 'inquiry_route_set' then 'confirmed'
               else split_part(v_w->>'result_reference', '=', 2) end);
      end if;

      select count(*) into v_inbox_after from public.kernel_trigger_inbox;
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status','CREATED', 'relation', v_w->>'canonical_relation',
        'result_reference', v_w->>'result_reference', 'state', v_w->>'state',
        'policy_family', v_w->>'policy_family',
        'notifications_written', v_notif_after - v_notif_before,
        'kernel_trigger_rows_written', v_inbox_after - v_inbox_before,
        'contributes', st.contributes_ref));
      v_ok := v_ok + 1;

    exception when others then
      v_err := SQLERRM;
      -- An external-effect breach is not a stage outcome to record and carry on from. It aborts.
      if position('pd_fixture_external_effect_produced' in v_err) > 0 then raise; end if;
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status','REFUSED',
        'refused_with', coalesce((regexp_match(v_err,'\((pd_[a-z0-9_]+)\)'))[1],'(none)'),
        'reason', left(v_err, 300)));
      v_blocked := v_blocked + 1;
    end;
  end loop;

  select count(*) into v_notif_after from public.notifications;
  select count(*) into v_inbox_after from public.kernel_trigger_inbox;

  return jsonb_build_object(
    'ok', v_blocked = 0, 'label', v_label,
    'stages_created', v_ok, 'stages_not_created', v_blocked,
    'stages_declared', (select count(*) from public.phase_d_fixture_stage where stage_no <= v_upto),
    'parent_refs', v_refs,
    'manifest', v_man,
    'notifications_written_by_this_scenario', v_notif_after - v_notif_start,
    'kernel_trigger_rows_written_by_this_scenario', v_inbox_after - v_inbox_start,
    'external_effects', 0, 'paid_calls', 0,
    'note', 'every row here was written through fn_phase_d_object_write; abort the transaction to leave nothing behind');
end $fn$;

-- ---- 3. the board measures the exposure by execution, not by reading the map ---------------------

-- ROUTINE REMOVED 7 September 2026. public.fn_phase_d_outbound_exposure was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ROUTINE REMOVED 7 September 2026. public.fn_phase_d_fixture_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke all on function public.fn_phase_d_outbound_exposure() from public;
grant execute on function public.fn_phase_d_outbound_exposure() to service_role;

-- ---- 4. positive controls, on this deployment ------------------------------------------------------

do $ctl$
declare v_n int; v_err text; v_fired boolean := false;
begin
  select count(*) into v_n from public.fn_phase_d_outbound_exposure();
  if v_n = 0 then
    raise exception 'D9d positive control FAILED: the exposure detector finds nothing, and notify_matched_supplier on public.inquiry_matches is live. A detector that reports zero on a known instance is worse than none.';
  end if;

  if not (select column_map ? 'rfq_ready' from public.phase_d_object_write_map where object_id='inquiry') then
    raise exception 'D9d: the inquiry write map still cannot write rfq_ready';
  end if;

  -- the test-context guard still fires after this replacement
  begin
    perform public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','deploy-control-d9d','execution_context','test'));
  exception when others then
    v_err := SQLERRM; v_fired := true;
  end;
  if not v_fired or position('pd_fixture_no_test_context' in v_err) = 0 then
    raise exception 'D9d positive control FAILED: the test-context guard did not fire (%)',
      left(coalesce(v_err,'(no error)'),200);
  end if;

  raise notice 'D9d positive controls: exposure detector finds % relation(s); rfq_ready writable; test-context guard fires.', v_n;
end $ctl$;

commit;

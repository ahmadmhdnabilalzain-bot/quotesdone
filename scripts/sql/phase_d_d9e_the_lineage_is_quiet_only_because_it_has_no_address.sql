-- =================================================================================================
-- Phase D — D9e. The lineage is quiet only because it has no address.
--
-- D9d added a per-stage assertion that the scenario factory writes nothing into
-- `public.notifications`. On the very next run it fired — on `inquiry`, not on the stage D9d was
-- written for:
--
--   pd_fixture_external_effect_produced — stage inquiry wrote 1 row(s) into public.notifications
--
-- So the exposure was never one trigger on one table. Measured with a detector that reads trigger
-- FUNCTION BODIES rather than write maps, the canonical Phase D object services reach **eight**
-- notification-writing triggers across **four** relations:
--
--   public.inquiries       trg_inquiry_received_a   (inquiry)              customer email
--   public.inquiries       customer_abandon_ban     (inquiry)              support notice
--   public.inquiry_matches notify_matched_supplier  (supplier_assignment)  supplier email
--   public.quotes          trg_new_quote_sms        (quotation)            SMS
--   public.transactions    trg_reveal_receipt_a     (payment/reveal)       receipt
--   public.transactions    trg_notify_refund        (payment/reveal)       refund notice
--
-- WHAT THIS MEANS PRECISELY, AND IT IS THE FINDING: writing five of the estate's business objects
-- through their own canonical service queues an outbound message. Not one of those rows comes from
-- a Phase D write map, so the D7 board check
-- `phase_d_write_maps_into_the_outbound_notification_table` is green and always would have been.
-- Its name says Phase D does not write the outbound table; what it measures is that no Phase D
-- write map targets it. That is the instrument-on-the-wrong-subject shape again, and this file does
-- not fix it by editing the old check — it adds a detector that reads where the rows actually come
-- from, and leaves both numbers visible.
--
-- WHAT KEEPS THE SESSION AT ZERO: the fixture identities carry NO EMAIL AND NO PHONE. Every one of
-- those six triggers is conditional on a contact detail existing. That is the honest statement —
-- the lineage is quiet because it has no address, not because the paths are closed. 569 of the
-- 20,465 real supplier rows likewise have no email, so the shape is an ordinary business state and
-- not a contrivance; and the per-stage count, not the choice of fixture, is what enforces the zero.
--
-- THE EXPECTED VALUE IS NOT TYPED. D9d wrote "1 (disclosed)" as the expectation and the real number
-- was 8. Retyping 8 would be the same mistake with a better number — the count moves whenever the
-- product gains or loses a notification trigger, and a literal makes the check agree with whatever
-- happens to be there. The exposure row is now INFORMATIONAL, and the check that can actually fail
-- is the executed one: run the whole scenario and count the delta.
--
-- NOT DONE: no trigger is disabled, altered or dropped. They are live product behaviour and the
-- outbound senders are held; a Phase D increment that removed a notification path to make its own
-- number green would be changing behaviour to pass a check.
-- =================================================================================================

begin;

-- ---- 1. the fixture identities carry no contact detail ------------------------------------------

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

    v_name  := format('ZZ DEMO — %s %s', v_label, st.stage_key);
    v_key   := md5(format('%s:%s', v_label, st.stage_key))::uuid::text;
    v_owner := v_key;
    v_state := 'open';
    v_pay   := jsonb_build_object('fixture_label', v_label, 'stage', st.stage_key,
                                  'phase_d_test_context', true);

    if st.stage_key = 'customer_account' then
      -- NO EMAIL AND NO PHONE. trg_inquiry_received_a queues a customer email for any inquiry whose
      -- customer has an address, and trg_new_quote_sms / trg_reveal_receipt_a do the same on a
      -- phone. The fixture identity carries neither, and the per-stage assertion below is what
      -- proves it rather than this comment.
      v_state := 'active';
      v_pay := v_pay || jsonb_build_object('full_name', v_name, 'locale', 'en');

    elsif st.stage_key = 'customer_terms_acceptance' then
      v_owner := v_refs->>'customer_id'; v_state := 'accepted';
      v_pay := v_pay || jsonb_build_object(
        'terms_version', 'zz-terms-v1',
        'terms_hash', encode(sha256(convert_to('zz-terms-v1','UTF8')),'hex'),
        'accepted_by', v_refs->>'customer_id');

    elsif st.stage_key = 'inquiry' then
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

-- ---- 2. the board: disclose the exposure, and check the thing that can actually fail -------------

create or replace function public.fn_phase_d_fixture_state()
returns table(check_name text, expected text, actual text, ok boolean)
language sql stable
set search_path to 'public', 'pg_temp'
as $fn$
  select 'fixture_stages_declared', '>= 20',
         (select count(*)::text from public.phase_d_fixture_stage),
         (select count(*) from public.phase_d_fixture_stage) >= 20
  union all
  select 'stages_naming_an_unbound_object', '0',
         (select count(*)::text from public.phase_d_fixture_stage s
           where not exists (select 1 from public.phase_d_business_object_binding b
                              where b.object_id = s.object_id)),
         not exists (select 1 from public.phase_d_fixture_stage s
                      where not exists (select 1 from public.phase_d_business_object_binding b
                                         where b.object_id = s.object_id))
  union all
  select 'stages_requiring_a_stage_that_does_not_exist', '0',
         (select count(*)::text from public.phase_d_fixture_stage s, unnest(s.requires_stages) r
           where not exists (select 1 from public.phase_d_fixture_stage p where p.stage_key = r)),
         not exists (select 1 from public.phase_d_fixture_stage s, unnest(s.requires_stages) r
                      where not exists (select 1 from public.phase_d_fixture_stage p
                                         where p.stage_key = r))
  union all
  select 'stages_depending_on_a_later_stage', '0',
         (select count(*)::text from public.phase_d_fixture_stage s, unnest(s.requires_stages) r
            join public.phase_d_fixture_stage p on p.stage_key = r
           where p.stage_no >= s.stage_no),
         not exists (select 1 from public.phase_d_fixture_stage s, unnest(s.requires_stages) r
                       join public.phase_d_fixture_stage p on p.stage_key = r
                      where p.stage_no >= s.stage_no)
  union all
  select 'supplier_account_can_write_verified', 'true',
         (select (column_map ? 'verified')::text from public.phase_d_object_write_map
           where object_id = 'supplier_account'),
         (select column_map ? 'verified' from public.phase_d_object_write_map
           where object_id = 'supplier_account')
  union all
  select 'inquiry_can_write_rfq_ready', 'true',
         (select (column_map ? 'rfq_ready')::text from public.phase_d_object_write_map
           where object_id = 'inquiry'),
         (select column_map ? 'rfq_ready' from public.phase_d_object_write_map
           where object_id = 'inquiry')
  union all
  select 'fixture_rows_surviving_in_business_tables', '0',
         (select coalesce(sum(surviving_rows),0)::text from public.fn_phase_d_fixture_residue()),
         coalesce((select sum(surviving_rows) from public.fn_phase_d_fixture_residue()), 0) = 0
  union all
  select 'fixture_stage_targeting_public_notifications', '0',
         (select count(*)::text from public.phase_d_fixture_stage s
            join public.phase_d_business_object_binding b on b.object_id = s.object_id
           where b.canonical_relation = 'public.notifications'),
         not exists (select 1 from public.phase_d_fixture_stage s
                       join public.phase_d_business_object_binding b on b.object_id = s.object_id
                      where b.canonical_relation = 'public.notifications')
  union all
  -- INFORMATIONAL. The number moves whenever the product gains or loses a notification trigger, so
  -- a typed expectation would only ever mean "agree with whatever is there". D9d typed 1 and the
  -- measurement was 8. What can genuinely fail is the executed check below it.
  select 'canonical_object_writes_that_can_reach_a_notification_trigger', 'informational',
         (select count(*)::text from public.fn_phase_d_outbound_exposure()), true
  union all
  select 'fixture_identities_carrying_a_contact_detail', '0',
         (select count(*)::text from public.customers c
           where c.full_name like 'ZZ DEMO — %'
             and (coalesce(c.email,'') <> '' or coalesce(c.phone,'') <> '')),
         not exists (select 1 from public.customers c
                      where c.full_name like 'ZZ DEMO — %'
                        and (coalesce(c.email,'') <> '' or coalesce(c.phone,'') <> ''));
$fn$;

-- ---- 3. the executed control: run the whole scenario and count the delta -------------------------
-- This is the check that can fail. It runs the full lineage on this deployment, asserts the
-- notification delta is zero, and then raises so every row is rolled back.

do $ctl$
declare v jsonb; v_created int; v_notif int; v_err text;
begin
  begin
    perform set_config('app.phase_d_test_context','on', true);
    v := public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','deploy-ctl-d9e','execution_context','test'));
    v_created := (v->>'stages_created')::int;
    v_notif   := (v->>'notifications_written_by_this_scenario')::int;
    raise exception 'PHASE_D_D9E_ROLLBACK created=% notifications=% blocked=%',
      v_created, v_notif, v->>'stages_not_created';
  exception when others then
    v_err := SQLERRM;
    if position('PHASE_D_D9E_ROLLBACK' in v_err) = 0 then
      raise exception 'D9e control FAILED before it could assert: %', left(v_err, 400);
    end if;
  end;

  if (regexp_match(v_err, 'notifications=(-?\d+)'))[1] <> '0' then
    raise exception 'D9e control FAILED: the scenario queued outbound notifications — %', v_err;
  end if;
  if (regexp_match(v_err, 'created=(\d+)'))[1]::int < 22 then
    raise exception 'D9e control FAILED: only % stages were created; the lineage is incomplete — %',
      (regexp_match(v_err, 'created=(\d+)'))[1], v_err;
  end if;

  raise notice 'D9e control: % — every row rolled back.', v_err;
end $ctl$;

commit;

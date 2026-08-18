-- =================================================================================================
-- Phase D — D9f. The inquiry writer covers two of the six fields its own readiness scorer reads.
--
-- D9d added `rfq_ready` to the `inquiry` write map so a supplier assignment could reference a
-- ready inquiry. It did not work, and the reason is worth writing down because the first repair was
-- the wrong one:
--
--   `trg_rfq_complete` is a BEFORE trigger on public.inquiries and it does
--       NEW.rfq_ready := (public.fn_rfq_score(NEW)->>'ready')::boolean;
--   so `rfq_ready` is a DERIVED column. Whatever a caller supplies is overwritten before the row
--   lands. Mapping it was mapping a column that cannot be written, which is worse than not mapping
--   it: the board would have gone green on a repair that changes nothing.
--
-- WHAT THE SCORER ACTUALLY READS, measured from `fn_rfq_score`, out of 100 with 70 to pass:
--
--     category            20     mapped
--     emirate             10     NOT mapped
--     scope_detail        25     mapped (spec, > 20 alphanumeric characters)
--     scope_type          15     NOT mapped
--     budget              15     NOT mapped
--     supporting_detail   15     NOT mapped (trades / drawing_file_path / boq)
--
-- The canonical `inquiry` writer could reach **45 of 100**, and 70 is the bar. So no Phase D path
-- could produce a quote-ready inquiry, therefore none could produce a supplier assignment — the
-- assignment row was being dropped silently by `trg_gate_incomplete_match`, whose own comment says
-- "silently skip" and which returns NULL rather than raising. Therefore W12 could not be driven,
-- and neither could anything downstream of a dispatch.
--
-- THE OBJECT'S READINESS IS THE PRODUCT'S OWN JUDGEMENT, NOT A FLAG THIS PHASE SETS. The repair is
-- to let the writer supply the FACTS the scorer measures and leave the verdict to `fn_rfq_score`.
-- Forcing `rfq_ready` — even if the trigger allowed it — would be asserting a readiness nobody
-- measured, on the row that BR-013 then reads back as evidence.
--
-- AND THE GENERIC SCORE IS NOT THE WHOLE BAR — measured by execution, after the first attempt:
--
--     rfq score = 100   ready = false
--
-- `fn_rfq_score` returns `ready = (generic_ready AND category_required_ok)`. A perfect 100 on the
-- generic six still fails when `fn_rfq_required_check` finds an unanswered required field, and
-- `public.category_specs` does carry a row for `general` with three required keys — `describe`,
-- `property`, `scope`. The first fixture answered one of the three. A score of 100 beside
-- ready=false is exactly the "instrument reporting on the wrong subject" reflex: the number that
-- looks like the verdict is not the verdict, and only reading both told them apart.
--
-- The fixture spec now answers all three, and the readiness verdict remains entirely the product's.
-- =================================================================================================

begin;

-- rfq_ready is derived. Remove it: a mapped column that a BEFORE trigger overwrites is a promise
-- the map cannot keep.
update public.phase_d_object_write_map
   set column_map = column_map - 'rfq_ready'
 where object_id = 'inquiry' and (column_map ? 'rfq_ready');

-- The four facts the scorer reads and the writer could not supply.
update public.phase_d_object_write_map
   set column_map = column_map
                    || jsonb_build_object('emirate','emirate')
                    || jsonb_build_object('scope_type','scope_type')
                    || jsonb_build_object('budget','budget')
                    || jsonb_build_object('trades','trades')
 where object_id = 'inquiry';

-- The map validator's rule, re-checked here rather than assumed: every mapped column must exist on
-- the target. A map that names a column the table does not have deploys and then fails at runtime.
do $chk$
declare v_missing text;
begin
  select string_agg(k.key, ', ') into v_missing
    from public.phase_d_object_write_map wm, jsonb_each(wm.column_map) k
   where wm.object_id = 'inquiry'
     and not exists (select 1 from pg_attribute a
                      where a.attrelid = wm.target_relation::regclass
                        and a.attname = k.key and a.attnum > 0 and not a.attisdropped);
  if v_missing is not null then
    raise exception 'D9f: the inquiry write map names column(s) public.inquiries does not have: %', v_missing;
  end if;
end $chk$;

-- ---- the fixture supplies those facts ------------------------------------------------------------
-- Only the `inquiry` stage changes. Everything else in the factory is untouched, so this file is a
-- payload correction and not a second copy of the routine.

create or replace function public.fn_phase_d_fixture_inquiry_payload(p_label text)
returns jsonb
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  -- The generic six, and the three keys public.category_specs marks required for `general`
  -- (describe, property, scope) — read from the table, not guessed. The verdict is still
  -- fn_rfq_score's; this supplies facts, not a readiness flag.
  select jsonb_build_object(
    'summary',   format('ZZ DEMO — %s inquiry', p_label),
    'spec',      jsonb_build_object(
                   'describe','ZZ DEMO fixture requirement described in full: supply and installation of a general works package to the stated scope and quantities.',
                   'property','Commercial fit-out, Dubai',
                   'scope','ZZ DEMO fixture scope of works with sufficient descriptive detail for the readiness scorer to register scope_detail',
                   'quantity','1 lot'),
    'category',  'general',
    'emirate',   'Dubai',
    'scope_type','supply_and_install',
    'budget',    'AED 100,000 - 200,000',
    'trades',    '["general"]'::jsonb);
$fn$;

revoke all on function public.fn_phase_d_fixture_inquiry_payload(text) from public;
grant execute on function public.fn_phase_d_fixture_inquiry_payload(text) to service_role;

-- ---- the scenario uses the payload helper for its inquiry stage ---------------------------------
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
      -- The FACTS fn_rfq_score reads, never a readiness flag. rfq_ready is derived by
      -- trg_rfq_complete and the verdict stays the product's own.
      v_owner := v_refs->>'customer_id'; v_state := 'quote_ready';
      v_pay := v_pay || public.fn_phase_d_fixture_inquiry_payload(v_label);

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

commit;

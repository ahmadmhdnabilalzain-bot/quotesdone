-- =================================================================================================
-- Phase D — D9c. The fixture factory: a scenario built in the order reality builds it.
--
-- WHY THIS EXISTS. Six of the eight workflows driven in D8 stopped for want of a parent, not for a
-- defect: `public.customers`, `public.inquiries`, `public.quotes`, `public.transactions`,
-- `public.inquiry_matches`, `public.quote_comparisons` and `public.refunds` all hold ZERO rows since
-- the 16 August purge. GATE-011, GATE-014, GATE-017, GATE-018, GATE-019, GATE-020, BR-013, BR-015,
-- BR-016, BR-019, BR-020 and BR-032 all read real business data and correctly refuse against nothing.
--
-- WHAT IS DELIBERATELY NOT DONE: inserting parent rows directly. `insert into public.customers …`
-- would produce a row no business path can produce, and a workflow driven over it proves that the
-- workflow works on data the product cannot create. Every stage below goes through
-- `fn_phase_d_object_write` — the same canonical object service the handlers use — so a stage that
-- the product could not perform fails here too.
--
-- THE ORDER IS THE FOREIGN-KEY ORDER, MEASURED FROM pg_constraint, NOT ASSUMED:
--   customers -> inquiries -> leads -> supplier_capabilities -> inquiry_matches -> quotes
--             -> transactions -> {refunds, reveal_invoices, quote_comparisons}
--
-- A STAGE WHOSE REFERENCE DATA DOES NOT EXIST IS REPORTED, NOT FAKED. `inquiry_answer` requires
-- `group_id` into `public.inquiry_workstream_group`, which holds 0 rows. That stage returns
-- BLOCKED_NO_REFERENCE_DATA. Creating a workstream group to satisfy it would be a fixture inventing
-- reference data the business owns, which is the same defect one layer down.
--
-- AN IDENTITY IS NEVER A FIXTURE. The factory creates no auth user, no role, no department and no
-- reviewer. Where a workflow needs a reviewer the frozen step does not name, the caller supplies one
-- and the FROZEN kernel decides whether it is independent.
--
-- CLEANUP. Every stage is designed to be run inside a transaction the caller aborts. Nothing here
-- deletes: `fn_phase_d_fixture_residue()` measures what survived AFTER the fact, by scanning the
-- write-map target relations for this repository's existing fixture convention — `ZZ DEMO — …` in a
-- name and `@example.invalid` in an email — because a ledger written in the same transaction rolls
-- back with the rows it describes and can therefore prove nothing about residue.
-- =================================================================================================

begin;

-- ---- 0. the repair the measurement found -------------------------------------------------------
-- `supplier_account` declares `approval_status` as its state column and `public.leads` carries
-- CHECK (approval_status <> 'approved' OR verified = true). The write map has no `verified` column,
-- so the object's own `approved` state was UNREACHABLE through its canonical writer — proved by
-- execution: "new row for relation leads violates check constraint leads_approved_implies_verified".
-- BR-015 requires approved AND verified, so no canonical path could ever satisfy it.
update public.phase_d_object_write_map
   set column_map = column_map || jsonb_build_object('verified','verified')
 where object_id = 'supplier_account'
   and not (column_map ? 'verified');

-- ---- 1. the stages, declared as data -----------------------------------------------------------

create table if not exists public.phase_d_fixture_stage (
  stage_no          int  primary key,
  stage_key         text not null unique,
  -- A foreign key, not a CHECK with a subquery: Postgres refuses the latter, and a stage naming an
  -- object nobody bound is the failure this is guarding against. Named explicitly, with the identity
  -- Postgres itself generates, so the canonical routine engine can attribute it — it can only derive
  -- an auto-generated name when `references` sits on the same source line as its column.
  object_id         text not null,
  constraint phase_d_fixture_stage_object_id_fkey
    foreign key (object_id) references public.phase_d_business_object_binding(object_id) on delete restrict,
  requires_stages   text[] not null default '{}',
  contributes_ref   text,
  reference_relation text,
  note              text not null
);

comment on table public.phase_d_fixture_stage is
  'Phase D: the scenario stages in foreign-key order, each naming the canonical object service that produces it and the parent_refs key it contributes.';

insert into public.phase_d_fixture_stage
  (stage_no, stage_key, object_id, requires_stages, contributes_ref, reference_relation, note)
values
  (10,'customer_account',           'customer_account',           '{}',                                    'customer_id', null,
      'W04 produces this. Every customer-scoped object downstream is a child of it.'),
  (20,'customer_terms_acceptance',  'customer_terms_acceptance',  '{customer_account}',                    null, null,
      'BR-025 needs the exact version AND hash; the store keeps the accepted pair.'),
  (30,'inquiry',                    'inquiry',                    '{customer_account}',                    'inquiry_id', null,
      'W05 produces this. State quote_ready is what BR-013 measures.'),
  (40,'inquiry_answer',             'inquiry_answer',             '{inquiry}',                             null, 'public.inquiry_workstream_group',
      'Requires a workstream group; public.inquiry_workstream_group holds 0 rows, so this reports BLOCKED_NO_REFERENCE_DATA rather than creating business reference data.'),
  (50,'inquiry_version',            'inquiry_version',            '{inquiry}',                             null, null,
      'W05-S08 immutable revision of the qualified inquiry.'),
  (60,'inquiry_route_set',          'inquiry_route_set',          '{inquiry}',                             'route_state', null,
      'W06. BR-014 accepts only a CONFIRMED route, so the fixture writes confirmed and the rule decides.'),
  (70,'inquiry_document',           'inquiry_document',           '{inquiry}',                             'document_id', null,
      'W07 validated document revision.'),
  (80,'document_extraction',        'document_extraction',        '{inquiry_document}',                    null, null,
      'W07 deterministic extraction; no paid model is called anywhere in this factory.'),
  (90,'supplier_safe_package',      'supplier_safe_package',      '{inquiry,inquiry_document}',            'safe_package_ref', null,
      'W08. BR-012 needs both the reference and an approver, and BR-011 scans the payload for customer identity.'),
  (100,'supplier_account',          'supplier_account',           '{}',                                    'supplier_id', null,
      'W09. approved implies verified is a CHECK on public.leads; the write map now carries verified so the state is reachable.'),
  (110,'supplier_terms_acceptance', 'supplier_terms_acceptance',  '{supplier_account}',                    null, null,
      'W09 append-only acceptance record.'),
  (120,'supplier_capability',       'supplier_capability',        '{supplier_account}',                    null, null,
      'W09/W10 versioned capability declaration.'),
  (130,'supplier_verification_case','supplier_verification_case', '{supplier_account}',                    null, null,
      'W10 independent verification case.'),
  (140,'supplier_assignment',       'supplier_assignment',        '{inquiry,supplier_account}',            'assignment_id', null,
      'W12. BR-016 counts assignments per (inquiry, supplier); inquiry_matches carries no unique constraint, which is recorded as a D2 REPAIR.'),
  (150,'quotation',                 'quotation',                  '{inquiry,supplier_account}',            'quote_id', null,
      'W14. quote_amount > 0 is a CHECK, so the fixture cannot write a free quote.'),
  (160,'quotation_revision',        'quotation_revision',         '{quotation}',                           'quote_revision_ref', null,
      'W14 immutable supplier-authored revision. BR-018 refuses a platform-edited one.'),
  (170,'quotation_comparison',      'quotation_comparison',       '{inquiry,customer_account,quotation}',  'comparison_id', null,
      'W15. BR-019 checks the comparison belongs to the calling customer.'),
  (180,'customer_selection',        'customer_selection',         '{quotation_comparison}',                null, null,
      'W15 append-only customer decision.'),
  (190,'payment_transaction',       'payment_transaction',        '{customer_account,inquiry,quotation}',  'transaction_id', null,
      'W16. The payment ladder starts here; BR-020 walks it.'),
  (200,'provider_event',            'provider_event',             '{payment_transaction}',                 'provider_event_id', null,
      'W16. BR-032 decides duplicate delivery from public.stripe_events.'),
  (210,'reconciliation_case',       'reconciliation_case',        '{payment_transaction}',                 null, null,
      'W16/W27 reconciliation case.'),
  (220,'reveal_transaction',        'reveal_transaction',         '{payment_transaction}',                 null, null,
      'W15 reveal. Moves the SAME transaction row; a second row would be two records for one payment.'),
  (230,'refund_dispute_case',       'refund_dispute_case',        '{payment_transaction,customer_account}','refund_id', null,
      'W17. Every refund needs the founder — the trigger enforces it and this factory executes none.'),
  (240,'review_record',             'review_record',              '{}',                                    null, null,
      'Internal review record; review_chain refuses reviewer = author.')
on conflict (stage_no) do update set
  object_id = excluded.object_id, requires_stages = excluded.requires_stages,
  contributes_ref = excluded.contributes_ref, reference_relation = excluded.reference_relation,
  note = excluded.note;

-- ---- 2. the factory ------------------------------------------------------------------------------

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
begin
  -- ---- GUARDS. All four, and none of them is a comment. -----------------------------------------
  if v_label is null then
    raise exception 'fn_phase_d_fixture_scenario: label is required; it is what makes the ids deterministic and the residue findable (pd_fixture_label_missing)'
      using errcode = '22023';
  end if;
  if v_ctx <> 'test' then
    raise exception 'fn_phase_d_fixture_scenario: execution_context is %; this factory runs only in test (pd_fixture_not_test_context)',
      coalesce(nullif(v_ctx,''),'(unset)') using errcode = '23514';
  end if;
  if coalesce(nullif(btrim(current_setting('app.phase_d_test_context', true)),''),'') <> 'on' then
    -- An explicit, per-transaction opt-in. A caller that has not said `set local
    -- app.phase_d_test_context = 'on'` has not declared a test context, and a factory that inferred
    -- one from its own argument would be answering its own question.
    raise exception 'fn_phase_d_fixture_scenario: app.phase_d_test_context is not set to on in this transaction (pd_fixture_no_test_context)'
      using errcode = '23514',
            hint = 'set local app.phase_d_test_context = ''on''; and abort the transaction when finished.';
  end if;
  if current_user in ('anon','authenticated') then
    raise exception 'fn_phase_d_fixture_scenario: % may not build fixtures (pd_fixture_untrusted_caller)',
      current_user using errcode = '42501';
  end if;

  -- Deterministic identities. md5 gives 32 hex characters, which casts straight to uuid, so the
  -- same label produces the same ids on every run and a replay is a replay rather than a new row.
  for st in select * from public.phase_d_fixture_stage where stage_no <= v_upto order by stage_no
  loop
    -- A stage whose prerequisites did not produce their reference is SKIPPED and says so.
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

    -- Reference data the business owns is looked up, never created.
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

    -- ---- the payload each object's own write map can use ---------------------------------------
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
      -- BR-013 measures readiness on this exact state vocabulary.
      v_owner := v_refs->>'customer_id'; v_state := 'quote_ready';
      v_pay := v_pay || jsonb_build_object('summary', v_name, 'spec', 'ZZ DEMO — fixture specification',
                                           'category', 'general');

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
                                           'method','deterministic',
                                           'paid_model_used', false);

    elsif st.stage_key = 'supplier_safe_package' then
      v_owner := v_refs->>'inquiry_id'; v_state := 'approved';
      -- The payload is scanned by BR-011 for customer identity. It deliberately carries none.
      v_pay := v_pay || jsonb_build_object(
        'inquiry_id', v_refs->>'inquiry_id',
        'safe_package_ref', v_key,
        'safe_package_approved_by', 'compliance_and_privacy_officer',
        'contents','ZZ DEMO — scope and quantities only; no customer identity');

    elsif st.stage_key = 'supplier_account' then
      -- leads.id is GENERATED ALWAYS, so the business key cannot be supplied; the returned key is
      -- what the rest of the lineage uses, which is why every stage reads v_refs and not v_key.
      v_state := 'approved';
      v_pay := v_pay || jsonb_build_object('email', v_email, 'company_name', v_name,
                                           'verified', true);

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
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'quote_amount', 1000);

    elsif st.stage_key = 'quotation_revision' then
      v_owner := v_refs->>'supplier_id'; v_state := 'submitted';
      v_pay := v_pay || jsonb_build_object('quote_id', v_refs->>'quote_id',
                                           'quote_revision_ref', v_key,
                                           'platform_edited', false);

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
      -- Rung 5 of the declared payment ladder plus a payment reference and a fee, which is the
      -- exact combination fn_phase_d_reveal_permitted requires and nothing less.
      v_owner := v_refs->>'customer_id'; v_state := 'payment_reconciled';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'quote_id', v_refs->>'quote_id',
                                           'quote_amount', 1000,
                                           'reveal_fee', 100,
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
      -- THE SAME ROW. reveal_transaction and payment_transaction are both bound to
      -- public.transactions; writing a second key here would be two transaction records for one
      -- payment, which the TRANSACTION_RECORD policy family exists to refuse.
      v_key := v_refs->>'transaction_id';
      v_owner := v_refs->>'customer_id'; v_state := 'reveal_authorized';
      v_pay := v_pay || jsonb_build_object('reveal_fee', 100,
                                           'payment_ref', format('zz-pay-%s', v_label),
                                           'revealed_at', now(),
                                           'supplier_id', (v_refs->>'supplier_id')::bigint);

    elsif st.stage_key = 'refund_dispute_case' then
      v_owner := v_refs->>'customer_id'; v_state := 'requested';
      v_pay := v_pay || jsonb_build_object('transaction_id', v_refs->>'transaction_id',
                                           'amount_fils', 10000,
                                           'reason_code','other',
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

    begin
      v_w := public.fn_phase_d_object_write(jsonb_build_object(
        'object_id', st.object_id, 'business_key', v_key, 'owner_ref', v_owner,
        'created_by', v_actor, 'state', v_state, 'payload', v_pay));

      -- The contributed reference is the key the WRITE returned, never the key that was offered.
      -- Seven of these relations generate their own identity, and a factory that recorded what it
      -- asked for rather than what it got would hand every downstream stage a dangling parent.
      if st.contributes_ref is not null then
        v_refs := v_refs || jsonb_build_object(st.contributes_ref,
          case when st.stage_key = 'inquiry_route_set' then 'confirmed'
               else split_part(v_w->>'result_reference', '=', 2) end);
      end if;

      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status','CREATED', 'relation', v_w->>'canonical_relation',
        'result_reference', v_w->>'result_reference', 'state', v_w->>'state',
        'policy_family', v_w->>'policy_family',
        'contributes', st.contributes_ref));
      v_ok := v_ok + 1;

    exception when others then
      v_err := SQLERRM;
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status','REFUSED',
        'refused_with', coalesce((regexp_match(v_err,'\((pd_[a-z0-9_]+)\)'))[1],'(none)'),
        'reason', left(v_err, 300)));
      v_blocked := v_blocked + 1;
    end;
  end loop;

  return jsonb_build_object(
    'ok', v_blocked = 0, 'label', v_label,
    'stages_created', v_ok, 'stages_not_created', v_blocked,
    'stages_declared', (select count(*) from public.phase_d_fixture_stage where stage_no <= v_upto),
    'parent_refs', v_refs,
    'manifest', v_man,
    'external_effects', 0, 'paid_calls', 0,
    'note', 'every row here was written through fn_phase_d_object_write; abort the transaction to leave nothing behind');
end $fn$;

-- ---- 3. residue, measured after the fact ---------------------------------------------------------
-- A ledger written inside the transaction rolls back with the rows it describes, so it can prove
-- nothing about what survived. This scans the real relations for this repository's fixture
-- convention instead, and it is the check that answers "persistent fixture rows after test = 0".

create or replace function public.fn_phase_d_fixture_residue()
returns table(relation text, surviving_rows bigint)
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare r record; v_n bigint; v_pred text;
begin
  for r in
    select distinct wm.target_relation as rel from public.phase_d_object_write_map wm
     union select 'public.phase_d_object_record'
  loop
    v_pred := (select string_agg(format(
                 '(coalesce(%I::text,'''') like ''ZZ DEMO — %%'' or coalesce(%I::text,'''') like ''%%@example.invalid'' or coalesce(%I::text,'''') like ''zz-phase-d-%%'')',
                 a.attname, a.attname, a.attname), ' or ')
               from pg_attribute a
              where a.attrelid = r.rel::regclass and a.attnum > 0 and not a.attisdropped
                and format_type(a.atttypid, a.atttypmod) in ('text','character varying','jsonb'));
    if v_pred is null then continue; end if;
    execute format('select count(*) from %s where %s', r.rel, v_pred) into v_n;
    if v_n > 0 then
      relation := r.rel; surviving_rows := v_n; return next;
    end if;
  end loop;
end $fn$;

-- ---- 4. the board ---------------------------------------------------------------------------------

-- ROUTINE REMOVED 7 September 2026. public.fn_phase_d_fixture_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ---- 5. grants -------------------------------------------------------------------------------------

revoke all on function public.fn_phase_d_fixture_scenario(jsonb) from public;
revoke all on function public.fn_phase_d_fixture_residue() from public;
revoke all on function public.fn_phase_d_fixture_state() from public;
grant execute on function public.fn_phase_d_fixture_scenario(jsonb) to service_role;
grant execute on function public.fn_phase_d_fixture_residue() to service_role;
grant execute on function public.fn_phase_d_fixture_state() to service_role;

revoke all on public.phase_d_fixture_stage from anon, authenticated;
grant select on public.phase_d_fixture_stage to service_role;
alter table public.phase_d_fixture_stage enable row level security;

-- ---- 6. positive controls, on this deployment -------------------------------------------------------

do $ctl$
declare v_err text; v_fired boolean := false;
begin
  -- WITHOUT the test-context setting, the factory must refuse. This is the guard that stops the
  -- factory ever being reachable from ordinary application code, so it is made to fire.
  begin
    perform public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','deploy-control','execution_context','test'));
  exception when others then
    v_err := SQLERRM; v_fired := true;
  end;
  if not v_fired then
    raise exception 'D9c positive control FAILED: the factory ran with no app.phase_d_test_context';
  end if;
  if position('pd_fixture_no_test_context' in v_err) = 0 then
    raise exception 'D9c positive control FAILED: refused for the wrong reason: %', left(v_err,200);
  end if;

  -- And with the setting on, a non-test execution_context must still refuse.
  v_fired := false;
  perform set_config('app.phase_d_test_context', 'on', true);
  begin
    perform public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','deploy-control','execution_context','production'));
  exception when others then
    v_err := SQLERRM; v_fired := true;
  end;
  perform set_config('app.phase_d_test_context', '', true);
  if not v_fired or position('pd_fixture_not_test_context' in v_err) = 0 then
    raise exception 'D9c positive control FAILED: production context was accepted (%)', left(coalesce(v_err,'(no error)'),200);
  end if;

  raise notice 'D9c positive controls: the factory refuses without a declared test context and outside test.';
end $ctl$;

commit;

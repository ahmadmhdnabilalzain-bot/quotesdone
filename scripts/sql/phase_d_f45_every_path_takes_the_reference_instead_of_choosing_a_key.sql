-- F45 - every Phase D path takes the reference instead of choosing a key
--
-- F43 recorded which identity is canonical for each of the 56 objects; F44 made the write services
-- return it. This migrates the three paths that were choosing for themselves:
--
--   fn_phase_d_scenario_record_write   stores the envelope beside the row it created
--   fn_phase_d_fixture_scenario        contributes the canonical identity, not a row id
--   fn_phase_d_fixture_input           answers a context key from the envelope, or not at all
--
-- OBJECT_KEY AND RESULT_KEY WERE THE SAME QUESTION ASKED TWICE. F42 added OBJECT_KEY because two
-- stages needed the object-store key while the rest needed a relation primary key, and classified
-- them by hand. That list was correct and could not stay correct: which identity an object is known
-- by is a property of the OBJECT, and the frozen map has always said so. Both arms now read the
-- reference, and the classification is no longer a per-stage decision anyone can get wrong.
--
-- THERE IS NO FALLBACK CHAIN IN THE RESOLVER, and that is deliberate. The previous body was
-- coalesce(contributed_value, business_key), which is a guess between two keys, and it is how
-- artifact_sha256 came to resolve to 44208. An identity stage now answers from the envelope or
-- contributes nothing at all, so the key falls through to the object payload, then to the committed
-- catalogue, then to an explicit refusal -- each of which is a stated source rather than a guess.
--
-- THE REST OF ALL THREE ROUTINES IS BYTE-IDENTICAL. Five anchors, each required to match once.

CREATE OR REPLACE FUNCTION public.fn_phase_d_scenario_record_write(p_input jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_run bigint := public.fn_phase_d_fixture_context();
  v_id  bigint;
begin
  if v_run is null then
    raise exception 'fn_phase_d_scenario_record_write: no verified Phase D fixture context. The evidence manifest is written only inside an audited fixture run. (pd_fixture_no_test_context)'
      using errcode = '42501';
  end if;
  insert into public.phase_d_scenario_record
    (fixture_run_id, fixture_id, fixture_version, source_checksum, object_id, business_key,
     owner_ref, ownership_scope, state, canonical_relation, canonical_service, result_reference,
     contributes_ref, contributed_value, contributes_kind, trace_id, provenance, expected_effect,
     canonical_ref)
  values (v_run,
          p_input->>'fixture_id',
          coalesce(nullif(p_input->>'fixture_version','')::int, 1),
          p_input->>'source_checksum',
          p_input->>'object_id',
          p_input->>'business_key',
          nullif(p_input->>'owner_ref',''),
          coalesce(nullif(p_input->>'ownership_scope',''),'COMPANY'),
          nullif(p_input->>'state',''),
          nullif(p_input->>'canonical_relation',''),
          coalesce(nullif(p_input->>'canonical_service',''),'fn_phase_d_object_write'),
          nullif(p_input->>'result_reference',''),
          nullif(p_input->>'contributes_ref',''),
          nullif(p_input->>'contributed_value',''),
          nullif(p_input->>'contributes_kind',''),
          nullif(p_input->>'trace_id','')::bigint,
          coalesce(nullif(p_input->>'provenance',''),
                   'PHASE_D_FIXTURE_DO_NOT_PUBLISH — created by the zero-persistence scenario factory inside a transaction that is aborted'),
          nullif(p_input->>'expected_effect',''),
          -- F44/F45. The canonical reference the write service returned. The scenario row's own
          -- scenario_record_id is never the business object identity.
          p_input->'canonical_ref')
  on conflict (fixture_run_id, object_id, business_key) do update
     set state = excluded.state, result_reference = excluded.result_reference,
         contributed_value = excluded.contributed_value
  returning scenario_record_id into v_id;
  return v_id;
end
$function$
;

CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_scenario(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_ok     int := 0; v_blocked int := 0; v_owned int := 0;
  v_for_wf text := nullif(btrim(coalesce(p_input->>'for_workflow','')),'');
  v_notif_before bigint; v_notif_after bigint;
  v_inbox_before bigint; v_inbox_after bigint;
  v_notif_start  bigint; v_inbox_start  bigint;
  v_net_start    bigint;
  v_fixture_run  bigint;                     -- F01: the audited fixture run this build belongs to
  v_terms_ver    text;   v_terms_hash text;  -- F08: a REAL published document, not an invented one
  v_sup_ver      text;   v_sup_hash   text;
  v_art_sha      text;                       -- F08: the digest BR-036 resolves
  v_cat          jsonb;                      -- F08: a committed catalogue value
  v_scenario_id  bigint;
  v_state_col    text;    -- F15: the column the write map points at the state
  v_actual       text;    -- F15: what the product left in it
begin
  if v_label is null then
    raise exception 'fn_phase_d_fixture_scenario: label is required; it is what makes the ids deterministic and the residue findable (pd_fixture_label_missing)'
      using errcode = '22023';
  end if;
  if v_ctx <> 'test' then
    raise exception 'fn_phase_d_fixture_scenario: execution_context is %; this factory runs only in test (pd_fixture_not_test_context)',
      coalesce(nullif(v_ctx,''),'(unset)') using errcode = '23514';
  end if;
  -- F01. THIS READ A GUC ANY CALLER COULD SET. `set local app.phase_d_test_context = 'on'` was
  -- accepted from service_role, so the "protected test context" was a string the caller supplied
  -- about itself -- the same shape as a guard authenticating an email. The context is now an hmac
  -- over the current txid, keyed by a secret no role can SELECT, minted only by
  -- fn_phase_d_test_context_open against an approved audited operation.
  v_fixture_run := public.fn_phase_d_fixture_context();
  if v_fixture_run is null then
    raise exception 'fn_phase_d_fixture_scenario: no verified Phase D fixture context in this transaction (pd_fixture_no_test_context)'
      using errcode = '23514',
            hint = 'select public.fn_phase_d_test_context_open(''{"operation_key":"pdop_scenario_factory","label":"..."}''); and abort the transaction when finished.';
  end if;
  if current_user in ('anon','authenticated') then
    raise exception 'fn_phase_d_fixture_scenario: % may not build fixtures (pd_fixture_untrusted_caller)',
      current_user using errcode = '42501';
  end if;

  -- F08. BR-025 REQUIRES THE EXACT DISPLAYED VERSION AND ITS DIGEST, and this factory was writing
  -- 'zz-terms-v1' with sha256('zz-terms-v1') -- a hash OF THE VERSION STRING, not of any terms.
  -- The rule resolves the pair against public.legal_documents where the displayed body hashes to
  -- exactly that digest, so the acceptance the factory created could never be an acceptance of
  -- anything, and BR-025 refused every terms step for the right reason. The pair is now READ from
  -- the published document, so the fixture accepts terms that actually exist.
  select d.version, encode(sha256(convert_to(coalesce(d.body_html,''),'UTF8')),'hex')
    into v_terms_ver, v_terms_hash
    from public.legal_documents d where d.slug = 'customer-terms' order by d.version desc limit 1;
  select d.version, encode(sha256(convert_to(coalesce(d.body_html,''),'UTF8')),'hex')
    into v_sup_ver, v_sup_hash
    from public.legal_documents d where d.slug = 'supplier-agreement' order by d.version desc limit 1;
  -- The artifact digest is the digest of the committed artifact fixture's own text, so BR-036
  -- resolves it against a record this scenario writes rather than against a string.
  select encode(sha256(convert_to(c.value #>> '{}','UTF8')),'hex') into v_art_sha
    from public.phase_d_fixture_catalogue c
   where c.scope = 'CONTEXT_KEY' and c.field_key = 'artifact_ref';

  select coalesce(max(id),0) into v_net_start from net.http_request_queue;
  select count(*) into v_notif_start from public.notifications;
  select count(*) into v_inbox_start from public.kernel_trigger_inbox;

  for st in select * from public.phase_d_fixture_stage where stage_no <= v_upto order by stage_no
  loop
    -- A SCENARIO MUST NOT PRE-CREATE THE OBJECT THE WORKFLOW UNDER TEST PRODUCES. W09 writes
    -- supplier_capability, W14 writes quotation, W16 writes payment_transaction; building those
    -- first made the workflow collide with its own output on a unique constraint, and a harness
    -- that seeds the row the step is supposed to create is answering its own question. The set is
    -- read from phase_d_step_effect for that workflow, never listed by hand.
    -- D22. THE EXCLUSION SKIPS LEAVES ONLY, SO A CASCADE IS IMPOSSIBLE BY CONSTRUCTION.
    --
    -- Measured with the old rule: for_workflow on W09 skipped 3 stages and the requires_stages
    -- cascade then blocked 13 MORE, because supplier_account is a parent of half the lineage. The
    -- D9 closure recorded the same shape as closure falling 14 -> 3, which is why the exclusion was
    -- left available and unused. Removing a parent to avoid a collision costs more than it saves.
    --
    -- A stage no other stage requires cannot cascade. supplier_assignment and provider_event are
    -- both leaves, and they are exactly the two collisions left: W12 writes supplier_assignment and
    -- GATE-015 correctly refused the fixture's as a duplicate dispatch. The skip is still recorded
    -- in the manifest as SKIPPED_PRODUCED_BY_THE_WORKFLOW_UNDER_TEST, never silently.
    if v_for_wf is not null
       and not exists (select 1 from public.phase_d_fixture_stage t
                        where st.stage_key = any(t.requires_stages))
       and exists (
         select 1 from public.phase_d_step_effect x
          where x.workflow_id = v_for_wf and x.effect_object_id = st.object_id) then
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status', 'SKIPPED_PRODUCED_BY_THE_WORKFLOW_UNDER_TEST', 'detail', v_for_wf));
      v_owned := v_owned + 1;
      continue;
    end if;

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
    -- F10. THE STATE IS THE STAGE'S OWN DECLARATION. This line used to read v_state := 'open' and
    -- every branch below then assigned a literal over it, so public.phase_d_fixture_stage.working_state
    -- -- the column whose sibling working_state_evidence explains, per stage, WHY that state -- was
    -- read by nothing at all. Five stages carried a state their object's contract does not declare
    -- and refused on every build since they were written; correcting the table changed nothing,
    -- because the table was not the source. It is now.
    v_state := coalesce(nullif(btrim(st.working_state),''), 'open');
    v_pay   := jsonb_build_object('fixture_label', v_label, 'stage', st.stage_key,
                                  'phase_d_test_context', true);

    -- D22. company_objective HAS NEVER ONCE CREATED ITS OBJECT.
    --
    -- D16 added this stage to fix W01-S03 dying on department_objective_goal_key_fkey, and it has
    -- refused on every build since with
    --     null value in column "goal" of relation "company_goals" violates not-null
    -- because the chain below has no branch for it, so the payload carried only the three
    -- bookkeeping keys every stage gets. The write map declares goal and metric; both are NOT NULL
    -- with no default.
    --
    -- Nothing failed loudly. stages_created read 23 of 25 and the missing one was recorded as
    -- REFUSED inside the manifest, where no caller was looking. A stage added to fix a foreign key
    -- and never observed creating anything is the "finished capability with no entry point" shape,
    -- and the only reason it surfaced is that a control started counting stages_not_created.
    if st.stage_key = 'company_objective' then
      v_pay := v_pay || jsonb_build_object(
        'goal', 1, 'metric', format('zz_demo_%s', v_label), 'active', true, 'direction', 'at_least');

    elsif st.stage_key = 'customer_account' then
      -- NO EMAIL AND NO PHONE. trg_inquiry_received_a queues a customer email for any inquiry whose
      -- customer has an address, and trg_new_quote_sms / trg_reveal_receipt_a do the same on a
      -- phone. The fixture identity carries neither, and the per-stage assertion below is what
      -- proves it rather than this comment.
      v_pay := v_pay || jsonb_build_object('full_name', v_name, 'locale', 'en');

    elsif st.stage_key = 'customer_terms_acceptance' then
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object(
        'terms_version', v_terms_ver,
        'terms_hash',    v_terms_hash,
        'accepted_by',   v_refs->>'customer_id');

    elsif st.stage_key = 'inquiry' then
      -- The FACTS fn_rfq_score reads, never a readiness flag. rfq_ready is derived by
      -- trg_rfq_complete and the verdict stays the product's own.
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || public.fn_phase_d_fixture_inquiry_payload(v_label);

    elsif st.stage_key = 'inquiry_answer' then
      v_owner := v_refs->>'inquiry_id';
      v_pay := v_pay || jsonb_build_object(
        'answer_scope','inquiry_shared', 'source_kind','customer', 'precedence', 1,
        'value', to_jsonb('ZZ DEMO — fixture answer'::text),
        'field_id', (select id from public.field_definition order by id limit 1),
        'group_id', (select id from public.inquiry_workstream_group order by id limit 1));

    elsif st.stage_key = 'inquiry_version' then
      v_owner := v_refs->>'inquiry_id';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id', 'version', 1);

    elsif st.stage_key = 'inquiry_route_set' then
      v_owner := v_refs->>'inquiry_id';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'route_state','confirmed', 'routes', '["general"]'::jsonb,
                                           'evidence','ZZ DEMO — fixture route evidence');

    elsif st.stage_key = 'inquiry_document' then
      v_owner := v_refs->>'inquiry_id';
      v_pay := v_pay || jsonb_build_object('kind','boq', 'mime','application/pdf',
                                           'bucket','zz-phase-d-fixtures',
                                           'path', format('zz/%s/%s.pdf', v_label, st.stage_key),
                                           'file_name', format('zz-%s.pdf', v_label));

    elsif st.stage_key = 'document_extraction' then
      v_owner := v_refs->>'document_id';
      v_pay := v_pay || jsonb_build_object('document_id', v_refs->>'document_id',
                                           'method','deterministic', 'paid_model_used', false);

    elsif st.stage_key = 'supplier_safe_package' then
      v_owner := v_refs->>'inquiry_id';
      v_pay := v_pay || jsonb_build_object(
        'inquiry_id', v_refs->>'inquiry_id',
        'safe_package_ref', v_key,
        'safe_package_approved_by', 'compliance_and_privacy_officer',
        'contents','ZZ DEMO — scope and quantities only; no customer identity');

    elsif st.stage_key = 'supplier_account' then
      v_pay := v_pay || jsonb_build_object('company_name', v_name, 'verified', true);

    elsif st.stage_key = 'supplier_terms_acceptance' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('terms_version', v_sup_ver,
        'terms_hash',  v_sup_hash,
        'supplier_id', v_refs->>'supplier_id');

    elsif st.stage_key = 'supplier_capability' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('trades', '["general"]'::jsonb);

    elsif st.stage_key = 'supplier_verification_case' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('supplier_id', v_refs->>'supplier_id',
                                           'evidence','ZZ DEMO — fixture verification evidence',
                                           'verified_by','supplier_verification');

    elsif st.stage_key = 'supplier_assignment' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'similarity', 0.9,
                                           'match_reason','ZZ DEMO — fixture assignment');

    elsif st.stage_key = 'quotation' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id', 'quote_amount', 1000);

    elsif st.stage_key = 'quotation_revision' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('quote_id', v_refs->>'quote_id',
                                           'quote_revision_ref', v_key, 'platform_edited', false);

    elsif st.stage_key = 'quotation_comparison' then
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'analysis', jsonb_build_object('note','ZZ DEMO — fixture comparison'),
                                           'quote_count', 1,
                                           'signature', encode(sha256(convert_to(v_key,'UTF8')),'hex'));

    elsif st.stage_key = 'customer_selection' then
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object('comparison_id', v_refs->>'comparison_id',
                                           'selected_quote_id', v_refs->>'quote_id');

    elsif st.stage_key = 'payment_transaction' then
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'quote_id', v_refs->>'quote_id',
                                           'quote_amount', 1000, 'reveal_fee', 100,
                                           'payment_ref', format('zz-pay-%s', v_label));

    elsif st.stage_key = 'provider_event' then
      v_owner := v_refs->>'transaction_id';
      v_key := format('evt_zz_%s', v_label);
      v_pay := v_pay || jsonb_build_object('event_type','checkout.session.completed');

    elsif st.stage_key = 'reconciliation_case' then
      v_owner := v_refs->>'transaction_id';
      v_pay := v_pay || jsonb_build_object('transaction_id', v_refs->>'transaction_id',
                                           'monetary_state','reconciled');

    elsif st.stage_key = 'reveal_transaction' then
      v_key := v_refs->>'transaction_id';
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object('reveal_fee', 100,
                                           'payment_ref', format('zz-pay-%s', v_label),
                                           'revealed_at', now(),
                                           'supplier_id', (v_refs->>'supplier_id')::bigint);

    elsif st.stage_key = 'refund_dispute_case' then
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object('transaction_id', v_refs->>'transaction_id',
                                           'amount_fils', 10000, 'reason_code','other',
                                           'reason_note','ZZ DEMO — fixture refund case; no refund is executed',
                                           'requested_by', v_refs->>'customer_id');

    elsif st.stage_key = 'artifact_revision' then
      -- F08. BR-036 resolves artifact_sha256 against an artifact_review row or a business object
      -- record CARRYING that digest. public.artifact_review holds 0 rows, so the record is the
      -- only honest route: this stage writes one whose payload carries the digest of the committed
      -- artifact fixture's own text. The digest is computed, never typed.
      v_pay := v_pay || jsonb_build_object(
        'artifact_ref', (select c.value #>> '{}' from public.phase_d_fixture_catalogue c
                          where c.scope='CONTEXT_KEY' and c.field_key='artifact_ref'),
        'artifact_sha256', v_art_sha,
        'revision', 1);

    elsif st.stage_key = 'system_incident' then
      v_pay := v_pay || jsonb_build_object(
        'title',    (select c.value #>> '{}' from public.phase_d_fixture_catalogue c
                      where c.scope='EFFECT_PAYLOAD' and c.field_key='title'),
        'severity', 'low');

    elsif st.stage_key = 'marketing_content' then
      v_pay := v_pay || jsonb_build_object(
        'title', (select c.value #>> '{}' from public.phase_d_fixture_catalogue c
                   where c.scope='EFFECT_PAYLOAD' and c.field_key='title'),
        'body',  (select c.value #>> '{}' from public.phase_d_fixture_catalogue c
                   where c.scope='EFFECT_PAYLOAD' and c.field_key='body'),
        'channel','none', 'published', false);

    elsif st.stage_key = 'knowledge_capability_request' then
      v_pay := v_pay || jsonb_build_object(
        'requested_capability','REASONING',
        'note', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a knowledge/capability request record; no provider is called by Phase D');

    elsif st.stage_key = 'workforce_performance_case' then
      v_pay := v_pay || jsonb_build_object(
        'subject_role','phase_d_fixture_role',
        'note', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a workforce performance case about no real person and no real agent');

    elsif st.stage_key = 'notification_intent' then
      v_pay := v_pay || jsonb_build_object(
        'recipient',     (select c.value #>> '{}' from public.phase_d_fixture_catalogue c
                           where c.scope='EFFECT_PAYLOAD' and c.field_key='recipient'),
        'consent_basis', (select c.value #>> '{}' from public.phase_d_fixture_catalogue c
                           where c.scope='EFFECT_PAYLOAD' and c.field_key='consent_basis'),
        'provider_mode','mock', 'suppressed', true);

    elsif st.stage_key = 'department_mandate' then
      v_pay := v_pay || jsonb_build_object(
        'objective', (select c.value #>> '{}' from public.phase_d_fixture_catalogue c
                       where c.scope='EFFECT_PAYLOAD' and c.field_key='objective'),
        'goal_key',  v_refs->>'goal_key',
        'dept_key',  (select dept_key from public.org_departments where active order by dept_key limit 1));
      v_owner := (select dept_key from public.org_departments where active order by dept_key limit 1);

    elsif st.stage_key = 'review_record' then
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

      -- F15. THE PRODUCT'S OWN TRIGGERS GET THE LAST WORD ON AN INSERT, SO SETTLE THE STATE.
      -- public.trg_inquiry_enrich is a BEFORE INSERT trigger that sets the status a NEW inquiry
      -- has, so the inquiry stage asked for quote_ready and the row came out open, and GATE-011
      -- and BR-013 refused it -- correctly, because it was not quote-ready. A real inquiry is
      -- created open and BECOMES quote-ready, so the factory now does that: create, read back the
      -- column the write map points at the state, and if the product moved it, write again through
      -- the same canonical service. Skipped entirely when the readback already agrees.
      select c.k into v_state_col
        from public.phase_d_object_write_map wm,
             lateral (select k from jsonb_object_keys(wm.column_map) k where wm.column_map->>k = 'state') c
       where wm.object_id = st.object_id limit 1;
      if v_state_col is not null then
        begin
          execute format('select %I::text from %s where %I::text = $1',
                         v_state_col,
                         (select wm.target_relation from public.phase_d_object_write_map wm
                           where wm.object_id = st.object_id),
                         (select wm.key_column from public.phase_d_object_write_map wm
                           where wm.object_id = st.object_id))
            into v_actual using coalesce(split_part(v_w->>'result_reference','=',2), v_key);
          if v_actual is distinct from v_state then
            v_w := public.fn_phase_d_object_write(jsonb_build_object(
              'object_id', st.object_id, 'business_key', v_key, 'owner_ref', v_owner,
              'created_by', v_actor, 'state', v_state, 'payload', v_pay));
            v_man := v_man || jsonb_build_array(jsonb_build_object(
              'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
              'status','SETTLED',
              'detail', format('%s.%s was %s after the create and the stage declares %s; a second write through the same canonical service settled it',
                               v_state_col, st.object_id, coalesce(v_actual,'(null)'), v_state)));
          end if;
        exception when others then
          v_man := v_man || jsonb_build_array(jsonb_build_object(
            'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
            'status','SETTLE_REFUSED',
            'refused_with', coalesce((regexp_match(SQLERRM,'\((pd_[a-z0-9_]+)\)'))[1],'(none)'),
            'reason', left(SQLERRM, 300)));
        end;
        v_state_col := null; v_actual := null;
      end if;

      -- F02. THE EVIDENCE MANIFEST THE FOUNDER ASKED FOR. Written from what the canonical write
      -- RETURNED, in the same statement block, so a manifest entry cannot exist for an object the
      -- service did not create -- and so an object the service created cannot be missing from it.
      v_scenario_id := public.fn_phase_d_scenario_record_write(jsonb_build_object(
        'fixture_id',        format('PDS-%s', st.stage_key),
        'fixture_version',   1,
        'source_checksum',   encode(sha256(convert_to(v_pay::text,'UTF8')),'hex'),
        'object_id',         st.object_id,
        'business_key',      coalesce(split_part(v_w->>'result_reference','=',2), v_key),
        'owner_ref',         v_owner,
        'ownership_scope',   coalesce((select ob.ownership_scope
                                         from public.phase_d_business_object_binding ob
                                        where ob.object_id = st.object_id), 'COMPANY'),
        'state',             v_w->>'state',
        'canonical_relation',v_w->>'canonical_relation',
        'canonical_service', 'fn_phase_d_object_write',
        'result_reference',  v_w->>'result_reference',
        'contributes_ref',   st.contributes_ref,
        'contributes_kind',  st.contributes_kind,
        'canonical_ref',     v_w->'canonical_ref',
        'contributed_value', case when st.stage_key = 'inquiry_route_set' then 'confirmed'
                                  -- F41. A PAYLOAD_VALUE STAGE CONTRIBUTES A VALUE, NOT ITS ROW ID.
                                  -- artifact_revision declares it contributes artifact_sha256, and
                                  -- this expression handed over split_part(result_reference,'=',2)
                                  -- -- the primary key of the row it had just written. BR-036 read
                                  -- 44208 and refused it as "not a SHA-256 digest", correctly.
                                  -- The digest is in the record's own payload, written by F08 over
                                  -- the committed artifact body, so it is read from there.
                                  -- F42. AN OBJECT_KEY STAGE CONTRIBUTES THE KEY THE PHASE D
                                  -- OBJECT STORE USES, WHICH IS NOT THE RELATION'S ROW ID.
                                  -- F45. OBJECT_KEY AND RESULT_KEY WERE THE SAME QUESTION ASKED TWICE.
                                  -- Which identity an object is known by is a property of the
                                  -- object, recorded once in phase_d_object_reference_strategy and
                                  -- derived from the frozen map -- not something a stage decides.
                                  -- Both arms are now the canonical reference the writer returned.
                                  when st.contributes_kind in ('OBJECT_KEY','RESULT_KEY')
                                    then v_w->'canonical_ref'->'physical_ref'->>'pk_value'
                                  when st.contributes_kind = 'PAYLOAD_VALUE' then
                                    (select o.payload #>> array[st.contributes_ref]
                                       from public.phase_d_object_record o
                                      where o.object_id = st.object_id
                                        and o.business_key = split_part(v_w->>'result_reference', '=', 2)
                                      limit 1)
                                  else split_part(v_w->>'result_reference', '=', 2) end,
        'expected_effect',   coalesce(st.note,'(none recorded on the stage)')));

      if st.contributes_ref is not null then
        v_refs := v_refs || jsonb_build_object(st.contributes_ref,
          case when st.stage_key = 'inquiry_route_set' then 'confirmed'
               when st.contributes_kind in ('OBJECT_KEY','RESULT_KEY')
                 then v_w->'canonical_ref'->'physical_ref'->>'pk_value'
               when st.contributes_kind = 'PAYLOAD_VALUE' then
                 (select o.payload #>> array[st.contributes_ref]
                    from public.phase_d_object_record o
                   where o.object_id = st.object_id
                     and o.business_key = split_part(v_w->>'result_reference', '=', 2)
                   limit 1)
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
      -- D17. An outbound HTTP request is not a stage that failed; it is the whole scenario losing
      -- its zero-external-effect property. It aborts the build exactly as a notification does.
      if position('pd_object_outbound_request_produced' in v_err) > 0 then raise; end if;
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status','REFUSED',
        'refused_with', coalesce((regexp_match(v_err,'\((pd_[a-z0-9_]+)\)'))[1],'(none)'),
        'reason', left(v_err, 300)));
      v_blocked := v_blocked + 1;
    end;
  end loop;

  -- F12. THE FOUNDER AUTHORITY FIXTURE, LAST, BECAUSE NOTHING DEPENDS ON IT. Six rules resolve
  -- founder_authority_ref against public.founder_command; a Phase D run has no founder command
  -- behind it, so all six refuse on every founder-gated step. This creates one, marked, at state
  -- received, founder_initiated_only false and refund_semantics false, inside the same aborted
  -- transaction -- and it authenticates nobody: see the header of F12.
  begin
    v_w := public.fn_phase_d_founder_authority_fixture(jsonb_build_object('label', v_label));
    v_refs := v_refs || jsonb_build_object('founder_authority_ref', v_w->>'founder_authority_ref');
    v_man := v_man || jsonb_build_array(jsonb_build_object(
      'stage_no', 999, 'stage_key','founder_authority', 'object_id','founder_command_fixture',
      'status','CREATED', 'relation','public.founder_command',
      'result_reference', v_w->>'founder_authority_ref', 'state','received',
      'contributes','founder_authority_ref'));
    v_ok := v_ok + 1;
  exception when others then
    v_man := v_man || jsonb_build_array(jsonb_build_object(
      'stage_no', 999, 'stage_key','founder_authority', 'object_id','founder_command_fixture',
      'status','REFUSED',
      'refused_with', coalesce((regexp_match(SQLERRM,'\((pd_[a-z0-9_]+)\)'))[1],'(none)'),
      'reason', left(SQLERRM, 300)));
    v_blocked := v_blocked + 1;
  end;

  select count(*) into v_notif_after from public.notifications;
  select count(*) into v_inbox_after from public.kernel_trigger_inbox;

  return jsonb_build_object(
    'ok', v_blocked = 0, 'label', v_label, 'fixture_run_id', v_fixture_run,
    'evidence_manifest', (select coalesce(jsonb_agg(to_jsonb(x) order by x.scenario_record_id),'[]'::jsonb)
                            from public.phase_d_scenario_record x
                           where x.fixture_run_id = v_fixture_run),
    'stages_created', v_ok, 'stages_not_created', v_blocked,
    'stages_left_to_the_workflow_under_test', v_owned, 'for_workflow', v_for_wf,
    'stages_declared', (select count(*) from public.phase_d_fixture_stage where stage_no <= v_upto),
    'parent_refs', v_refs,
    -- THE RULE CONTEXT IS WHAT THIS SCENARIO ACTUALLY PERSISTED, not a set of plausible strings.
    -- Every value below is either a key returned by a write above or the exact value that write
    -- recorded on the row. A rule reading one of these is reading the scenario, and a rule whose
    -- key is absent still gets the driver's generated fixture and still refuses.
    -- F08. `rule_context` used to be returned here as a set of plausible strings for a caller to
    -- hand the rules. E32 removed the caller's ability to hand the kernel anything, so nothing has
    -- read it since; and two of its values were false -- terms_hash was the digest of the VERSION
    -- STRING, and safe_package_approved_by and assignment_result were literals with no record
    -- behind them. It is replaced by evidence_manifest above, which is what this scenario actually
    -- persisted, and by the committed catalogue for the values that are content rather than record.
    'parent_ref_keys', (select coalesce(jsonb_agg(k order by k),'[]'::jsonb)
                          from jsonb_object_keys(v_refs) k),
    'manifest', v_man,
    'notifications_written_by_this_scenario', v_notif_after - v_notif_start,
    'kernel_trigger_rows_written_by_this_scenario', v_inbox_after - v_inbox_start,
    -- D17. MEASURED, NOT ASSERTED. Before D17 this object said 'external_effects', 0 while every
    -- build enqueued two POSTs to production edge functions, because the only thing counted was
    -- public.notifications. Both doors are now counted and the writer refuses on either.
    'outbound_http_requests_written_by_this_scenario',
      (select count(*) from net.http_request_queue where id > v_net_start),
    'external_effects', 0, 'paid_calls', 0,
    'note', 'every row here was written through fn_phase_d_object_write; abort the transaction to leave nothing behind');
end $function$
;

CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_input(p_step_run_id bigint, p_scope text, p_key text)
 RETURNS TABLE(value jsonb, provenance text, fixture_id text, fixture_version integer, checksum text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_run  bigint := public.fn_phase_d_fixture_context();
  sr     public.phase_c_workflow_step_run%rowtype;
  v_wf   text;
  r      record;
begin
  -- NO VERIFIED FIXTURE CONTEXT, NO FIXTURE. This single line is the production boundary.
  if v_run is null then return; end if;

  select * into sr from public.phase_c_workflow_step_run where step_run_id = p_step_run_id;
  if not found then return; end if;
  select b.workflow_id into v_wf from public.phase_d_handler_binding b where b.step_id = sr.step_id;

  if p_scope = 'CONTEXT_KEY' then
    -- (1) A REFERENCE RESOLVES TO WHAT THIS RUN ACTUALLY CREATED, and to the value the stage
    --     CONTRIBUTED rather than to its row id -- see F09 on inquiry_route_set.
    -- F40. A STAGE THAT CONTRIBUTED NOTHING STILL ANSWERED, WITH ITS OWN ROW ID.
    --
    -- coalesce(contributed_value, business_key) means a stage whose contributed_value was never set
    -- answers the key with the primary key of the row it created. Measured: the artifact_revision
    -- stage declares contributes_ref = 'artifact_sha256', sets no contributed_value, and so
    -- resolved artifact_sha256 to 44208 -- a row id. BR-036 then refused with "artifact_sha256
    -- 44208 is not a SHA-256 digest (64 hexadecimal characters), so it was not computed over any
    -- artifact", which was true, and which no fixture could correct: a non-null wrong value blocks
    -- the catalogue fallback below, because that fallback exists only for a key NOTHING answered.
    --
    -- The fallback to business_key is kept where it is right -- a RESULT_KEY stage contributes the
    -- identity of what it created, and that IS its business key -- and refused where it is not.
    -- A stage that declares it contributes a value and supplies none now contributes NOTHING, so
    -- the object-payload branch below and then the committed catalogue get their turn, and a key
    -- with no answer anywhere stays unresolved and its rule refuses.
    -- F45. THE CANONICAL REFERENCE, OR NOTHING. There is no coalesce chain here on purpose: a
    -- fallback among the scenario row id, the object-record key, the business key and the relation
    -- primary key is precisely the guessing the founder's ruling of 23 Aug 2026 removes. An identity
    -- stage answers from the reference the write service returned; a PAYLOAD_VALUE or STATE stage
    -- answers with the value it settled; anything else contributes nothing and the key falls through
    -- to the object payload, then to the committed catalogue, then to an explicit refusal.
    select case when sc.contributes_kind in ('PAYLOAD_VALUE','STATE') then sc.contributed_value
                when sc.canonical_ref is not null
                  then sc.canonical_ref->'physical_ref'->>'pk_value'
                else null end v,
           sc.object_id o,
           sc.canonical_relation cr, sc.fixture_id fi, sc.fixture_version fv, sc.source_checksum ck
      into r
      from public.phase_d_scenario_record sc
     where sc.fixture_run_id = v_run and sc.contributes_ref = p_key
     order by sc.scenario_record_id limit 1;
    if found and r.v is not null then
      value := to_jsonb(r.v);
      provenance := format('phase_d_scenario_record: the %s created by fixture run %s through %s',
                           r.o, v_run, coalesce(r.cr,'its canonical service'));
      fixture_id := r.fi; fixture_version := r.fv; checksum := r.ck;
      return next; return;
    end if;

    -- (1b) A FACT THE SCENARIO RECORDED ON ONE OF ITS OWN ROWS. terms_version and terms_hash are
    --      the example: they are not keys and not authorable content -- they are read off the
    --      published document and written onto the acceptance record, so the honest place to find
    --      them is that record's own payload.
    select o.payload->p_key v, sc.object_id ob, sc.canonical_relation cr, sc.fixture_id fi,
           sc.fixture_version fv, sc.source_checksum ck
      into r
      from public.phase_d_scenario_record sc
      join public.phase_d_object_record o
        on o.object_id = sc.object_id and o.business_key = sc.business_key
     where sc.fixture_run_id = v_run and o.payload ? p_key
       and jsonb_typeof(o.payload->p_key) <> 'null'
     order by sc.scenario_record_id desc limit 1;
    if found then
      value := r.v;
      provenance := format('phase_d_object_record.payload of the %s created by fixture run %s',
                           r.ob, v_run);
      fixture_id := r.fi; fixture_version := r.fv; checksum := r.ck;
      return next; return;
    end if;
  end if;

  -- (2) CONTENT COMES FROM THE COMMITTED CATALOGUE, most specific row first.
  for r in
    select c.* from public.phase_d_fixture_catalogue c
     where c.scope = p_scope and c.field_key = p_key
       and (c.step_id is null or c.step_id = sr.step_id)
       and (c.workflow_id is null or c.workflow_id = v_wf)
     order by (c.step_id is not null) desc, (c.workflow_id is not null) desc, c.fixture_id
     limit 1
  loop
    value := r.value;
    provenance := format('phase_d_fixture_catalogue %s v%s (%s) — %s',
                         r.fixture_id, r.fixture_version, r.checksum, r.expected_result);
    fixture_id := r.fixture_id; fixture_version := r.fixture_version; checksum := r.checksum;
    return next; return;
  end loop;
  return;
end
$function$
;

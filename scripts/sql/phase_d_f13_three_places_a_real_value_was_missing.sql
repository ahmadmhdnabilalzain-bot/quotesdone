-- F13 - three places a real value was missing, and one where a real value answered the wrong question
--
-- (1) THE FACTORY NOW CREATES THE FOUNDER AUTHORITY FIXTURE (F12). Six rules resolve
--     founder_authority_ref against public.founder_command. Nothing in a Phase D run put a row
--     there, so all six refused on every founder-gated step in the estate. The fixture is created
--     last, because nothing depends on it, and it is recorded in the evidence manifest as
--     contributing founder_authority_ref. Read F12's header for what it deliberately cannot do.
--
-- (2) BR-029 WAS ANSWERED WITH THE WRONG SUBJECT. fn_phase_d_step_context resolved
--     evidence_authority from the ARRIVAL CLASSIFICATION -- "A NEW_WORK_REQUEST (system.task_engine)
--     via dbtrigger:public.inquiries:trg_inquiry_received_a, activation ACTIVE". That is a true fact
--     about how the run started and it is not an evidence authority: BR-029 is about RANK, and the
--     estate's ranking is public.mep_evidence_weight. Measured on every drive since E30: 0 matching
--     rows, so the rule refused the whole estate while its reason read as though someone had named
--     an unranked authority rather than as though the resolver had answered a different question.
--     The classification is now offered only if it appears in the ranking, and the run's own
--     document extraction is offered when it does not -- both reads. Otherwise the key is
--     unresolved, which is the honest state and which keeps BR-029 refusing in production.
--
-- (3) A STEP THAT WRITES AN OBJECT OTHER THAN ITS RUN'S PRIMARY COULD NEVER GET A BUSINESS KEY.
--     pd_effect_owner_or_key_missing on W01-S07 and its siblings. Correct in production. Inside a
--     verified fixture run the scenario's own record supplies it, or it is derived deterministically
--     so a replay collides with itself rather than creating a second record.

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
        'contributed_value', case when st.stage_key = 'inquiry_route_set' then 'confirmed'
                                  else split_part(v_w->>'result_reference', '=', 2) end,
        'expected_effect',   coalesce(st.note,'(none recorded on the stage)')));

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

CREATE OR REPLACE FUNCTION public.fn_phase_d_step_context(p_step_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  sr public.phase_c_workflow_step_run%rowtype;
  r  public.phase_c_workflow_run%rowtype;
  s  public.phase_b_workflow_step%rowtype;
  b  public.phase_d_handler_binding%rowtype;
  ec public.phase_d_step_effect%rowtype;
  v_keys   text[];
  v_k      text;
  v_val    jsonb;
  v_src    text;
  v_ctx    jsonb := '{}'::jsonb;
  v_prov   jsonb := '{}'::jsonb;
  v_unres  text[] := '{}';
  v_obj    text;
  v_boid   text;
  v_rel    text;
  v_keycol text;
  v_owncol text;
  v_row_id text;
  v_row_own text;
  v_found  boolean := false;
  v_key_prefixed boolean := false;   -- E25
  v_sql    text;
  v_from   text;
  v_to     text;
  v_route  text;
  v_cmd    bigint;
  v_src_ref   text;
  v_src_kind  text;
  v_src_class text;
  v_src_actor text;
  v_src_act   text;
  v_email     text;
  v_fx_val    jsonb;   -- F11
  v_fx_src    text;    -- F11
begin
  select * into sr from public.phase_c_workflow_step_run where step_run_id = p_step_run_id;
  if not found then
    raise exception 'fn_phase_d_step_context: no step run %', p_step_run_id using errcode = '23503';
  end if;
  select * into r  from public.phase_c_workflow_run    where run_id  = sr.run_id;
  select * into s  from public.phase_b_workflow_step   where step_id = sr.step_id;
  select * into b  from public.phase_d_handler_binding where step_id = sr.step_id;
  select * into ec from public.phase_d_step_effect     where step_id = sr.step_id;

  select coalesce(array_agg(distinct k), '{}') into v_keys from (
    select unnest(re.required_context) k from public.phase_d_rule_enforcement re
     where re.rule_id = any (coalesce(b.rule_ids,'{}'))
    union
    select unnest(gc.evidence_keys) k from public.phase_d_gate_contract gc
     where gc.gate_id = any (coalesce(b.gate_ids,'{}'))) q(k);

  -- ---- the frozen state model ------------------------------------------------------------------
  v_from  := r.state;
  -- E12. THE RESOLVER NULLED A FACT THE GATE EXISTS TO JUDGE.
  --
  -- to_state is the step's own frozen declaration: phase_b_workflow_step.success_workflow_state.
  -- Until now this line also re-ran GATE-006's test on it, and blanked the value when the test
  -- failed. That is a different act from resolving, and it had two consequences.
  --
  -- First, it made the answer depend on WHEN the resolver was called rather than on what the
  -- registry says. fn_phase_d_dispatch_step runs inside fn_kernel_open_step, and a step opened out
  -- of a handoff is dispatched while its run is still in waiting_handoff -- the state it is
  -- leaving. The old guard therefore asked whether the run could go waiting_handoff ->
  -- waiting_handoff, which the frozen model rightly says it cannot, and nulled the key. Called a
  -- moment later, against the same step run, the same function resolved it. Measured 2026-08-20:
  -- W01-S04/S05/S06 record to_state in phase_d_dispatch.unresolved_keys, and a direct call for the
  -- same step runs resolves it to waiting_handoff.
  --
  -- Second, and worse, it turned a judgeable fact into an absent one. GATE-006 already tests the
  -- transition against public.phase_b_workflow_transition, and already holds the reasoned branch
  -- for the case where a step declares the state it is already in (55 of 257 steps do). With the
  -- key blanked, the gate could not reach either branch and reported "requires [to_state] and the
  -- call names none of it" -- an evidence-absence message standing in for a judgement the
  -- instrument was built to make.
  --
  -- The resolution is therefore the declaration, and the judgement stays with the gate. This is a
  -- REMOVAL: nothing new is asserted, and a transition the frozen model does not declare is still
  -- refused -- by GATE-006, which is the check that owns it.
  v_to    := nullif(btrim(coalesce(s.success_workflow_state,'')),'');
  -- D42. route_state IS NOT "the first declared transition, alphabetically". That is what this
  -- resolver did, and GATE-010 duly reported "route state approved; only a confirmed route carries
  -- dispatch authority" for an inquiry that had never been routed. Picking a plausible value out of
  -- the declared set is the placeholder defect wearing a schema. A route state exists when a route
  -- has been confirmed; until then the key is unresolved and GATE-010 refuses, which is the gate
  -- doing its job.
  v_route := null;

  -- ---- the arrival that caused this run, and how the register classifies it ---------------------
  select ti.source_system, 'trigger' into v_src_ref, v_src_kind
    from public.kernel_trigger_inbox ti where ti.run_id = sr.run_id order by ti.inbox_id desc limit 1;
  if v_src_ref is null and coalesce(btrim(coalesce(r.business_object_id,'')),'') <> '' then
    -- D39(2). The first step of a run dispatches INSIDE fn_kernel_workflow_start, before the inbox
    -- row is stamped with run_id. business_object_id is on both sides already, derived from the same
    -- object rule, so it is what links them at the only moment that matters.
    select ti.source_system, 'trigger' into v_src_ref, v_src_kind
      from public.kernel_trigger_inbox ti
     where ti.business_object_id = r.business_object_id
     order by ti.inbox_id desc limit 1;
  end if;
  if v_src_ref is null then
    select si.source_type, 'signal' into v_src_ref, v_src_kind
      from public.kernel_signal_inbox si
     where si.workflow_run_id = sr.run_id order by si.signal_id desc limit 1;
  end if;
  if v_src_ref is null then
    select tk.source_ref, tk.source_kind into v_src_ref, v_src_kind
      from public.phase_c_task tk where tk.run_id = sr.run_id order by tk.task_id limit 1;
  end if;
  -- D40. THE INBOX ROW IS NOT READABLE BY run_id OR business_object_id AT FIRST-STEP DISPATCH TIME.
  -- fn_kernel_trigger_submit inserts the inbox row, then calls fn_kernel_workflow_start passing
  -- source_ref = 'trigger_inbox:<inbox_id>', and stamps run_id and business_object_id onto that row
  -- only AFTER the call returns. The dispatch happens inside it, so both earlier matches were looking
  -- for columns the row does not carry yet. The inbox id IS in the source_ref the kernel already
  -- passes, and fn_kernel_workflow_start writes it onto the task before it opens the step — the one
  -- identifier available at the only moment that matters.
  if v_src_ref like 'trigger_inbox:%' then
    select ti.source_system, 'trigger' into v_src_ref, v_src_kind
      from public.kernel_trigger_inbox ti
     where ti.inbox_id = nullif(substr(v_src_ref, 15), '')::bigint;
  end if;
  if coalesce(btrim(coalesce(v_src_ref,'')),'') <> '' then
    select c.source_class, c.system_actor, c.current_activation
      into v_src_class, v_src_actor, v_src_act
      from public.phase_c_source_cutover c
     where c.source_component_id = v_src_ref limit 1;
  end if;

  -- ---- the run's own business object -----------------------------------------------------------
  v_obj := coalesce(nullif(btrim(coalesce(ec.effect_object_id,'')),''),
                    (select bo.object_id from public.phase_d_business_object_binding bo
                      where bo.governing_workflow_id = r.workflow_id limit 1));
  v_boid := nullif(btrim(coalesce(r.business_object_id,'')),'');
  -- D39(1). The kernel writes the object rule out in full: 'inquiry:<uuid>'. Strip ONLY that
  -- object's own prefix; a blind split on ':' would corrupt an identifier that contains one.
  -- E25. WHETHER THE PREFIX MATCHED IS ITSELF A FACT, and the caller needs it. A run whose
  -- business_object_id is 'inquiry:<uuid>' names the object this step writes; one that reads
  -- 'outbox:195' or a probe label does not, and using the raw string as a business key would invent
  -- an identity for a record. Only a stripped key is a key.
  v_key_prefixed := (v_obj is not null and v_boid is not null and v_boid like (v_obj || ':%'));
  if v_key_prefixed then
    v_boid := substr(v_boid, length(v_obj) + 2);
  end if;
  if v_obj is not null and coalesce(v_boid,'') <> '' then
    select wm.target_relation, wm.key_column, wm.owner_column
      into v_rel, v_keycol, v_owncol
      from public.phase_d_object_write_map wm where wm.object_id = v_obj limit 1;
    if v_rel is not null and coalesce(btrim(v_keycol),'') <> ''
       and to_regclass(v_rel) is not null then
      begin
        v_sql := format('select %I::text, %s from %s where %I::text = $1 limit 1',
                        v_keycol,
                        case when coalesce(btrim(v_owncol),'') = '' then 'null::text'
                             else quote_ident(v_owncol) || '::text' end,
                        to_regclass(v_rel)::text, v_keycol);
        execute v_sql into v_row_id, v_row_own using v_boid;
        v_found := v_row_id is not null;
      exception when others then
        v_found := false;
      end;
    end if;
  end if;

  foreach v_k in array v_keys loop
    v_val := null; v_src := null;

    if v_k = 'from_state' then
      v_val := to_jsonb(v_from); v_src := 'phase_c_workflow_run.state';
    elsif v_k = 'to_state' then
      if v_to is not null then
        v_val := to_jsonb(v_to);
        v_src := 'phase_b_workflow_step.success_workflow_state, confirmed against phase_b_workflow_transition';
      end if;
    elsif v_k = 'route_state' then
      -- Resolved only from a route that actually exists. See the note above v_route.
      if v_route is not null then
        v_val := to_jsonb(v_route); v_src := 'the confirmed route for this inquiry';
      end if;

    elsif v_k in ('inquiry_id','supplier_id','quote_id','transaction_id','document_id',
                  'comparison_id','refund_id') then
      if v_found then
        v_val := to_jsonb(v_row_id);
        v_src := format('%s.%s, looked up by the run''s business_object_id', v_rel, v_keycol);
      end if;
    elsif v_k = 'caller_customer_id' then
      if v_found and v_row_own is not null then
        v_val := to_jsonb(v_row_own);
        v_src := format('%s.%s of the run''s own object', v_rel, coalesce(v_owncol,'(none)'));
      end if;

    elsif v_k = 'inquiry_owner' then
      -- D41. inquiry_owner IS A ROLE, NOT A CUSTOMER. BR-049 is the only consumer of this key —
      -- no gate declares it — and its predicate compares it to the literal role
      -- 'rfq_qualification_manager'. Resolving it from inquiries.customer_id handed a rule about
      -- ACCOUNTABILITY a customer UUID, so it refused every inquiry the moment the owner started
      -- resolving at all. The frozen rule text is unambiguous: "Specialist and document handoffs do
      -- not transfer overall inquiry accountability away from RFQ Qualification Manager unless an
      -- explicit approved workflow says so."
      --
      -- The subject is therefore the role accountable for the INQUIRY, which is
      -- phase_c_workflow_run.accountable_role_id of the run that owns it. For a W05 run that is this
      -- run; for W06 and W07, which are the specialist workflows the rule is about, it is the W05
      -- run for the same inquiry, and where no such run exists the key stays unresolved rather than
      -- being answered with this run''s own role.
      --
      -- This is what makes the rule able to FAIL: it fails exactly when a run''s accountable role
      -- has drifted from the frozen registry''s, which is the drift BR-049 exists to catch.
      if r.workflow_id = 'W05' then
        v_val := to_jsonb(r.accountable_role_id);
        v_src := 'phase_c_workflow_run.accountable_role_id of this inquiry''s own run';
      elsif v_found then
        select to_jsonb(r2.accountable_role_id) into v_val
          from public.phase_c_workflow_run r2
         where r2.workflow_id = 'W05'
           and r2.business_object_id = ('inquiry:' || v_row_id)
         order by r2.run_id desc limit 1;
        v_src := 'phase_c_workflow_run.accountable_role_id of the W05 run that owns this inquiry';
      end if;
    elsif v_k = 'monetary_state' then
      if v_found and v_rel like '%transactions' then
        select to_jsonb(t.fee_status) into v_val from public.transactions t
          where t.id::text = v_row_id limit 1;
        v_src := 'public.transactions.fee_status of the run''s own transaction';
      end if;

    elsif v_k = 'evidence_authority' then
      -- F13. THIS RESOLVED, AND RESOLVED TO SOMETHING THE RULE CANNOT RANK.
      --
      -- BR-029 is about RANK: lower-authority evidence may not silently overwrite higher, and the
      -- estate's ranking is public.mep_evidence_weight (alias, customer_text, document_extraction,
      -- scope_rule, structured_answer). This branch answered with the arrival CLASSIFICATION --
      -- "A NEW_WORK_REQUEST (system.task_engine) via dbtrigger:public.inquiries:trg_inquiry_received_a,
      -- activation ACTIVE" -- which is a true fact about how the run started and is not an evidence
      -- authority at all. Measured on every drive: 0 rows matched, so BR-029 refused for the whole
      -- estate, and it refused with a reason that read as though the authority were unranked rather
      -- than as though the resolver had answered a different question.
      --
      -- The correction is a REMOVAL plus a test: the classification is offered only if it actually
      -- appears in the ranking. When it does not, the key is UNRESOLVED, which is the honest state
      -- -- and which is what lets the Phase D fixture door supply a ranked authority, and what
      -- keeps BR-029 refusing in production where no such authority is named.
      if v_src_class is not null
         and exists (select 1 from public.mep_evidence_weight w
                      where w.weight_key = v_src_class or w.evidence_source = v_src_class
                         or w.source_authority = v_src_class) then
        v_val := to_jsonb(v_src_class);
        v_src := 'phase_c_source_cutover classification of the arrival that caused this run, confirmed present in the public.mep_evidence_weight ranking';
      elsif exists (select 1 from public.phase_d_object_record o
                     where o.object_id = 'document_extraction'
                       and o.payload->>'document_id' = coalesce(v_row_id,'')) then
        -- The run's own object carries a document extraction, and document_extraction IS a ranked
        -- evidence source. This is a read of what the run rests on, not a choice.
        v_val := to_jsonb('document_extraction'::text);
        v_src := 'public.mep_evidence_weight: the run''s own object carries a document extraction, which is a ranked evidence source';
      end if;

    elsif v_k = 'notify_email' then
      if v_found and v_row_own is not null then
        v_email := null;
        if v_owncol = 'customer_id' then
          select c.email into v_email from public.customers c where c.id::text = v_row_own limit 1;
        elsif v_owncol in ('supplier_id','lead_id') then
          select l.email into v_email from public.leads l where l.id::text = v_row_own limit 1;
        end if;
        if coalesce(btrim(coalesce(v_email,'')),'') <> '' then
          v_val := to_jsonb(v_email);
          v_src := format('the email of %s.%s, the owner of the run''s own object', v_rel, v_owncol);
        end if;
      end if;

    elsif v_k = 'evidence_refs' then
      -- E22. A CONDITION THE FIRST STEP OF A RUN COULD NEVER MEET.
      --
      -- This resolved evidence_refs from public.phase_d_effect_ledger for the run and nothing else.
      -- The FIRST step of a run has no predecessor, so it has no prior effect, so the key was
      -- unresolvable for it by construction — not sometimes, ever. BR-027 is bound to 59 steps and
      -- applies to 7 of the estate's first steps; six of those seven (the seventh is held by the
      -- capability boundary) were refused by a rule they had no way to satisfy. Measured 2026-08-20.
      --
      -- The fix is not to hand the key a placeholder. It is to notice that a first step DOES have
      -- evidence, and that the resolver was reading the wrong subject for it: what a first step
      -- rests on is THE ARRIVAL THAT OPENED THE RUN. That is a row — phase_c_workflow_run carries
      -- start_event, command_id and opened_at, and phase_c_source_cutover classifies the source
      -- component — so naming it is a read, not an invention.
      --
      -- THE ARRIVAL COUNTS ONLY FOR A STEP WITH NO PREDECESSOR, and that restriction is what keeps
      -- BR-027 able to fail. A later step must still show what the run has PRODUCED; if its
      -- predecessors produced nothing, it still gets nothing and BR-027 still refuses. Handing every
      -- call an automatic arrival reference would have turned a rule that refuses into a rule that
      -- cannot, which is the defect this file is fixing, in the other direction.
      select case when count(*) = 0 then null
                  else jsonb_agg(jsonb_build_object(
                         'effect_id', el.effect_id, 'step_id', el.step_id,
                         'effect_type', el.effect_type,
                         'result_reference', el.result_reference) order by el.effect_id) end
        into v_val
        from public.phase_d_effect_ledger el where el.run_id = sr.run_id;
      v_src := 'phase_d_effect_ledger for this run';

      if v_val is null
         and not exists (select 1 from public.phase_c_workflow_step_run pr
                          where pr.run_id = sr.run_id and pr.step_run_id < sr.step_run_id) then
        v_val := jsonb_build_array(jsonb_build_object(
          'kind',          'arrival',
          'run_id',        sr.run_id,
          'workflow_id',   r.workflow_id,
          'start_event',   nullif(btrim(coalesce(r.start_event,'')),''),
          'command_id',    r.command_id,
          'source_ref',    nullif(btrim(coalesce(v_src_ref,'')),''),
          'source_class',  v_src_class,
          'system_actor',  v_src_actor,
          'opened_at',     r.opened_at));
        v_src := 'the arrival that opened this run (phase_c_workflow_run.start_event/command_id '
              || 'plus its phase_c_source_cutover classification) — this step has no predecessor, '
              || 'so the arrival is the evidence it rests on';
      end if;

    elsif v_k = 'handoff_id' then
      -- D50. The handoff this step opens is a row of the frozen registry, not something a caller has
      -- to remember to pass. BR-008 was refusing for want of an identifier sitting in a table.
      select to_jsonb(hc.handoff_id) into v_val
        from public.phase_d_handoff_contract hc where hc.from_step_id = sr.step_id
       order by hc.handoff_id limit 1;
      v_src := 'phase_d_handoff_contract.handoff_id for the handoff this step opens';

    elsif v_k = 'sla_policy_id' then
      -- Likewise: the SLA policy of that handoff is recorded against it in the frozen registry.
      select to_jsonb(nullif(btrim(coalesce(h.sla_policy_id,'')),'')) into v_val
        from public.phase_b_handoff h where h.from_step_id = sr.step_id
       order by h.handoff_id limit 1;
      v_src := 'phase_b_handoff.sla_policy_id of the handoff this step opens';

    elsif v_k in ('packet','requested_action','source_version') then
      select case v_k
               when 'packet' then case when hc.packet_keys is null or cardinality(hc.packet_keys) = 0
                                       then null else to_jsonb(hc.packet_keys) end
               when 'requested_action' then to_jsonb(nullif(btrim(coalesce(hc.acceptance_criteria,'')),''))
               else to_jsonb(nullif(btrim(coalesce(hc.source_object_version_key,'')),'')) end
        into v_val
        from public.phase_d_handoff_contract hc where hc.from_step_id = sr.step_id limit 1;
      v_src := 'phase_d_handoff_contract for this step';

    elsif v_k = 'founder_authority_ref' then
      select l.command_id into v_cmd from public.founder_command_workflow_link l
        where l.run_id = sr.run_id limit 1;
      if v_cmd is null then v_cmd := r.command_id; end if;
      if v_cmd is not null then
        v_val := to_jsonb('founder_command:' || v_cmd::text);
        v_src := 'founder_command that started this run';
      end if;

    elsif v_k = 'run_id' then
      -- E11. This function loads sr and r in its first ten lines and then declared run_id
      -- unresolved, which refused GATE-008 on every step in the estate for want of a number the
      -- same function was already holding.
      v_val := to_jsonb(sr.run_id);
      v_src := 'phase_c_workflow_step_run.run_id of this step run';

    elsif v_k = 'actor_role_id' then
      -- The role ACCOUNTABLE for this step run, read from the kernel's own row. Not the caller's
      -- claim about who they are: this function is given a step_run_id and nothing else, and a
      -- context resolver that took an identity from its caller would be answering the question it
      -- was asked to check.
      v_val := to_jsonb(nullif(btrim(coalesce(sr.accountable_role_id,'')),''));
      v_src := 'phase_c_workflow_step_run.accountable_role_id';

    elsif v_k = 'reviewer_role_id' then
      -- The INDEPENDENT reviewer the frozen binding declares, and only that. 45 of the 47 review
      -- steps name none, and for those this stays unresolved so GATE-004 and GATE-021 refuse —
      -- which is the gate working. Choosing a reviewer here would be fn_pick_reviewer returning the
      -- department head 182 times, one layer up.
      v_val := to_jsonb(nullif(btrim(coalesce(b.independent_reviewer_role_id,'')),''));
      v_src := 'phase_d_handler_binding.independent_reviewer_role_id, declared not chosen';

    elsif v_k = 'step_id' then
      -- MENTIONED IN THIS FUNCTION AND NOT BRANCHED, which is why the first measurement of this
      -- defect missed it. sr.step_id appears in the return object at the bottom, so a grep for
      -- 'step_id' finds it and a reader concludes the key resolves. It did not. A mention is not a
      -- branch — the same lens that cost the 19 Aug audit its central premise, applied here to the
      -- very file that was measuring it.
      v_val := to_jsonb(sr.step_id);
      v_src := 'phase_c_workflow_step_run.step_id';

    elsif v_k = 'step_run_id' then
      v_val := to_jsonb(p_step_run_id);
      v_src := 'the step_run_id this function was called with';

    elsif v_k = 'source_ref' then
      -- The arrival that caused this run, already computed into v_src_ref from kernel_trigger_inbox
      -- at the top of this function. Unresolved when no arrival is recorded, which is a fact about
      -- the run rather than a gap in this resolver.
      v_val := to_jsonb(nullif(btrim(coalesce(v_src_ref,'')),''));
      v_src := 'kernel_trigger_inbox.source_system for this run';

    else
      -- 40 of the 71 declared context keys still land here, and that is correct: artifact_sha256,
      -- terms_hash, legal_review_ref, denominator, formula, outcome_metric and the rest are facts a
      -- CALLER produces at runtime, not facts this estate holds. They stay unresolved and their
      -- rules and gates refuse, which is the contract working.
      -- exception_authority_ref is here on purpose too: BR-043 applies only when the call names a
      -- policy exception, and inventing an authority reference would be the placeholder defect the
      -- D42 comment above already refused once for route_state.
      v_val := null; v_src := null;
    end if;


    -- F11. THE FIXTURE DOOR, AND ONLY AFTER EVERY REAL SOURCE HAS BEEN TRIED.
    --
    -- The founder's section B: "A deterministic handler must not invent business content. The
    -- scenario catalogue supplies explicit test values... The handler receives the fixture as
    -- input. The handler must not generate the fixture itself."
    --
    -- This is where the fixture becomes an input. It runs in the RESOLVER, which is called by
    -- fn_phase_d_dispatch_step before fn_phase_d_handler_execute is entered, so the handler is
    -- handed a value and never reaches for one. And it runs LAST: a key a real row can answer is
    -- answered by that row, and the fixture never shadows a fact.
    --
    -- fn_phase_d_fixture_input returns NO ROW unless fn_phase_d_fixture_context() verifies an hmac
    -- over the current txid keyed by a secret no role can read. In production there is no such
    -- context, so this block resolves nothing, the key stays unresolved, and its rule or gate
    -- refuses exactly as it did before this file existed.
    if v_val is null or v_val = 'null'::jsonb
       or (jsonb_typeof(v_val) = 'string' and btrim(coalesce(v_val #>> '{}','')) = '') then
      select fi.value, fi.provenance || format(' [fixture %s v%s %s]', fi.fixture_id,
                                               fi.fixture_version, left(fi.checksum, 12))
        into v_fx_val, v_fx_src
        from public.fn_phase_d_fixture_input(p_step_run_id, 'CONTEXT_KEY', v_k) fi;
      if v_fx_val is not null then
        v_ctx := v_ctx || jsonb_build_object(v_k, v_fx_val);
        v_prov := v_prov || jsonb_build_object(v_k, v_fx_src);
        v_fx_val := null; v_fx_src := null;
        continue;
      end if;
    end if;
    if v_val is null or v_val = 'null'::jsonb
       or (jsonb_typeof(v_val) = 'string' and btrim(coalesce(v_val #>> '{}','')) = '') then
      v_unres := v_unres || v_k;
    else
      v_ctx  := v_ctx  || jsonb_build_object(v_k, v_val);
      v_prov := v_prov || jsonb_build_object(v_k, v_src);
    end if;
  end loop;

  return jsonb_build_object(
    'step_run_id', p_step_run_id, 'step_id', sr.step_id,
    'declared_keys', to_jsonb(v_keys),
    'context', v_ctx, 'provenance', v_prov, 'unresolved', to_jsonb(v_unres),
    'arrival', jsonb_build_object('source_ref', v_src_ref, 'source_kind', v_src_kind,
                                  'source_class', v_src_class, 'activation', v_src_act),
    'business_object', jsonb_build_object(
      'object_id', v_obj, 'object_key', v_boid, 'relation', v_rel, 'key_column', v_keycol,
      'owner_column', v_owncol, 'row_found', v_found,
      -- E25. The two facts fn_phase_d_effect_produce demands of its caller, reported here because
      -- this is the routine that already resolved them and the dispatch had no way to know them.
      'key_is_prefixed', v_key_prefixed,
      'row_owner_ref', v_row_own,
      'ownership_scope', (select ob.ownership_scope
                            from public.phase_d_business_object_binding ob
                           where ob.object_id = v_obj)));
end
$function$
;

CREATE OR REPLACE FUNCTION public.fn_phase_d_dispatch_step(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  sr public.phase_c_workflow_step_run%rowtype;
  v_step_run bigint := nullif(p_input->>'step_run_id','')::bigint;
  v_actor    text   := nullif(btrim(coalesce(p_input->>'actor_role_id','')),'');
  v_kind     text   := coalesce(nullif(btrim(p_input->>'opened_by_kind'),''),'(unstated)');
  v_ref      text   := coalesce(nullif(btrim(p_input->>'opened_by_ref'),''),'(unstated)');
  v_idem     text   := coalesce(nullif(btrim(p_input->>'idempotency_key'),''),'');
  v_wf       text;
  v_on       text;
  v_depth    int;
  v_in       jsonb;
  v_cx       jsonb;
  v_res      jsonb;
  v_unres    text[];
  v_err      text;
  v_bkey     text;   -- E25
  v_owner    text;   -- E25
  v_scope    text;   -- E25
  v_code     text;
begin
  if v_step_run is null or v_actor is null then
    raise exception 'fn_phase_d_dispatch_step: step_run_id and actor_role_id are required (got %, %)',
      coalesce(v_step_run::text,'(null)'), coalesce(v_actor,'(null)') using errcode = '22023';
  end if;

  select * into sr from public.phase_c_workflow_step_run where step_run_id = v_step_run;
  if not found then
    raise exception 'fn_phase_d_dispatch_step: no step run %', v_step_run using errcode = '23503';
  end if;

  if not exists (select 1 from public.phase_d_handler_binding hb where hb.step_id = sr.step_id)
     or not exists (select 1 from public.phase_d_step_effect se where se.step_id = sr.step_id) then
    return jsonb_build_object('dispatched', false, 'outcome', 'NO_BINDING', 'step_id', sr.step_id);
  end if;

  select b2.workflow_id into v_wf from public.phase_d_handler_binding b2 where b2.step_id = sr.step_id;
  if v_idem = '' then v_idem := 'kernel|' || sr.run_id || '|' || sr.step_id; end if;

  v_on    := lower(coalesce(nullif(btrim(current_setting('app.phase_d_dispatch', true)),''), 'on'));
  v_depth := coalesce(nullif(btrim(current_setting('app.phase_d_dispatch_depth', true)),'')::int, 0);

  if v_on = 'off' then
    insert into public.phase_d_dispatch
      (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
       outcome, refusal_code, reason, dispatch_depth)
    values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
            'DISPATCH_OFF', 'pd_dispatch_off',
            'app.phase_d_dispatch is off for this transaction', v_depth);
    return jsonb_build_object('dispatched', false, 'outcome', 'DISPATCH_OFF');
  end if;

  if v_depth >= 64 then
    insert into public.phase_d_dispatch
      (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
       outcome, refusal_code, reason, dispatch_depth)
    values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
            'DEPTH_LIMIT', 'pd_dispatch_depth_limit',
            format('dispatch depth %s reached at step %s', v_depth, sr.step_id), v_depth);
    return jsonb_build_object('dispatched', false, 'outcome', 'DEPTH_LIMIT', 'depth', v_depth);
  end if;

  perform set_config('app.phase_d_dispatch_depth', (v_depth + 1)::text, true);

  begin
    v_in := public.fn_phase_d_step_inputs(v_step_run);
    select array_agg(x) into v_unres
      from jsonb_array_elements_text(coalesce(v_in->'unresolved','[]'::jsonb)) x;
    v_unres := coalesce(v_unres, '{}');

    if cardinality(v_unres) > 0 then
      insert into public.phase_d_dispatch
        (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
         outcome, refusal_code, reason, unresolved_keys, inputs_provenance, dispatch_depth)
      values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
              'INPUTS_UNRESOLVED', 'pd_input_unresolved',
              format('%s of the %s declared input keys resolve from no real source: %s',
                     cardinality(v_unres),
                     jsonb_array_length(coalesce(v_in->'declared_keys','[]'::jsonb)),
                     array_to_string(v_unres, ', ')),
              v_unres, coalesce(v_in->'provenance','{}'::jsonb), v_depth);
      perform set_config('app.phase_d_dispatch_depth', v_depth::text, true);
      return jsonb_build_object('dispatched', false, 'outcome', 'INPUTS_UNRESOLVED',
                                'unresolved', to_jsonb(v_unres));
    end if;

    -- D37. The same treatment for what the RULES and GATES read. Unresolved keys are not supplied,
    -- so a rule that needs one refuses instead of passing on a placeholder.
    v_cx := public.fn_phase_d_step_context(v_step_run);

    -- E25. THE DISPATCH WITHHELD THE TWO FIELDS THE WRITE SERVICE REQUIRES, AND IT KNEW BOTH.
    --
    -- fn_phase_d_effect_produce raises pd_effect_owner_or_key_missing for DOMAIN_MUTATION and
    -- VERSIONED_ARTIFACT unless the CALL names business_key and owner_ref. That is the right
    -- behaviour for the routine -- a record written under an owner it chose for itself would be the
    -- auto-vivified account defect in a new place -- but the kernel dispatch passed neither and had
    -- no branch that could. The R3 independent acceptance measured the consequence: 125 of 257 steps
    -- structurally excluded before any rule was consulted, and the only two steps that executed were
    -- KERNEL_ONLY_TRANSITION ones that write no business object at all.
    --
    -- Neither field is invented here. Both are READ, and where they cannot be read the step still
    -- refuses:
    --
    --   owner_ref  COMPANY-scoped object -> phase_c_workflow_step_run.accountable_role_id, which is
    --              the frozen registry's own answer to who is accountable for this step. Not chosen.
    --              CUSTOMER- or SUPPLIER-scoped -> the owner column of the run's OWN business row,
    --              and null when no such row exists. A customer is never conjured to own a record.
    --
    --   business_key  the run's business_object_id, and ONLY when it actually carried the
    --              '<object>:' prefix of the object this step writes -- 'inquiry:<uuid>' is an
    --              identity, 'outbox:195' and a probe label are not. fn_phase_d_step_context reports
    --              key_is_prefixed for exactly this decision.
    --
    -- jsonb_strip_nulls means an underivable field is ABSENT rather than null, so the write service
    -- sees precisely what it saw before and refuses in precisely the same way.
    v_scope := v_cx#>>'{business_object,ownership_scope}';
    if coalesce((v_cx#>>'{business_object,key_is_prefixed}')::boolean, false) then
      v_bkey := nullif(btrim(coalesce(v_cx#>>'{business_object,object_key}','')),'');
    end if;

    -- F13. A STEP THAT WRITES AN OBJECT OTHER THAN ITS RUN'S PRIMARY HAD NO KEY IT COULD EVER GET.
    --
    -- E25 derives business_key from the run's business_object_id and only when it carries the
    -- '<object>:' prefix of the object THIS STEP writes -- which is right, and which means a step
    -- like W01-S07 (run is company_objective:..., step writes the initiative object) can never be prefixed
    -- and refuses with pd_effect_owner_or_key_missing on every drive. That is correct in
    -- production: nothing has told the estate which initiative this is.
    --
    -- Inside a verified Phase D fixture run there IS an answer, and it is a read rather than an
    -- invention: the scenario either already created a record of that object -- in which case this
    -- step mutates THAT record -- or it did not, in which case the key is derived deterministically
    -- from (fixture run, object, run), so the same scenario driven twice produces the same key and
    -- a replay collides with itself instead of creating a second record.
    if v_bkey is null and public.fn_phase_d_fixture_context() is not null then
      select coalesce(sc.contributed_value, sc.business_key) into v_bkey
        from public.phase_d_scenario_record sc
       where sc.fixture_run_id = public.fn_phase_d_fixture_context()
         and sc.object_id = (v_cx#>>'{business_object,object_id}')
       order by sc.scenario_record_id limit 1;
      if v_bkey is null and (v_cx#>>'{business_object,object_id}') is not null then
        v_bkey := md5(format('phase_d_fixture:%s:%s:%s',
                             public.fn_phase_d_fixture_context(),
                             v_cx#>>'{business_object,object_id}', sr.run_id))::uuid::text;
      end if;
    end if;
    v_owner := nullif(btrim(coalesce(v_cx#>>'{business_object,row_owner_ref}','')),'');
    if v_owner is null and coalesce(v_scope,'COMPANY') = 'COMPANY' then
      v_owner := nullif(btrim(coalesce(sr.accountable_role_id,'')),'');
    end if;

    v_res := public.fn_phase_d_handler_execute(jsonb_build_object(
      'step_run_id',       v_step_run,
      'actor_role_id',     v_actor,
      'idempotency_key',   v_idem || '|phase_d',
      'inputs',            v_in->'inputs',
      'context',           v_cx->'context',
      'gate_evidence',     v_cx->'context',
      'execution_context', 'production',
      'correlation_id',    p_input->>'correlation_id',
      'causation_id',      'kernel_dispatch:' || v_kind || ':' || v_ref)
      || jsonb_strip_nulls(jsonb_build_object(
      'business_key',      v_bkey,
      'owner_ref',         v_owner)));

    insert into public.phase_d_dispatch
      (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
       outcome, inputs_provenance, effect_id, dispatch_depth)
    values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
            'EXECUTED',
            coalesce(v_in->'provenance','{}'::jsonb) || coalesce(v_cx->'provenance','{}'::jsonb),
            nullif(v_res#>>'{phase_d,business_effect,effect_id}','')::bigint, v_depth);

    perform set_config('app.phase_d_dispatch_depth', v_depth::text, true);
    return jsonb_build_object('dispatched', true, 'outcome', 'EXECUTED',
             'handler_id', v_res#>>'{phase_d,handler_id}',
             'effect_id',  v_res#>'{phase_d,business_effect,effect_id}');

  exception
    when others then
      v_err  := SQLERRM;
      -- E26. AN UNCLASSIFIED REFUSAL IS AN INSTRUMENT GAP, NOT A CATEGORY.
      -- Once E25 stopped the dispatch withholding business_key and owner_ref, two steps reached the
      -- real business write for the first time and failed on a NOT NULL column of the target
      -- relation -- public.opportunity.kind. That is a genuine and interesting refusal: the payload
      -- carries an IDENTITY for the record but not its CONTENT, and the content of an opportunity is
      -- a judgement no deterministic handler can make while the reasoning capability is held. It
      -- deserves to be named. Recorded as pd_unclassified it looked like a bug in the dispatch.
      --
      -- A raised Phase D or kernel code still wins; this only names what used to fall through.
      v_code := coalesce((regexp_match(v_err, '\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\)'))[1],
        case SQLSTATE
          when '23502' then 'pd_effect_payload_incomplete'   -- not-null column the payload did not fill
          when '23503' then 'pd_effect_reference_unresolved'  -- foreign key the payload pointed nowhere
          when '23505' then 'pd_effect_identity_collision'    -- unique key already taken
          when '23514' then 'pd_effect_check_violated'        -- a check constraint on the target relation
          when '22P02' then 'pd_effect_value_malformed'       -- a value the target column cannot parse
          else 'pd_unclassified' end);
      insert into public.phase_d_dispatch
        (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
         outcome, refusal_code, sqlstate_code, reason, unresolved_keys, inputs_provenance,
         dispatch_depth)
      values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
              -- E19. This column used to say REFUSED whether the handler had judged the evidence
              -- and rejected it, or had never been given any. Those are different events, and the
              -- 2026-08-20 acceptance audit read the second as the first. Both are refusals and
              -- neither is a pass; only the name differs.
              case when v_code = 'pd_evidence_absent' then 'REFUSED_EVIDENCE_ABSENT' else 'REFUSED' end,
              v_code, SQLSTATE, left(v_err, 1000),
              coalesce((select array_agg(x) from jsonb_array_elements_text(
                          coalesce(v_cx->'unresolved','[]'::jsonb)) x), '{}'),
              coalesce(v_cx->'provenance','{}'::jsonb), v_depth);
      perform set_config('app.phase_d_dispatch_depth', v_depth::text, true);
      return jsonb_build_object('dispatched', false,
                                'outcome', case when v_code = 'pd_evidence_absent'
                                                then 'REFUSED_EVIDENCE_ABSENT' else 'REFUSED' end,
                                'refusal_code', v_code, 'sqlstate', SQLSTATE);
  end;
end
$function$
;

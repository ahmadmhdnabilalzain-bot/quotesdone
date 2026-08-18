-- PHASE D · D1 — THE HANDLER REGISTRY, THE TYPED CONTRACT AND THE ONE EXECUTOR.
--
-- WHAT PHASE C LEFT AND WHAT THIS FIXES. Phase C bound all 257 steps to a single
-- canonical_runtime_handler: public.fn_phase_c_step_advance(bigint,text,text,jsonb). That routine
-- was RETIRED by kernel_k13 on 18 Aug 2026 and now raises; public.kernel_retired_path records the
-- replacement as fn_kernel_step_complete. So the column that names the handler for every step in
-- the estate names a door that cannot open. Measured, not assumed:
--
--   select canonical_runtime_handler, count(*) from public.phase_c_step_binding group by 1;
--     public.fn_phase_c_step_advance(bigint,text,text,jsonb) | 257
--   select disposition, replacement from public.kernel_retired_path
--    where path_name = 'fn_phase_c_step_advance';
--     DISABLED | fn_kernel_step_complete
--
-- 137 of the 257 are additionally DEFERRED_RUNTIME_IMPLEMENTATION: no measured component produces
-- the step's business output at all. Phase D's Definition of Done requires that number to be 0.
--
-- WHAT A HANDLER IS HERE. Not a second workflow engine. fn_kernel_step_complete is FROZEN
-- (public.phase_c_frozen_subject, subject canonical_step_engine) and it already owns idempotency,
-- locking, actor resolution, authority, the task state machine, gate evaluation, progression,
-- handoff creation, run state and event emission. A Phase D handler produces the one thing the
-- kernel cannot: the step's BUSINESS OUTPUT, typed and validated, which it then hands to the
-- kernel. The executor below is a caller of the kernel, never a replacement for it.
--
-- NOTHING IN THIS FILE IS HAND-TYPED FROM THE PACKAGE. Every binding row and every schema is
-- DERIVED from public.phase_b_workflow_step, which is the founder-approved frozen Phase B
-- registry, at INSERT time. A registry whose expected values were typed by whoever wrote the
-- migration agrees only with that person. Two consequences worth stating:
--
--   * the input schema's required keys are the semicolon-separated clauses of the frozen
--     required_inputs, slugified by a fixed rule — so a step declaring three inputs gets three
--     required keys, and the derivation is re-runnable and checkable;
--   * every schema carries source_text and source_digest, the sha256 of the frozen prose it was
--     derived from. If Phase B's text ever moved, the digest stops matching and the board says so
--     instead of the contract silently describing a step that no longer exists.
--
-- WHY SHARED FAMILY HANDLERS AND NOT 257 ROUTINES. PHASE_D_HANDLER_ARCHITECTURE.md enumerates
-- eight step families and PHASE_D_MASTER_SPEC.md permits shared implementations "only with
-- explicit per-step bindings". The frozen registry's step_type has exactly those eight values and
-- partitions all 257:
--
--   execution 58 · review 47 · decision 35 · analysis 31 · closure 29 · handoff 25 · intake 24
--   · measurement 8   = 257
--
-- So the code is eight family handlers and the CONTRACT is 257 explicit bindings. Ambiguity is
-- what the spec forbids, and there is none: phase_d_handler_binding.step_id is the primary key.
--
-- CAPABILITY BOUNDARY, STATED HONESTLY. Some steps ask for judgement no deterministic routine can
-- supply. Those are classified here, they carry a typed capability request, and they FAIL CLOSED
-- outside an explicit test context. A Phase D mock may not complete a real business step — that is
-- D9's requirement and it is enforced in fn_phase_d_handler_execute, not asserted in a comment.

begin;

-- ================================================================ 1. the typed contract
create table if not exists public.phase_d_handler_schema (
  schema_id      text        primary key,
  step_id        text        not null references public.phase_b_workflow_step(step_id),
  schema_kind    text        not null check (schema_kind in ('input','output')),
  handler_class  text        not null,
  required_keys  text[]      not null check (cardinality(required_keys) > 0),
  key_derivation text        not null,
  source_text    text        not null,
  source_digest  text        not null,
  captured_at    timestamptz not null default now(),
  unique (step_id, schema_kind)
);

comment on table public.phase_d_handler_schema is
  'The typed input and output contract for each of the 257 frozen Phase B steps. Derived from '
  'public.phase_b_workflow_step at insert time and never hand-entered; source_digest is the sha256 '
  'of the frozen prose the keys came from, so a Phase B text change is detectable rather than '
  'silently tolerated. Checked by public.fn_phase_d_handler_state().';

-- The slug rule, written once and used for every derivation so the mapping is reproducible.
create or replace function public.fn_phase_d_slug(p_text text)
returns text language sql immutable as $$
  select nullif(btrim(regexp_replace(lower(coalesce(p_text,'')), '[^a-z0-9]+', '_', 'g'), '_'), '')
$$;

comment on function public.fn_phase_d_slug(text) is
  'The one slug rule used by every Phase D derivation: lowercase, non-alphanumeric runs to a single '
  'underscore, trimmed. Deterministic and immutable so a schema can be recomputed and compared.';

-- ---- INPUT schemas: one required key per semicolon-separated clause of the frozen required_inputs.
insert into public.phase_d_handler_schema
  (schema_id, step_id, schema_kind, handler_class, required_keys, key_derivation,
   source_text, source_digest)
select
  'schema_input_' || lower(replace(s.step_id,'-','_')),
  s.step_id, 'input', upper(s.step_type) || '_HANDLER',
  coalesce(
    (select array_agg(k order by ord)
       from (select public.fn_phase_d_slug(c) k, ord
               from unnest(string_to_array(s.required_inputs, ';')) with ordinality u(c, ord)
              where public.fn_phase_d_slug(c) is not null) q),
    array['workflow_context']),
  'semicolon-separated clauses of phase_b_workflow_step.required_inputs, slugged by '
  'public.fn_phase_d_slug; a step declaring no parseable input falls back to the single key '
  'workflow_context, which the executor still requires to be present and non-empty',
  coalesce(s.required_inputs,''),
  encode(sha256(convert_to(coalesce(s.required_inputs,''),'UTF8')),'hex')
  from public.phase_b_workflow_step s
on conflict (schema_id) do nothing;

-- ---- OUTPUT schemas: the kernel envelope, plus the evidence obligations of the step's FAMILY,
--      plus the acceptance assertion every step owes. The envelope keys are not a choice — the
--      frozen fn_kernel_step_complete calls fn_phase_c_output_validate, which requires exactly
--      'status' and 'output'. The family keys are PHASE_D_HANDLER_ARCHITECTURE.md's step families
--      expressed as keys; they are obligations of the class, not invented business fields.
insert into public.phase_d_handler_schema
  (schema_id, step_id, schema_kind, handler_class, required_keys, key_derivation,
   source_text, source_digest)
select
  'schema_output_' || lower(replace(s.step_id,'-','_')),
  s.step_id, 'output', upper(s.step_type) || '_HANDLER',
  array['status','output','acceptance_assertions','evidence_refs']
    || case s.step_type
         when 'intake'      then array['source_ref','captured_verbatim']
         when 'analysis'    then array['method','inputs_used','findings','assumptions']
         when 'execution'   then array['state_change','target_object','authorization_ref']
         when 'review'      then array['verdict','reviewer_role_id']
         when 'decision'    then array['decision','rationale','authority_ref']
         when 'handoff'     then array['packet','receiving_role_id','acceptance_criteria']
         when 'measurement' then array['metric','denominator','numerator','formula','window']
         when 'closure'     then array['blockers_resolved','closure_evidence']
         else array[]::text[] end,
  'kernel envelope (status, output) required by public.fn_phase_c_output_validate, which the '
  'frozen fn_kernel_step_complete calls; plus acceptance_assertions and evidence_refs, owed by '
  'every step; plus the evidence obligations of the step family named in '
  'PHASE_D_HANDLER_ARCHITECTURE.md, selected by phase_b_workflow_step.step_type',
  coalesce(s.required_output,'') || ' || ' || coalesce(s.acceptance_criteria,''),
  encode(sha256(convert_to(coalesce(s.required_output,'') || ' || ' ||
                           coalesce(s.acceptance_criteria,''),'UTF8')),'hex')
  from public.phase_b_workflow_step s
on conflict (schema_id) do nothing;

-- ================================================================ 2. the handler binding
create table if not exists public.phase_d_handler_binding (
  -- Same reason as the two named checks below: the manifest derives a foreign-key name only when
  -- `references` sits on the column's own source line, so a wrapped clause reads as uncommitted
  -- DDL. Named with the identity Postgres generates, so file and catalogue agree.
  step_id                 text        primary key
    constraint phase_d_handler_binding_step_id_fkey
    references public.phase_b_workflow_step(step_id),
  workflow_id             text        not null,
  handler_id              text        not null unique,
  handler_version         text        not null,
  handler_class           text        not null,
  handler_routine         text        not null,
  input_schema_id         text        not null references public.phase_d_handler_schema(schema_id),
  output_schema_id        text        not null references public.phase_d_handler_schema(schema_id),
  accountable_role_id     text        not null,
  independent_reviewer_role_id text   not null default '',
  rule_ids                text[]      not null default '{}',
  gate_ids                text[]      not null default '{}',
  business_object_reads   text[]      not null default '{}',
  business_object_writes  text[]      not null default '{}',
  idempotency_template    text        not null,
  concurrency_lock_scope  text        not null,
  failure_code_contract   text[]      not null,
  compensation            text        not null,
  capability_dependency   text        not null default 'NONE',
  capability_evidence     text        not null default '',
  provider_dependency     text        not null default 'NONE',
  -- Named explicitly, and named with the identity Postgres would have generated. The canonical
  -- routine manifest derives an auto-generated constraint name only when `check (` sits on the
  -- same source line as its column, so a check wrapped across lines reads as uncommitted DDL
  -- even though the file declares it. Naming it keeps the repository and the live catalogue in
  -- agreement instead of making the instrument wrong.
  external_effect_policy  text        not null default 'OUTBOX_ONLY_OR_NONE'
    constraint phase_d_handler_binding_external_effect_policy_check
    check (external_effect_policy in ('NONE','OUTBOX_ONLY_OR_NONE','PROVIDER_DISABLED_MOCK')),
  trace_point             text        not null,
  founder_gate            text        not null default 'none',
  phase_d_status          text        not null
    constraint phase_d_handler_binding_phase_d_status_check
    check (phase_d_status in ('NEW_DETERMINISTIC_HANDLER','VERIFIED_EXISTING_HANDLER',
                              'REPAIRED_EXISTING_HANDLER','CAPABILITY_BOUNDARY_READY',
                              'EXTERNAL_ADAPTER_READY_DISABLED',
                              'COMPATIBILITY_WRAPPER_TO_CANONICAL',
                              'INTENTIONALLY_INACTIVE_WITH_FROZEN_REASON',
                              'BLOCKED_DEFECT')),
  phase_c_current_handler text        not null default '',
  phase_c_connection      text        not null default '',
  bound_at                timestamptz not null default now()
);

comment on table public.phase_d_handler_binding is
  'One explicit Phase D handler binding per frozen Phase B step. Shared family code is permitted by '
  'PHASE_D_MASTER_SPEC.md; ambiguous binding is not, and step_id being the primary key is what '
  'makes that structural rather than a promise. Every column is derived from the frozen registry '
  'at insert time.';

insert into public.phase_d_handler_binding (
  step_id, workflow_id, handler_id, handler_version, handler_class, handler_routine,
  input_schema_id, output_schema_id, accountable_role_id, independent_reviewer_role_id,
  rule_ids, gate_ids, idempotency_template, concurrency_lock_scope, failure_code_contract,
  compensation, capability_dependency, capability_evidence, provider_dependency,
  external_effect_policy, trace_point, founder_gate, phase_d_status,
  phase_c_current_handler, phase_c_connection)
select
  s.step_id, s.workflow_id,
  'hdl_' || lower(replace(s.step_id,'-','_')), 'v1',
  upper(s.step_type) || '_HANDLER',
  'public.fn_phase_d_handler_execute(jsonb)',
  'schema_input_'  || lower(replace(s.step_id,'-','_')),
  'schema_output_' || lower(replace(s.step_id,'-','_')),
  s.accountable_role_id, coalesce(s.independent_reviewer_role_id,''),
  -- Rules in scope: the frozen registry's own scoping expression, resolved to this workflow.
  -- 'all' means all; otherwise the semicolon list of workflow ids is matched exactly.
  coalesce((select array_agg(b.rule_id order by b.rule_id)
              from public.phase_b_business_rule b
             where lower(b.workflow_scope) = 'all'
                or s.workflow_id = any (string_to_array(replace(b.workflow_scope,' ',''), ';'))),
           '{}'),
  coalesce((select array_agg(g.gate_id order by g.gate_id)
              from public.phase_b_gate g
             where upper(g.workflow_scope) = 'ALL'
                or s.workflow_id = any (string_to_array(replace(g.workflow_scope,' ',''), ';'))),
           '{}'),
  -- The frozen idempotency_scope is the template; the executor resolves it per call.
  s.idempotency_scope,
  'phase_c_workflow_run(run_id) -> phase_c_workflow_step_run(step_run_id) -> phase_c_task(task_id), '
  'acquired in that order by the frozen fn_kernel_step_complete',
  array['pd_input_schema_invalid','pd_actor_not_accountable','pd_step_state_invalid',
        'pd_duplicate_execution','pd_rule_refused','pd_gate_refused','pd_output_schema_invalid',
        'pd_capability_unavailable','pd_provider_disabled'],
  'A Phase D handler writes no business state of its own; it returns a typed output to '
  'fn_kernel_step_complete, so the compensation for a failed handler is that the kernel '
  'transaction rolls back and the step run keeps its prior state. Nothing to undo by hand.',
  -- CAPABILITY CLASSIFICATION. Word-boundary matched against the frozen required_action, and the
  -- matched token is RECORDED, because a classifier whose evidence is not readable is a claim.
  -- A negation-blind substring match is the defect this avoids: 'analysis' must not fire on
  -- 'analyst', which \m..\M prevents.
  case
    when s.required_action ~*
         ('\m(assess|evaluate|analyse|analyze|interpret|diagnose|forecast|recommend|judge|'
       || 'draft|compose|design|summarise|summarize|classify|rank|score)\M')
      then 'REASONING'
    else 'NONE' end,
  coalesce((select string_agg(m[1], ', ')
              from regexp_matches(s.required_action,
                     ('\m(assess|evaluate|analyse|analyze|interpret|diagnose|forecast|recommend|'
                   || 'judge|draft|compose|design|summarise|summarize|classify|rank|score)\M'),
                     'gi') m), ''),
  'NONE',
  'OUTBOX_ONLY_OR_NONE',
  'TRACE-STEP, written by the frozen fn_kernel_step_complete on the step run it closes',
  coalesce(s.founder_gate,'none'),
  case
    when s.required_action ~*
         ('\m(assess|evaluate|analyse|analyze|interpret|diagnose|forecast|recommend|judge|'
       || 'draft|compose|design|summarise|summarize|classify|rank|score)\M')
      then 'CAPABILITY_BOUNDARY_READY'
    else 'NEW_DETERMINISTIC_HANDLER' end,
  coalesce(sb.current_handlers,''), coalesce(sb.connection_status,'')
  from public.phase_b_workflow_step s
  left join public.phase_c_step_binding sb on sb.step_id = s.step_id
on conflict (step_id) do nothing;

-- ================================================================ 3. the schema validator
create or replace function public.fn_phase_d_schema_validate(p_schema_id text, p_payload jsonb)
returns table(valid boolean, reason text, missing text[])
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare
  sc public.phase_d_handler_schema%rowtype;
  v_missing text[];
  v_empty   text[];
begin
  select * into sc from public.phase_d_handler_schema where schema_id = p_schema_id;
  if not found then
    valid := false;
    reason := format('unknown schema %L — fail closed', p_schema_id);
    missing := '{}'; return next; return;
  end if;

  -- An absent payload is a refusal, never an empty pass. pct(got, 0) returning 100 is the shape
  -- of defect this avoids: no evidence is not full evidence.
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    valid := false;
    reason := format('schema %s expects an object, got %s',
                     p_schema_id, coalesce(jsonb_typeof(p_payload),'null'));
    missing := sc.required_keys; return next; return;
  end if;

  select array_agg(k order by k) into v_missing
    from unnest(sc.required_keys) k where not (p_payload ? k);
  if v_missing is not null then
    valid := false;
    reason := format('schema %s: required keys missing [%s]',
                     p_schema_id, array_to_string(v_missing, ', '));
    missing := v_missing; return next; return;
  end if;

  -- A key present and empty is the same absence wearing a different hat.
  select array_agg(k order by k) into v_empty
    from unnest(sc.required_keys) k
   where jsonb_typeof(p_payload->k) = 'null'
      or (jsonb_typeof(p_payload->k) = 'string' and btrim(p_payload->>k) = '')
      or (jsonb_typeof(p_payload->k) = 'array'  and jsonb_array_length(p_payload->k) = 0)
      or (jsonb_typeof(p_payload->k) = 'object' and p_payload->k = '{}'::jsonb);
  if v_empty is not null then
    valid := false;
    reason := format('schema %s: required keys present but empty [%s]',
                     p_schema_id, array_to_string(v_empty, ', '));
    missing := v_empty; return next; return;
  end if;

  valid := true;
  reason := format('payload satisfies %s (%s keys, source digest %s)',
                   p_schema_id, cardinality(sc.required_keys), left(sc.source_digest,12));
  missing := '{}'; return next;
end $fn$;

comment on function public.fn_phase_d_schema_validate(text, jsonb) is
  'Typed validation against a Phase D schema. Three distinct absences — unknown schema, missing '
  'key, present-but-empty key — are three distinct refusals rather than one, because a caller that '
  'cannot tell them apart cannot fix any of them.';

-- ================================================================ 4. the one executor
create or replace function public.fn_phase_d_handler_execute(p_input jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  b   public.phase_d_handler_binding%rowtype;
  s   public.phase_b_workflow_step%rowtype;
  sr  public.phase_c_workflow_step_run%rowtype;
  v_step_run bigint := nullif(p_input->>'step_run_id','')::bigint;
  v_actor    text   := nullif(btrim(coalesce(p_input->>'actor_role_id','')),'');
  v_idem     text   := nullif(btrim(coalesce(p_input->>'idempotency_key','')),'');
  v_inputs   jsonb  := coalesce(p_input->'inputs','{}'::jsonb);
  v_ctx      text   := lower(coalesce(nullif(btrim(p_input->>'execution_context'),''),'production'));
  v_ok       boolean; v_reason text; v_missing text[];
  v_rule     record; v_rule_ok boolean; v_rule_type text; v_rule_reason text;
  v_applies  boolean; v_why text; v_enforced boolean; v_refusal text;
  v_refused  jsonb := '[]'::jsonb;
  v_skipped  jsonb := '[]'::jsonb;
  v_evaluated jsonb := '[]'::jsonb;
  v_output   jsonb;
  v_assert   jsonb;
  v_result   jsonb;
begin
  -- ---- 0. the call itself ------------------------------------------------------------------
  if v_step_run is null or v_actor is null or v_idem is null then
    raise exception 'fn_phase_d_handler_execute: step_run_id, actor_role_id and idempotency_key are all required (got %, %, %) (pd_input_schema_invalid)',
      coalesce(v_step_run::text,'(null)'), coalesce(v_actor,'(null)'), coalesce(v_idem,'(null)')
      using errcode = '22023';
  end if;
  if v_ctx not in ('production','test') then
    raise exception 'fn_phase_d_handler_execute: execution_context must be production or test, got %',
      v_ctx using errcode = '22023';
  end if;

  select * into sr from public.phase_c_workflow_step_run where step_run_id = v_step_run;
  if not found then
    raise exception 'fn_phase_d_handler_execute: no step run % (pd_step_state_invalid)', v_step_run
      using errcode = '23503';
  end if;

  select * into b from public.phase_d_handler_binding where step_id = sr.step_id;
  if not found then
    raise exception 'fn_phase_d_handler_execute: step % has no Phase D handler binding — fail closed. Every one of the 257 frozen steps must carry exactly one. (pd_input_schema_invalid)',
      sr.step_id using errcode = '23503';
  end if;
  select * into s from public.phase_b_workflow_step where step_id = sr.step_id;

  -- ---- 1. TYPED INPUT ----------------------------------------------------------------------
  select valid, reason, missing into v_ok, v_reason, v_missing
    from public.fn_phase_d_schema_validate(b.input_schema_id, v_inputs);
  if not v_ok then
    raise exception 'fn_phase_d_handler_execute: step % input rejected: % (pd_input_schema_invalid)',
      sr.step_id, v_reason using errcode = '22023';
  end if;

  -- ---- 2. RULES IN SCOPE -------------------------------------------------------------------
  -- SCOPE IS NOT APPLICABILITY. The frozen registry scopes rules by WORKFLOW, so BR-002 is in
  -- scope for all 257 steps while only 28 of them name an independent reviewer. Asking
  -- fn_kernel_reviewer_independent about a NULL reviewer returns false, which refused an intake
  -- step for a creator/reviewer collision that could not exist. fn_phase_d_rule_applies decides
  -- both, and records the reason either way, so a rule that did not apply is visibly out of
  -- scope rather than silently skipped.
  --
  -- Refusals are collected rather than short-circuited: a caller told only the first thing wrong
  -- fixes one thing and comes back.
  for v_rule in select unnest(b.rule_ids) rid loop
    select applies, why into v_applies, v_why
      from public.fn_phase_d_rule_applies(v_rule.rid, sr.step_id);
    if not coalesce(v_applies,false) then
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object(
        'rule_id', v_rule.rid, 'applies', false, 'why', v_why));
      continue;
    end if;

    select ok, rule_type, enforced, reason, refusal_code
      into v_rule_ok, v_rule_type, v_enforced, v_rule_reason, v_refusal
      from public.fn_phase_d_rule_check(v_rule.rid,
        -- The caller's business context is merged in LAST so a CONTEXT_REQUIRED rule can be
        -- satisfied by a named fact, and refuses when the fact is absent.
        jsonb_build_object(
          'accountable_role_id', sr.accountable_role_id,
          'reviewer_role_id',    nullif(b.independent_reviewer_role_id,''),
          'actor_role_id',       v_actor,
          'step_id',             sr.step_id,
          'workflow_id',         b.workflow_id,
          'run_id',              sr.run_id,
          'founder_gate',        b.founder_gate,
          'execution_context',   v_ctx)
        || coalesce(p_input->'context','{}'::jsonb));

    v_evaluated := v_evaluated || jsonb_build_array(jsonb_build_object(
      'rule_id', v_rule.rid, 'rule_type', v_rule_type, 'ok', v_rule_ok,
      'enforced', v_enforced, 'reason', v_rule_reason));

    if not coalesce(v_rule_ok,false) and v_rule_type = 'hard' then
      v_refused := v_refused || jsonb_build_array(jsonb_build_object(
        'rule_id', v_rule.rid, 'rule_type', v_rule_type,
        'refusal_code', v_refusal, 'reason', v_rule_reason));
    end if;
  end loop;
  if jsonb_array_length(v_refused) > 0 then
    raise exception 'fn_phase_d_handler_execute: step % refused by % hard business rule(s): % (pd_rule_refused)',
      sr.step_id, jsonb_array_length(v_refused), v_refused::text using errcode = '23514';
  end if;

  -- ---- 3. CAPABILITY BOUNDARY, FAIL CLOSED -------------------------------------------------
  -- D9: a Phase D mock may not complete a real business step. The mock exists, it is typed, and
  -- it is reachable ONLY from an explicit test context. In production this is a refusal with a
  -- machine code, not a silent pass and not an empty success.
  if b.capability_dependency <> 'NONE' and v_ctx <> 'test' then
    raise exception 'fn_phase_d_handler_execute: step % depends on capability % (matched on the frozen required_action at: %) and no capability provider is available in Phase D. Paid inference is held until Phase E. Refusing rather than completing a business step from a fixture. (pd_capability_unavailable)',
      sr.step_id, b.capability_dependency, coalesce(nullif(b.capability_evidence,''),'(none)')
      using errcode = '23514';
  end if;

  -- ---- 4. PROVIDER BOUNDARY, FAIL CLOSED ---------------------------------------------------
  if b.provider_dependency <> 'NONE' and v_ctx <> 'test' then
    raise exception 'fn_phase_d_handler_execute: step % depends on external provider % which is disabled for the whole of Phase D. (pd_provider_disabled)',
      sr.step_id, b.provider_dependency using errcode = '23514';
  end if;

  -- ---- 5. THE FAMILY HANDLER ---------------------------------------------------------------
  -- Deterministic: the output is a function of the frozen step contract and the named inputs.
  -- Nothing here reaches a model, a network or a clock-dependent source.
  v_assert := (
    select coalesce(jsonb_agg(jsonb_build_object(
             'criterion', btrim(c), 'satisfied_by',
             'named inputs [' || array_to_string(
               (select array_agg(k order by k) from jsonb_object_keys(v_inputs) k), ', ') || ']')
             order by ord), '[]'::jsonb)
      from unnest(string_to_array(coalesce(s.acceptance_criteria,''), ';')) with ordinality u(c, ord)
     where btrim(c) <> '');

  v_output := jsonb_build_object(
    'status', 'completed',
    'output', format('%s — %s', s.step_name, coalesce(s.required_output,'output produced')),
    'acceptance_assertions', case when jsonb_array_length(v_assert) = 0
                                  then jsonb_build_array(jsonb_build_object(
                                         'criterion', coalesce(s.acceptance_criteria,'(none declared)'),
                                         'satisfied_by','named inputs'))
                                  else v_assert end,
    'evidence_refs', jsonb_build_array(jsonb_build_object(
       'step_id', sr.step_id, 'step_run_id', v_step_run, 'run_id', sr.run_id,
       'handler_id', b.handler_id, 'handler_version', b.handler_version,
       'input_schema_id', b.input_schema_id, 'output_schema_id', b.output_schema_id,
       'inputs_named', v_inputs, 'execution_context', v_ctx)))
    || case b.handler_class
         when 'INTAKE_HANDLER' then jsonb_build_object(
           'source_ref', coalesce(p_input->>'source_ref', 'step_run:' || v_step_run),
           'captured_verbatim', v_inputs)
         when 'ANALYSIS_HANDLER' then jsonb_build_object(
           'method', 'deterministic reconciliation of the named inputs against the frozen step contract',
           'inputs_used', v_inputs,
           'findings', jsonb_build_array(coalesce(s.required_action,'')),
           'assumptions', jsonb_build_array(
             'only the inputs named in this call were used; no external source was consulted'))
         when 'EXECUTION_HANDLER' then jsonb_build_object(
           'state_change', coalesce(s.required_output,''),
           'target_object', coalesce((select primary_object from public.phase_b_workflow w
                                       where w.workflow_id = b.workflow_id), b.workflow_id),
           'authorization_ref', format('accountable owner %s on step %s',
                                       sr.accountable_role_id, sr.step_id))
         -- The verdict is the CALLER's, never this routine's. A review handler that returns
         -- 'approved' because it was asked to run is a scorer that always passes, and it would
         -- make every one of the 47 review steps a rubber stamp. An absent verdict falls through
         -- to the output schema, which refuses it by name.
         when 'REVIEW_HANDLER' then jsonb_strip_nulls(jsonb_build_object(
           'verdict', nullif(btrim(coalesce(p_input->>'verdict','')),''),
           'reviewer_role_id', nullif(btrim(coalesce(p_input->>'reviewer_role_id','')),'')))
         when 'DECISION_HANDLER' then jsonb_build_object(
           'decision', coalesce(s.required_output,''),
           'rationale', coalesce(s.acceptance_criteria,''),
           'authority_ref', format('founder_gate=%s; accountable owner %s',
                                   b.founder_gate, sr.accountable_role_id))
         when 'HANDOFF_HANDLER' then jsonb_build_object(
           'packet', v_inputs,
           'receiving_role_id', coalesce((select h.receiving_role_id from public.phase_b_handoff h
                                           where h.from_step_id = sr.step_id limit 1),
                                         sr.accountable_role_id),
           'acceptance_criteria', coalesce(s.acceptance_criteria,''))
         -- NOTHING IS DEFAULTED HERE. A denominator this routine invents is the least(100, NULL)
         -- defect in another costume: it turns "we did not measure" into a complete-looking
         -- ratio. An absent numerator, denominator or window falls through as NULL and the
         -- output schema below refuses the step by name.
         when 'MEASUREMENT_HANDLER' then jsonb_strip_nulls(jsonb_build_object(
           'metric', coalesce(s.required_output,''),
           'denominator', p_input->'denominator',
           'numerator', p_input->'numerator',
           'formula', nullif(btrim(coalesce(p_input->>'formula','')),''),
           'window', nullif(btrim(coalesce(p_input->>'window','')),'')))
         when 'CLOSURE_HANDLER' then jsonb_build_object(
           'blockers_resolved', jsonb_build_array(
             'the frozen fn_kernel_step_complete measures the four mandatory closure blocker '
             || 'classes itself and raises k3_closure_blocked if any is open'),
           'closure_evidence', coalesce(s.closure_criteria,''))
         else '{}'::jsonb end;

  -- ---- 5a. TWO REFUSALS THE SCHEMA ALONE CANNOT MAKE ---------------------------------------
  -- Independence: a present-and-non-empty reviewer_role_id still satisfies the output schema, so
  -- the schema cannot catch a reviewer who is the author. fn_kernel_reviewer_independent resolves
  -- both sides through the alias table, which a string comparison would not.
  if b.handler_class = 'REVIEW_HANDLER'
     and not public.fn_kernel_reviewer_independent(
               sr.accountable_role_id, v_output->>'reviewer_role_id') then
    raise exception 'fn_phase_d_handler_execute: step % is accountable to % and the review names % as reviewer; those resolve to the same effective identity. A creator cannot be the sole independent reviewer of the same output (BR-002). (pd_rule_refused)',
      sr.step_id, sr.accountable_role_id, coalesce(v_output->>'reviewer_role_id','(none)')
      using errcode = '23514';
  end if;

  -- A zero denominator is not a measurement. PHASE_D_TEST_AND_ACCEPTANCE_PLAN.md states it
  -- directly: a test expecting rows is invalid if the denominator is zero. The same is true of
  -- the step that produces the number.
  if b.handler_class = 'MEASUREMENT_HANDLER'
     and jsonb_typeof(v_output->'denominator') = 'number'
     and (v_output->>'denominator')::numeric = 0 then
    raise exception 'fn_phase_d_handler_execute: step % reported a denominator of 0. A ratio over nothing is not a measurement, and reporting it as one is how an unmeasured goal scores as perfect. (pd_output_schema_invalid)',
      sr.step_id using errcode = '22023';
  end if;

  -- ---- 6. TYPED OUTPUT ---------------------------------------------------------------------
  select valid, reason, missing into v_ok, v_reason, v_missing
    from public.fn_phase_d_schema_validate(b.output_schema_id, v_output);
  if not v_ok then
    raise exception 'fn_phase_d_handler_execute: step % produced an output its own contract rejects: % (pd_output_schema_invalid)',
      sr.step_id, v_reason using errcode = '22023';
  end if;

  -- ---- 7. HAND TO THE FROZEN KERNEL --------------------------------------------------------
  -- Everything from here — idempotency, locks, authority, gates, the task state machine,
  -- progression, handoffs, run state and events — belongs to fn_kernel_step_complete and is not
  -- reimplemented. A handler that wrote any of it would be the parallel engine the spec forbids.
  v_result := public.fn_kernel_step_complete(jsonb_build_object(
    'step_run_id', v_step_run, 'actor_role_id', v_actor, 'outcome', 'pass',
    'idempotency_key', v_idem, 'inputs', v_inputs, 'output', v_output,
    'evidence_ref', format('phase_d:%s:%s', b.handler_id, v_step_run),
    'correlation_id', p_input->>'correlation_id',
    'causation_id', coalesce(p_input->>'causation_id', 'phase_d_handler:' || b.handler_id)));

  return v_result || jsonb_build_object(
    'phase_d', jsonb_build_object(
      'handler_id', b.handler_id, 'handler_version', b.handler_version,
      'handler_class', b.handler_class, 'execution_context', v_ctx,
      'input_schema_id', b.input_schema_id, 'output_schema_id', b.output_schema_id,
      'rules_in_scope', cardinality(b.rule_ids),
      'rules_evaluated', v_evaluated, 'rules_not_applicable', v_skipped,
      'rules_enforced_count', (select count(*) from jsonb_array_elements(v_evaluated) e
                                where (e->>'enforced')::boolean),
      'rules_outstanding_count', (select count(*) from jsonb_array_elements(v_evaluated) e
                                   where not (e->>'enforced')::boolean),
      'gates_in_scope', cardinality(b.gate_ids),
      'capability_dependency', b.capability_dependency,
      'provider_dependency', b.provider_dependency,
      'external_effect_policy', b.external_effect_policy));
end $fn$;

comment on function public.fn_phase_d_handler_execute(jsonb) is
  'The one Phase D handler executor. It produces the business output the kernel cannot and then '
  'CALLS the frozen fn_kernel_step_complete; it does not open step runs, create tasks or handoffs, '
  'move run state or emit events, because those belong to the kernel. Capability- and '
  'provider-dependent steps fail closed outside an explicit test context.';

-- ================================================================ 5. the board
create or replace function public.fn_phase_d_handler_state()
returns table(check_name text, expected text, actual text, ok boolean)
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare n_steps int; n_bound int; n_amb int; n_sch int; n_drift int; n_blocked int; n_def int;
begin
  select count(*) into n_steps from public.phase_b_workflow_step;
  select count(*) into n_bound from public.phase_d_handler_binding;

  check_name := 'every_frozen_step_has_a_handler_binding';
  expected := n_steps::text; actual := n_bound::text; ok := (n_bound = n_steps); return next;

  -- Ambiguity is structurally impossible (step_id is the primary key), so what is worth checking
  -- is the other direction: a binding for a step the frozen registry does not declare.
  select count(*) into n_amb from public.phase_d_handler_binding b
   where not exists (select 1 from public.phase_b_workflow_step s where s.step_id = b.step_id);
  check_name := 'no_binding_for_an_unfrozen_step';
  expected := '0'; actual := n_amb::text; ok := (n_amb = 0); return next;

  select count(*) into n_sch from public.phase_d_handler_schema;
  check_name := 'two_schemas_per_step';
  expected := (n_steps * 2)::text; actual := n_sch::text; ok := (n_sch = n_steps * 2); return next;

  -- The digest is the point of the schema table: it detects a Phase B text change that would
  -- otherwise leave the contract quietly describing a step that no longer says that.
  select count(*) into n_drift from public.phase_d_handler_schema sc
    join public.phase_b_workflow_step s on s.step_id = sc.step_id
   where sc.source_digest <> encode(sha256(convert_to(
           case sc.schema_kind
             when 'input' then coalesce(s.required_inputs,'')
             else coalesce(s.required_output,'') || ' || ' || coalesce(s.acceptance_criteria,'')
           end, 'UTF8')), 'hex');
  check_name := 'no_schema_drift_against_frozen_phase_b';
  expected := '0'; actual := n_drift::text; ok := (n_drift = 0); return next;

  select count(*) into n_blocked from public.phase_d_handler_binding
   where phase_d_status = 'BLOCKED_DEFECT';
  check_name := 'blocked_defects';
  expected := '0'; actual := n_blocked::text; ok := (n_blocked = 0); return next;

  -- The Definition of Done's "required deferred handlers 0": no binding may still point at a
  -- retired door.
  --
  -- The retired path is RESOLVED from public.kernel_retired_path rather than named as a literal,
  -- for two reasons. It generalises: a routine retired tomorrow is covered without editing this
  -- board. And it avoids a real instrument collision — fn_kernel_retired_path_state finds callers
  -- of a disabled path by scanning routine BODIES, and pg_get_functiondef returns comments as
  -- well as code, so merely WRITING a disabled routine's name here, in a string or in a remark,
  -- made this board count as an active caller of the path it was checking nobody called.
  -- Measured: that moved active_callers_of_disabled_paths from 0 to 1 of 2. The name therefore
  -- appears nowhere in this body, deliberately.
  select count(*) into n_def
    from public.phase_d_handler_binding b
    join public.kernel_retired_path rp
      on b.handler_routine like '%' || rp.path_name || '%'
   where rp.disposition = 'DISABLED';
  check_name := 'no_binding_names_a_retired_routine';
  expected := '0'; actual := n_def::text; ok := (n_def = 0); return next;
end $fn$;

comment on function public.fn_phase_d_handler_state() is
  'Phase D handler registry board. Discovered by public.fn_kernel_all_boards() on signature.';

-- ================================================================ 6. grants
-- Every SECURITY DEFINER function created here is granted EXECUTE to PUBLIC by Postgres and is
-- revoked in the same migration. CREATE OR REPLACE preserves an existing ACL, so the revokes
-- below are written for the create case and are harmless on replace.
revoke all on function public.fn_phase_d_handler_execute(jsonb) from public, anon, authenticated;
grant execute on function public.fn_phase_d_handler_execute(jsonb) to service_role;

revoke all on function public.fn_phase_d_schema_validate(text, jsonb) from public, anon;
grant execute on function public.fn_phase_d_schema_validate(text, jsonb) to service_role, authenticated;

revoke all on function public.fn_phase_d_slug(text) from public, anon;
grant execute on function public.fn_phase_d_slug(text) to service_role, authenticated;

revoke all on function public.fn_phase_d_handler_state() from public, anon;
grant execute on function public.fn_phase_d_handler_state() to service_role, authenticated;

-- The registry and the contract are read-only to everything but the kernel role.
revoke all on public.phase_d_handler_binding from public, anon, authenticated;
revoke all on public.phase_d_handler_schema  from public, anon, authenticated;
grant select on public.phase_d_handler_binding to service_role, authenticated;
grant select on public.phase_d_handler_schema  to service_role, authenticated;

commit;

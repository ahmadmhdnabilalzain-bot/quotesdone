-- F05 - the capability boundary stops being a test-mode bypass
--
-- THE FOUNDER'S RULING, section C, in his own words:
--
--     Do not bypass their boundary with:  execution_context = test -> skip capability check.
--
-- That is exactly what was there. fn_phase_d_handler_execute section 3 read:
--
--     if b.capability_dependency <> 'NONE' and v_ctx <> 'test' then
--       raise ... (pd_capability_unavailable);
--     end if;
--
-- and section 4 said the same thing about the provider dependency. So the string 'test' arriving in
-- one field turned twenty-one fail-closed business boundaries off at once, and a workflow could
-- reach closure having asserted a capability nobody supplied. The builder's own deliverable header
-- says so in its first paragraph and drives in production mode to avoid it; that is the right
-- instinct and the wrong remedy, because it leaves the bypass in the routine.
--
-- WHAT REPLACES IT — the founder's own sequence, which is also the production sequence:
--
--     capability request -> capability result -> output validation -> evidence/provenance
--                        -> handler continuation
--
-- Both halves are now REAL ROWS, and the handler resolves them by reading, not by trusting a mode:
--
--   * fn_phase_d_capability_request_open records that a step asked for a capability. It runs in
--     every context, production included, and it is what a Phase E provider would answer.
--   * fn_phase_d_capability_result_accept is the ONE result-acceptance service. A Phase E provider
--     result and a Phase D fixture result travel through the same routine, the same schema
--     validation, the same evidence recording and the same idempotency; the only difference is the
--     provider_mode column and what each mode has to prove.
--   * provider_mode = 'fixture' additionally requires a verified Phase D fixture context (F01) and
--     a fixture id, version and hash that resolve in the committed catalogue. In production there
--     is no fixture context, so a fixture result is refused -- 42501, before the payload is read.
--   * provider_mode = 'provider' requires a provider event reference and is refused outright while
--     the founder's paid-inference hold stands. It exists so the Phase E path is the same path.
--
-- The handler then asks one question: is there an ACCEPTED capability result for this step run? No
-- result, no continuation -- pd_capability_unavailable, in production and in test alike. The mode
-- is not consulted, and there is no longer a value of execution_context that skips the check.
--
-- WHAT THIS DOES NOT WEAKEN, stated because a boundary change deserves it:
--   * a step with no request and no result refuses exactly as it did before;
--   * a malformed fixture result is refused by the schema check, not accepted and then ignored;
--   * a fixture result replayed produces no second effect (the acceptance is keyed);
--   * a fixture result submitted with no verified fixture context is refused;
--   * nothing here calls a provider, and the provider arm raises before it could.

-- ================================================================================================
-- 1. WHAT A CAPABILITY RESULT MUST LOOK LIKE, PER STEP
-- ================================================================================================
CREATE TABLE IF NOT EXISTS public.phase_d_capability_contract (
  step_id       text PRIMARY KEY REFERENCES public.phase_b_workflow_step(step_id),
  capability    text        NOT NULL,
  required_keys text[]      NOT NULL CHECK (cardinality(required_keys) >= 1),
  key_types     jsonb       NOT NULL,
  note          text        NOT NULL,
  recorded_at   timestamptz NOT NULL DEFAULT now()
);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_d_capability_contract FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_d_capability_contract FROM anon, authenticated, service_role;

COMMENT ON TABLE public.phase_d_capability_contract IS
  'THE OUTPUT CONTRACT OF A CAPABILITY RESULT, ONE ROW PER CAPABILITY-DEPENDENT STEP. Named keys '
  'and their types, validated by fn_phase_d_capability_result_accept before any result -- fixture '
  'or provider -- is recorded. A step with a capability_dependency and no row here cannot accept a '
  'result at all, which is the fail-closed default (F05).';

-- Every step the frozen binding marks capability-dependent gets the REASONING contract. The keys
-- are the ones a reasoning result has to carry for the estate to be able to say what it decided,
-- on what, how sure it was, and what it assumed -- and `provider_mode` is in the payload as well as
-- the column so a result cannot be silently re-labelled after acceptance.
INSERT INTO public.phase_d_capability_contract (step_id, capability, required_keys, key_types, note)
SELECT b.step_id, b.capability_dependency,
       ARRAY['finding','rationale','confidence','assumptions','provider_mode'],
       jsonb_build_object('finding','string','rationale','string','confidence','number',
                          'assumptions','array','provider_mode','string'),
       format('%s on step %s (%s). The frozen required_action that made this step capability-dependent: %s',
              b.capability_dependency, b.step_id, b.handler_class,
              coalesce(nullif(b.capability_evidence,''),'(none recorded)'))
  FROM public.phase_d_handler_binding b
 WHERE b.capability_dependency <> 'NONE'
ON CONFLICT (step_id) DO NOTHING;

-- ================================================================================================
-- 2. THE REQUEST
-- ================================================================================================
CREATE TABLE IF NOT EXISTS public.phase_d_capability_request (
  request_id     bigserial   PRIMARY KEY,
  step_run_id    bigint      NOT NULL,
  run_id         bigint      NOT NULL,
  step_id        text        NOT NULL,
  workflow_id    text        NOT NULL,
  capability     text        NOT NULL,
  requested_by   text        NOT NULL,
  request_digest text        NOT NULL,
  fixture_run_id bigint,
  state          text        NOT NULL DEFAULT 'open'
                 CHECK (state in ('open','answered','refused')),
  opened_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT phase_d_capability_request_one_open_per_step_run UNIQUE (step_run_id, capability)
);

CREATE TABLE IF NOT EXISTS public.phase_d_capability_result (
  result_id       bigserial   PRIMARY KEY,
  request_id      bigint      NOT NULL REFERENCES public.phase_d_capability_request(request_id),
  provider_mode   text        NOT NULL CHECK (provider_mode in ('fixture','provider')),
  fixture_id      text,
  fixture_version int,
  fixture_hash    text,
  provider_event_ref text,
  payload         jsonb       NOT NULL,
  payload_digest  text        NOT NULL,
  trace_id        bigint,
  evidence        text        NOT NULL CHECK (length(btrim(evidence)) >= 30),
  accepted_by     text        NOT NULL,
  fixture_run_id  bigint,
  accepted_at     timestamptz NOT NULL DEFAULT now(),
  -- A FIXTURE RESULT NAMES THE FIXTURE. Nothing may be accepted as a fixture without the id,
  -- version and hash that let a reader find the committed row it came from.
  CONSTRAINT phase_d_capability_result_fixture_is_identified
    CHECK (provider_mode <> 'fixture'
           OR (fixture_id is not null and fixture_version is not null
               and fixture_hash is not null and fixture_run_id is not null)),
  CONSTRAINT phase_d_capability_result_provider_names_its_event
    CHECK (provider_mode <> 'provider' OR provider_event_ref is not null),
  CONSTRAINT phase_d_capability_result_one_per_request UNIQUE (request_id)
);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_d_capability_request FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_d_capability_request FROM anon, authenticated, service_role;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_d_capability_result FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_d_capability_result FROM anon, authenticated, service_role;

COMMENT ON TABLE public.phase_d_capability_request IS
  'A STEP ASKED FOR A CAPABILITY. Written in every execution context, production included, by '
  'fn_phase_d_capability_request_open. This is the row a Phase E provider would answer, and it is '
  'the row a Phase D fixture result answers -- the same row, so the two paths cannot diverge (F05).';
COMMENT ON TABLE public.phase_d_capability_result IS
  'THE ANSWER TO A CAPABILITY REQUEST, whatever produced it. One row per request. provider_mode '
  'says which world it came from: fixture requires a verified Phase D fixture context and names '
  'the committed catalogue row by id, version and hash; provider requires a provider event '
  'reference and is refused while the founder''s paid-inference hold stands. Both go through the '
  'same validation, the same evidence and the same idempotency (F05).';

INSERT INTO public.kernel_write_authority (table_name, routine_name, why) VALUES
  ('phase_d_capability_request', 'fn_phase_d_capability_request_open',
   'The canonical capability-request service. A capability request exists because a handler asked for one, never because a caller inserted a row.'),
  ('phase_d_capability_result', 'fn_phase_d_capability_result_accept',
   'The canonical capability-result acceptance service. Every result -- provider or fixture -- is validated against the step contract, given evidence and provenance, and recorded here by this routine alone.')
ON CONFLICT DO NOTHING;

DROP TRIGGER IF EXISTS z10_kernel_write_guard ON public.phase_d_capability_request;
CREATE TRIGGER z10_kernel_write_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.phase_d_capability_request
  FOR EACH ROW EXECUTE FUNCTION public.fn_kernel_write_guard();
DROP TRIGGER IF EXISTS z10_kernel_write_guard ON public.phase_d_capability_result;
CREATE TRIGGER z10_kernel_write_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.phase_d_capability_result
  FOR EACH ROW EXECUTE FUNCTION public.fn_kernel_write_guard();

REVOKE TRUNCATE ON public.phase_d_capability_request  FROM PUBLIC, anon, authenticated, service_role;
REVOKE TRUNCATE ON public.phase_d_capability_result   FROM PUBLIC, anon, authenticated, service_role;
REVOKE TRUNCATE ON public.phase_d_capability_contract FROM PUBLIC, anon, authenticated, service_role;
DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_d_capability_request;
CREATE TRIGGER z00_kernel_truncate_guard BEFORE TRUNCATE ON public.phase_d_capability_request
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard();
DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_d_capability_result;
CREATE TRIGGER z00_kernel_truncate_guard BEFORE TRUNCATE ON public.phase_d_capability_result
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard();
DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_d_capability_contract;
CREATE TRIGGER z00_kernel_truncate_guard BEFORE TRUNCATE ON public.phase_d_capability_contract
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard();

-- ================================================================================================
-- 3. THE REQUEST SERVICE
-- ================================================================================================
CREATE OR REPLACE FUNCTION public.fn_phase_d_capability_request_open(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  sr  public.phase_c_workflow_step_run%rowtype;
  b   public.phase_d_handler_binding%rowtype;
  q   public.phase_d_capability_request%rowtype;
  v_step_run bigint := nullif(p_input->>'step_run_id','')::bigint;
  v_by       text   := nullif(btrim(coalesce(p_input->>'requested_by','')),'');
  v_id       bigint;
begin
  if v_step_run is null or v_by is null then
    raise exception 'fn_phase_d_capability_request_open: step_run_id and requested_by are required (pd_capability_request_invalid)'
      using errcode = '22023';
  end if;
  select * into sr from public.phase_c_workflow_step_run where step_run_id = v_step_run;
  if not found then
    raise exception 'fn_phase_d_capability_request_open: no step run % (pd_step_state_invalid)', v_step_run
      using errcode = '23503';
  end if;
  select * into b from public.phase_d_handler_binding where step_id = sr.step_id;
  if not found or b.capability_dependency = 'NONE' then
    raise exception 'fn_phase_d_capability_request_open: step % declares no capability dependency, so there is nothing to request (pd_capability_not_declared)',
      sr.step_id using errcode = '22023';
  end if;

  select * into q from public.phase_d_capability_request
   where step_run_id = v_step_run and capability = b.capability_dependency;
  if found then
    return jsonb_build_object('ok', true, 'replay', true, 'request_id', q.request_id,
                              'state', q.state, 'capability', q.capability);
  end if;

  insert into public.phase_d_capability_request
    (step_run_id, run_id, step_id, workflow_id, capability, requested_by, request_digest,
     fixture_run_id)
  values (v_step_run, sr.run_id, sr.step_id, b.workflow_id, b.capability_dependency, v_by,
          encode(sha256(convert_to(format('%s|%s|%s', sr.step_id, v_step_run,
                                          b.capability_dependency),'UTF8')),'hex'),
          public.fn_phase_d_fixture_context())
  returning request_id into v_id;

  return jsonb_build_object('ok', true, 'replay', false, 'request_id', v_id,
                            'state','open', 'capability', b.capability_dependency,
                            'note','a request is open; no provider is available in Phase D, so it '
                                || 'is answered by a Phase D fixture result or not at all');
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_capability_request_open(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_d_capability_request_open(jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_capability_request_open(jsonb) TO service_role;

-- ================================================================================================
-- 4. THE ONE RESULT-ACCEPTANCE SERVICE
-- ================================================================================================
CREATE OR REPLACE FUNCTION public.fn_phase_d_capability_result_accept(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  q    public.phase_d_capability_request%rowtype;
  c    public.phase_d_capability_contract%rowtype;
  ex   public.phase_d_capability_result%rowtype;
  v_req   bigint := nullif(p_input->>'request_id','')::bigint;
  v_mode  text   := lower(nullif(btrim(coalesce(p_input->>'provider_mode','')),''));
  v_pay   jsonb  := p_input->'payload';
  v_fid   text   := nullif(btrim(coalesce(p_input->>'fixture_id','')),'');
  v_fver  int    := nullif(p_input->>'fixture_version','')::int;
  v_by    text   := nullif(btrim(coalesce(p_input->>'accepted_by','')),'');
  v_run   bigint := public.fn_phase_d_fixture_context();
  v_cat   public.phase_d_fixture_catalogue%rowtype;
  v_k     text;
  v_want  text;
  v_got   text;
  v_miss  text[] := '{}';
  v_bad   text[] := '{}';
  v_id    bigint;
begin
  if v_req is null or v_mode is null or v_by is null then
    raise exception 'fn_phase_d_capability_result_accept: request_id, provider_mode and accepted_by are all required (pd_capability_result_invalid)'
      using errcode = '22023';
  end if;
  select * into q from public.phase_d_capability_request where request_id = v_req;
  if not found then
    raise exception 'fn_phase_d_capability_result_accept: no capability request % (pd_capability_request_absent)', v_req
      using errcode = '23503';
  end if;

  -- ---- idempotent replay: one result per request, and the first one stands -------------------
  select * into ex from public.phase_d_capability_result where request_id = v_req;
  if found then
    return jsonb_build_object('ok', true, 'replay', true, 'result_id', ex.result_id,
      'provider_mode', ex.provider_mode, 'payload_digest', ex.payload_digest,
      'note','this request already carries a result; no second result and no second effect');
  end if;

  -- ---- THE PROVIDER ARM IS REFUSED WHILE THE HOLD STANDS ------------------------------------
  -- It is written out rather than omitted so that the Phase E path is this path, and so that the
  -- refusal is a measured fact rather than the absence of code.
  if v_mode = 'provider' then
    raise exception 'fn_phase_d_capability_result_accept: a provider result cannot be accepted while the founder''s paid-inference hold stands (NO_PAID_AI=true, OPENROUTER_DISABLED=true, AI_PROVIDER_MODE=mock). No provider was called to produce this refusal. (pd_provider_disabled)'
      using errcode = '23514';
  end if;

  -- ---- THE FIXTURE ARM NEEDS A CONTEXT NO UNTRUSTED CALLER CAN MANUFACTURE --------------------
  if v_mode = 'fixture' then
    if v_run is null then
      raise exception 'fn_phase_d_capability_result_accept: a fixture capability result requires a verified Phase D fixture context. In production there is none, so a fixture result is refused before its payload is read. (pd_capability_fixture_context_absent)'
        using errcode = '42501';
    end if;
    if v_fid is null then
      raise exception 'fn_phase_d_capability_result_accept: a fixture result must name the committed catalogue row it came from (fixture_id) (pd_capability_fixture_unidentified)'
        using errcode = '22023';
    end if;
    select * into v_cat from public.phase_d_fixture_catalogue
     where fixture_id = v_fid and scope = 'CAPABILITY_RESULT';
    if not found then
      raise exception 'fn_phase_d_capability_result_accept: fixture % is not a CAPABILITY_RESULT row in the committed catalogue (pd_capability_fixture_unknown)',
        v_fid using errcode = '23503';
    end if;
    if v_fver is not null and v_fver <> v_cat.fixture_version then
      raise exception 'fn_phase_d_capability_result_accept: fixture % is version % in the committed catalogue and the call names version % (pd_capability_fixture_version_mismatch)',
        v_fid, v_cat.fixture_version, v_fver using errcode = '22023';
    end if;
    v_fver := v_cat.fixture_version;
    -- The payload is the catalogue's, merged over by nothing. A caller may not hand a fixture id
    -- and then a different payload: that would be an unmarked value wearing a marked label.
    v_pay := v_cat.value;
  end if;

  -- ---- OUTPUT VALIDATION, THE SAME FOR BOTH MODES -------------------------------------------
  select * into c from public.phase_d_capability_contract where step_id = q.step_id;
  if not found then
    raise exception 'fn_phase_d_capability_result_accept: step % has no capability contract, so no result can be validated against anything. Fail closed. (pd_capability_contract_absent)',
      q.step_id using errcode = '23503';
  end if;
  if v_pay is null or jsonb_typeof(v_pay) <> 'object' then
    raise exception 'fn_phase_d_capability_result_accept: the result payload for step % is not an object (pd_capability_result_malformed)',
      q.step_id using errcode = '22023';
  end if;
  foreach v_k in array c.required_keys loop
    if not (v_pay ? v_k) then
      v_miss := v_miss || v_k;
    else
      v_want := c.key_types->>v_k;
      v_got  := jsonb_typeof(v_pay->v_k);
      if v_want is not null and v_got <> v_want then
        v_bad := v_bad || format('%s is %s, contract says %s', v_k, v_got, v_want);
      end if;
    end if;
  end loop;
  if cardinality(v_miss) > 0 or cardinality(v_bad) > 0 then
    raise exception 'fn_phase_d_capability_result_accept: the result for step % does not satisfy its capability contract — missing [%], wrongly typed [%] (pd_capability_result_malformed)',
      q.step_id, array_to_string(v_miss, ', '), array_to_string(v_bad, ', ')
      using errcode = '22023';
  end if;
  -- provider_mode travels INSIDE the payload as well as beside it, and the two must agree, so a
  -- result cannot be re-labelled after acceptance by editing one of them.
  if lower(coalesce(v_pay->>'provider_mode','')) <> v_mode then
    raise exception 'fn_phase_d_capability_result_accept: the payload says provider_mode % and the call says %. A result that disagrees with itself about where it came from is refused. (pd_capability_result_malformed)',
      coalesce(v_pay->>'provider_mode','(absent)'), v_mode
      using errcode = '22023';
  end if;

  insert into public.phase_d_capability_result
    (request_id, provider_mode, fixture_id, fixture_version, fixture_hash, provider_event_ref,
     payload, payload_digest, trace_id, evidence, accepted_by, fixture_run_id)
  values (v_req, v_mode, v_fid, v_fver, v_cat.checksum, nullif(p_input->>'provider_event_ref',''),
          v_pay, encode(sha256(convert_to(v_pay::text,'UTF8')),'hex'),
          nullif(p_input->>'trace_id','')::bigint,
          format('capability %s for step %s answered in mode %s from %s; validated against '
              || 'phase_d_capability_contract keys [%s]; 0 paid inference requests were made to '
              || 'produce this result',
                 q.capability, q.step_id, v_mode,
                 coalesce(v_fid || ' v' || v_fver::text, coalesce(p_input->>'provider_event_ref','(unstated)')),
                 array_to_string(c.required_keys, ', ')),
          v_by, v_run)
  returning result_id into v_id;

  update public.phase_d_capability_request set state = 'answered' where request_id = v_req;

  return jsonb_build_object('ok', true, 'replay', false, 'result_id', v_id, 'request_id', v_req,
    'provider_mode', v_mode, 'fixture_id', v_fid, 'fixture_version', v_fver,
    'fixture_hash', v_cat.checksum,
    'payload_digest', encode(sha256(convert_to(v_pay::text,'UTF8')),'hex'));
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_capability_result_accept(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_d_capability_result_accept(jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_capability_result_accept(jsonb) TO service_role;

-- ================================================================================================
-- 5. WHAT A HANDLER ASKS
-- ================================================================================================
CREATE OR REPLACE FUNCTION public.fn_phase_d_capability_answer(p_step_run_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
           'result_id', r.result_id, 'request_id', r.request_id, 'provider_mode', r.provider_mode,
           'fixture_id', r.fixture_id, 'fixture_version', r.fixture_version,
           'fixture_hash', r.fixture_hash, 'payload', r.payload,
           'payload_digest', r.payload_digest, 'evidence', r.evidence)
    from public.phase_d_capability_result r
    join public.phase_d_capability_request q on q.request_id = r.request_id
   where q.step_run_id = p_step_run_id
   order by r.result_id desc limit 1;
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_capability_answer(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_d_capability_answer(bigint) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_capability_answer(bigint) TO service_role;

-- ================================================================================================
-- 6. THE BOARD
-- ================================================================================================
-- ROUTINE REMOVED 7 September 2026. public.fn_phase_d_capability_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


COMMENT ON FUNCTION public.fn_phase_d_capability_state() IS
  'THE PHASE D CAPABILITY BOUNDARY BOARD. Counts the 21 capability-dependent steps, refuses one '
  'without an output contract, and -- the row that matters -- greps the handler and effect routines '
  'for the exact bypass the founder prohibited, `capability_dependency <> NONE and v_ctx <> test`. '
  'A future edit that reintroduces it turns this row red rather than turning twenty-one boundaries '
  'off in silence (F05).';

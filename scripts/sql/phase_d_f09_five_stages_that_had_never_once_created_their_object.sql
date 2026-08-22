-- F09 - five stages that had never once created their object
--
-- F08 made the scenario factory write an evidence manifest, and the manifest is the first thing in
-- this estate that has ever LOOKED at what the factory produced rather than at how many stages it
-- ran. The first build with it on reported 26 created and 6 not created, and five of the six are
-- stages that have been refusing since the day they were written:
--
--   inquiry_version      state "frozen"     -- IMMUTABLE_REVISION allows open/issued/submitted/approved/rejected/superseded
--   inquiry_route_set    state "confirmed"  -- same family, same list
--   document_extraction  state "extracted"  -- same family, same list
--   reconciliation_case  state "reconciled" -- CASE_RECORD allows open/in_progress/verified/resolved/closed/rejected
--   department_mandate   status "open"      -- public.department_objective CHECK allows active/superseded/achieved/dropped
--
-- Every one of them carried a `working_state_evidence` reading PHASE_D_DECLARATION: "an answer is
-- recorded or it does not exist", "a version snapshot is immutable once taken", "a reconciliation
-- case that has not reconciled proves nothing". Each sentence is true about the BUSINESS and none
-- of them is the state vocabulary the object's own contract declares, so the evidence was a
-- statement of intent standing in front of a value the write service refuses. D22 found exactly
-- this on company_objective -- "a stage added to fix a foreign key and never observed creating
-- anything" -- and the same shape survived in five more places because nothing counted.
--
-- THE CONSEQUENCE, and it is not cosmetic: inquiry_route_set contributes `route_state`, which
-- GATE-010 requires and which "only a confirmed route carries dispatch authority" is about. The
-- stage has never been created, so the reference has never been contributed, so GATE-010 has been
-- refusing every dispatch step in the estate for want of a row that nothing wrote.
--
-- Each state below is the one the object's OWN declared vocabulary uses for the business fact the
-- old evidence described. Nothing is invented: the family and its allowed states are read off
-- public.phase_d_object_state_contract, and the evidence now names both.
--
-- AND ONE THING THE MANIFEST COULD NOT SAY. A stage contributes either a KEY or a STATE --
-- phase_d_fixture_stage.contributes_kind has said so since D9c -- and the manifest recorded only
-- the business key. For inquiry_route_set that meant `route_state` would have resolved to a uuid.
-- The manifest gains contributed_value, which is the value the factory actually put in parent_refs,
-- and the resolver returns that.

-- ---- the five states -------------------------------------------------------------------------
UPDATE public.phase_d_fixture_stage SET
  working_state = 'approved',
  working_state_evidence = 'DERIVED from public.phase_d_object_state_contract: inquiry_version is an IMMUTABLE_REVISION-family object whose declared states are open/issued/submitted/approved/rejected/superseded. A frozen version snapshot is an APPROVED revision in that vocabulary; the previous value "frozen" was true about the business and absent from the contract, so the write service refused this stage on every build since D9c.'
 WHERE stage_key = 'inquiry_version';

UPDATE public.phase_d_fixture_stage SET
  working_state = 'approved',
  working_state_evidence = 'DERIVED from public.phase_d_object_state_contract: inquiry_route_set is an IMMUTABLE_REVISION-family object whose declared states are open/issued/submitted/approved/rejected/superseded. A CONFIRMED route is an APPROVED revision in that vocabulary. The route_state the stage contributes stays "confirmed" -- that is the value GATE-010 tests -- and it is recorded as contributes_kind STATE, not as this row''s key.'
 WHERE stage_key = 'inquiry_route_set';

UPDATE public.phase_d_fixture_stage SET
  working_state = 'approved',
  working_state_evidence = 'DERIVED from public.phase_d_object_state_contract: document_extraction is an IMMUTABLE_REVISION-family object whose declared states are open/issued/submitted/approved/rejected/superseded. A completed deterministic extraction is an APPROVED revision in that vocabulary; "extracted" is a status field on the binding and not a state in the contract.'
 WHERE stage_key = 'document_extraction';

UPDATE public.phase_d_fixture_stage SET
  working_state = 'resolved',
  working_state_evidence = 'DERIVED from public.phase_d_object_state_contract: reconciliation_case is a CASE_RECORD-family object whose declared states are open/in_progress/verified/resolved/closed/rejected. A reconciled case is a RESOLVED case in that vocabulary; monetary_state stays "reconciled" and is what BR-033 reads.'
 WHERE stage_key = 'reconciliation_case';

UPDATE public.phase_d_fixture_stage SET
  working_state = 'active',
  working_state_evidence = 'DERIVED twice: public.phase_d_object_state_contract makes department_mandate a VERSIONED-family object whose declared states are open/active/superseded/published, and public.department_objective_status_check allows active/superseded/achieved/dropped. "active" is the only value in both.'
 WHERE stage_key = 'department_mandate';

-- ---- the manifest records what was contributed, not only the key ------------------------------
ALTER TABLE public.phase_d_scenario_record
  ADD COLUMN IF NOT EXISTS contributed_value text,
  ADD COLUMN IF NOT EXISTS contributes_kind  text;

COMMENT ON COLUMN public.phase_d_scenario_record.contributed_value IS
  'THE VALUE THE FACTORY PUT IN parent_refs FOR THIS STAGE. Usually the business key; for a stage '
  'whose contributes_kind is STATE it is the state -- inquiry_route_set contributes the literal '
  '"confirmed", which is what GATE-010 tests, and returning its uuid instead would have been a '
  'resolver answering a different question (F09).';

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
     contributes_ref, contributed_value, contributes_kind, trace_id, provenance, expected_effect)
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
          nullif(p_input->>'expected_effect',''))
  on conflict (fixture_run_id, object_id, business_key) do update
     set state = excluded.state, result_reference = excluded.result_reference,
         contributed_value = excluded.contributed_value
  returning scenario_record_id into v_id;
  return v_id;
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_scenario_record_write(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_d_scenario_record_write(jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_scenario_record_write(jsonb) TO service_role;

-- ---- the resolver returns the contributed value, and can read a key off a record's payload -----
CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_input(
  p_step_run_id bigint, p_scope text, p_key text)
 RETURNS TABLE(value jsonb, provenance text, fixture_id text, fixture_version int, checksum text)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
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
    select coalesce(sc.contributed_value, sc.business_key) v, sc.object_id o,
           sc.canonical_relation cr, sc.fixture_id fi, sc.fixture_version fv, sc.source_checksum ck
      into r
      from public.phase_d_scenario_record sc
     where sc.fixture_run_id = v_run and sc.contributes_ref = p_key
     order by sc.scenario_record_id limit 1;
    if found then
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
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_fixture_input(bigint, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_d_fixture_input(bigint, text, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_fixture_input(bigint, text, text) TO service_role;

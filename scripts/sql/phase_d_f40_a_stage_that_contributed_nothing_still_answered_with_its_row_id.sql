-- F40 - a stage that contributed nothing still answered, with its own row id
--
-- MEASURED, on the resolved context of W08's first step inside a fixture scenario:
--
--   artifact_sha256 = 44208   <- phase_d_scenario_record: the ux_specification created by fixture run 802
--
-- 44208 is a primary key. BR-036 refused it, correctly and precisely: "artifact_sha256 44208 is not
-- a SHA-256 digest (64 hexadecimal characters), so it was not computed over any artifact." Three
-- workflows -- W08, W22, W24 -- have their FIRST handler refusal there, and W20 has it as one of
-- two.
--
-- THE MECHANISM. fn_phase_d_fixture_input branch (1) resolves a context key from the scenario
-- record whose contributes_ref names it, as coalesce(contributed_value, business_key). Every one of
-- the 32 stages is classified contributes_kind = 'RESULT_KEY', including artifact_revision, whose
-- contributed_value is never set. So the coalesce fell through to the row id and the key was
-- ANSWERED -- which matters twice over, because branch (2), the committed catalogue, runs only for
-- a key nothing else answered. A wrong non-null value does not merely fail a rule; it locks out
-- the fixture that would have been right. F39 added a computed artifact_sha256 to the catalogue
-- and it could never be reached.
--
-- TWO CHANGES, AND THE SECOND IS THE GENERAL ONE:
--
--   * artifact_revision is reclassified PAYLOAD_VALUE, because artifact_sha256 is a digest computed
--     over the artifact body and not the identity of the revision row. F08 already writes that
--     digest into the record's payload, and branch (1b) reads payloads -- it simply never got its
--     turn.
--
--   * branch (1) falls back to business_key ONLY for a RESULT_KEY stage, where the identity of what
--     was created is genuinely the answer. A stage that declares it contributes a value and
--     supplies none now contributes nothing, so the payload branch and then the catalogue get their
--     turn, and a key nothing can answer stays unresolved and its rule refuses -- which is the
--     contract working rather than a row id wearing a digest's name.

-- The one stage that declares a VALUE and was classified as a KEY. artifact_sha256 is a digest
-- computed over the artifact body, not the identity of the revision row, and F08 already writes it
-- into that record's payload -- where branch (1b) of fn_phase_d_fixture_input reads it from. The
-- reclassification is what lets branch (1b) get its turn.
-- The classification is a new one, so the column's CHECK has to admit it first.
ALTER TABLE public.phase_d_fixture_stage
  DROP CONSTRAINT IF EXISTS phase_d_fixture_stage_contributes_kind_check;
ALTER TABLE public.phase_d_fixture_stage
  ADD CONSTRAINT phase_d_fixture_stage_contributes_kind_check
  CHECK (contributes_kind = ANY (ARRAY['RESULT_KEY'::text, 'STATE'::text, 'PAYLOAD_VALUE'::text]));

UPDATE public.phase_d_fixture_stage
   SET contributes_kind = 'PAYLOAD_VALUE'
 WHERE stage_key = 'artifact_revision'
   AND contributes_ref = 'artifact_sha256'
   AND contributes_kind = 'RESULT_KEY';

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
    select case when sc.contributes_kind = 'RESULT_KEY'
                then coalesce(sc.contributed_value, sc.business_key)
                else sc.contributed_value end v,
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

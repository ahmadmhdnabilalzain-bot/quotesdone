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
  v_ckey text;   -- F47: the identity a context key that names an object resolves to
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
    -- ---- F47. A KEY THAT NAMES AN OBJECT IS ANSWERED FROM THAT OBJECT'S REFERENCE --------------
    --
    -- Twelve of the 33 context keys the 54 business rules declare are references to a business
    -- object rather than values in their own right. Which object each names is recorded in
    -- public.phase_d_context_key_object, and the identity then comes from that object's canonical
    -- reference -- so the answer is the same one fn_phase_d_ref_resolve would give and the same one
    -- the rule looks up, whichever store the object lives in.
    --
    -- THIS RUNS BEFORE THE STAGE'S OWN contributes_ref, and that is the point. Before F43 the
    -- answer depended on which stage happened to declare it and what that stage set; now it depends
    -- on the OBJECT, which is what the key is about. A stage no longer has to be classified
    -- correctly for a rule to be given the right subject.
    select sc.canonical_ref->>'canonical_identity' into v_ckey
      from public.phase_d_context_key_object m
      join public.phase_d_scenario_record sc
        on sc.object_id = m.object_id
       and sc.fixture_run_id = v_run
     where m.context_key = p_key and m.key_role = 'IDENTIFIES'
       and sc.canonical_ref is not null
     order by sc.scenario_record_id
     limit 1;
    if v_ckey is not null then
      value := to_jsonb(v_ckey);
      provenance := format('the canonical reference of the %s this fixture run created, resolved '
                        || 'through public.phase_d_context_key_object',
                           (select object_id from public.phase_d_context_key_object
                             where context_key = p_key and key_role = 'IDENTIFIES'));
      select sc.fixture_id, sc.fixture_version, sc.source_checksum
        into fixture_id, fixture_version, checksum
        from public.phase_d_context_key_object m
        join public.phase_d_scenario_record sc
          on sc.object_id = m.object_id and sc.fixture_run_id = v_run
       where m.context_key = p_key and m.key_role = 'IDENTIFIES'
       order by sc.scenario_record_id limit 1;
      return next; return;
    end if;

    -- F45. THE CANONICAL REFERENCE, OR NOTHING. There is no coalesce chain here on purpose: a
    -- fallback among the scenario row id, the object-record key, the business key and the relation
    -- primary key is precisely the guessing the founder's ruling of 23 Aug 2026 removes. An identity
    -- stage answers from the reference the write service returned; a PAYLOAD_VALUE or STATE stage
    -- answers with the value it settled; anything else contributes nothing and the key falls through
    -- to the object payload, then to the committed catalogue, then to an explicit refusal.
    select case when sc.contributes_kind in ('PAYLOAD_VALUE','STATE') then sc.contributed_value
                when sc.canonical_ref is not null
                  then sc.canonical_ref->>'canonical_identity'
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

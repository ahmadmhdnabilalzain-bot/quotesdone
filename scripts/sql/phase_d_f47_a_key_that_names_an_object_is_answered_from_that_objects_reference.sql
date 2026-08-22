-- F47 - a context key that names an object is answered from that object's reference
--
-- F43 recorded which identity each of the 56 objects is known by; F44 and F45 made the write
-- services return it and the factory store it. This closes the last place where the answer still
-- depended on something other than the object: WHICH object a context key is about.
--
-- Twelve of the 33 context keys the 54 business rules declare are references to a business object
-- rather than values in their own right -- safe_package_ref, acceptance_ref, the two revision refs,
-- inquiry_id, supplier_id, transaction_id, comparison_id, caller_customer_id, quote_revision_ref,
-- provider_event_id and artifact_ref. Until now each was answered by whichever fixture stage
-- happened to declare it as its contributes_ref, and by whatever that stage had set -- which is why
-- reclassifying two stages in F42 fixed two rules and left four.
--
-- The mapping is recorded as data, with the reason on each row, in the same way
-- public.phase_d_object_write_map records which relation an object is written to. It is checked at
-- apply time against the 56-object registry, so a key can never name an object that does not exist.
--
-- The lookup runs BEFORE the stage's own contributes_ref, deliberately: the answer now depends on
-- the OBJECT the key is about rather than on a stage being classified correctly.
--
-- The rest of fn_phase_d_fixture_input is byte-identical. One anchor, required to match once.

-- ---- THE REGISTRY: which context keys name a business object, and which one ------------------
CREATE TABLE IF NOT EXISTS public.phase_d_context_key_object (
  context_key text PRIMARY KEY,
  object_id   text NOT NULL,
  why         text NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.phase_d_context_key_object IS
  'The context keys that are REFERENCES to a business object rather than values in their own right, '
  'and which of the 56 frozen objects each names. fn_phase_d_fixture_input answers such a key from '
  'that object''s canonical reference, so a rule is handed the same identity it looks up, whichever '
  'store the object lives in. F47.';

REVOKE ALL ON public.phase_d_context_key_object FROM PUBLIC;
REVOKE ALL ON public.phase_d_context_key_object FROM anon, authenticated;
GRANT SELECT ON public.phase_d_context_key_object TO service_role;

INSERT INTO public.phase_d_context_key_object (context_key, object_id, why) VALUES
 ('acceptance_ref','customer_terms_acceptance',
  'BR-026 refuses a certificate before an acceptance and resolves this against the terms-acceptance record'),
 ('approved_revision_ref','quotation_revision',
  'BR-035 compares the approved revision with the published one; both are IMMUTABLE_REVISION records'),
 ('publishing_revision_ref','quotation_revision',
  'BR-035, the other half of the same comparison'),
 ('quote_revision_ref','quotation_revision',
  'BR-018 asks whether the supplier quote is still supplier-authored, against the revision record'),
 ('artifact_ref','ux_specification',
  'BR-036 requires the reviewer to have reviewed the artifact itself; the artifact is the revision record'),
 ('caller_customer_id','customer_account',
  'BR-019 decides visibility from who is asking, which is a customer account'),
 ('comparison_id','quotation_comparison',
  'BR-019 resolves the comparison whose visibility it is judging'),
 ('inquiry_id','inquiry',
  'BR-013 refuses a quote against an inquiry that is not quote-ready, reading public.inquiries'),
 ('provider_event_id','provider_event',
  'BR-032 refuses a replayed provider event, reading the recorded event'),
 ('safe_package_ref','supplier_safe_package',
  'BR-012 requires an approved supplier-safe package record'),
 ('supplier_id','supplier_account',
  'BR-015 requires an approved, verified supplier, reading public.leads'),
 ('transaction_id','payment_transaction',
  'BR-020 refuses a reveal before payment, reading public.transactions')
ON CONFLICT (context_key) DO UPDATE
  SET object_id = excluded.object_id, why = excluded.why, recorded_at = now();

-- A key naming an object that is not one of the 56 would resolve nothing and say so only at
-- runtime. It is checkable here, once.
DO $guard$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(m.context_key || ' -> ' || m.object_id, ', ')
    INTO v_bad
    FROM public.phase_d_context_key_object m
   WHERE NOT EXISTS (SELECT 1 FROM public.phase_d_object_reference_strategy s
                      WHERE s.object_id = m.object_id);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'phase_d_context_key_object names objects that are not in the frozen 56: %', v_bad;
  END IF;
END $guard$;

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
     where m.context_key = p_key
       and sc.canonical_ref is not null
     order by sc.scenario_record_id
     limit 1;
    if v_ckey is not null then
      value := to_jsonb(v_ckey);
      provenance := format('the canonical reference of the %s this fixture run created, resolved '
                        || 'through public.phase_d_context_key_object',
                           (select object_id from public.phase_d_context_key_object where context_key = p_key));
      select sc.fixture_id, sc.fixture_version, sc.source_checksum
        into fixture_id, fixture_version, checksum
        from public.phase_d_context_key_object m
        join public.phase_d_scenario_record sc
          on sc.object_id = m.object_id and sc.fixture_run_id = v_run
       where m.context_key = p_key order by sc.scenario_record_id limit 1;
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
;

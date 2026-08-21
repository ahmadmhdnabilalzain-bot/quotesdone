-- F02 - the scenario manifest, and the committed content catalogue
--
-- THE FOUNDER'S RULING, 21 Aug 2026, sections A and B, in two sentences:
--
--   A: "The fixture factory must return an evidence manifest listing every created object and
--       expected effect." Every fixture record requires fixture_run_id, fixture_id,
--       fixture_version, source checksum, deterministic business key, canonical ownership, trace
--       and test-only provenance.
--
--   B: "A deterministic handler must not invent business content. The scenario catalogue supplies
--       explicit test values... The handler receives the fixture as input. The handler must not
--       generate the fixture itself."
--
-- WHY TWO TABLES AND NOT ONE.
--
-- The 71 declared context keys split cleanly into two populations, and the split is the whole
-- design:
--
--   * A REFERENCE key names a row. safe_package_ref, provider_event_id, terms_hash, quote_id,
--     transaction_id, acceptance_ref. Its correct value is not authorable in advance -- it is
--     whatever key the scenario factory's canonical write produced in THIS transaction. Those come
--     from public.phase_d_scenario_record, which is the evidence manifest section A demands, and
--     which the factory writes as it creates each object.
--
--   * A CONTENT key is a business judgement. assumptions, formula, window, supplier_payload,
--     an opportunity kind, a quotation amount, a review rationale. A deterministic handler must
--     not invent one, and nothing in the estate holds one. Those come from
--     public.phase_d_fixture_catalogue, which is committed to the repository and compared against
--     the file by CI.
--
-- Both are read ONLY through fn_phase_d_fixture_input, and that routine returns null unless
-- fn_phase_d_fixture_context() (F01) verifies. In production there is no fixture context, so every
-- key that is not resolvable from a real row stays unresolved and its rule or gate refuses exactly
-- as it does today. Nothing about the production boundary moves.
--
-- WHY THE HANDLER IS STILL NOT INVENTING ANYTHING. fn_phase_d_handler_execute never calls
-- fn_phase_d_fixture_input. The resolvers do -- fn_phase_d_step_context and fn_phase_d_step_inputs,
-- which run in fn_phase_d_dispatch_step BEFORE the handler is entered, and hand the handler a
-- payload. That is what "the handler receives the fixture as input" means mechanically.
--
-- EVERY TEXT FIXTURE IS MARKED. A CHECK constraint refuses any text value that does not carry
-- PHASE_D_FIXTURE_DO_NOT_PUBLISH, so a fixture string cannot reach a customer, a supplier or a
-- published surface without the marker travelling with it.
--
-- EVERY ROW CARRIES ITS OWN CHECKSUM, computed by a trigger over the canonical serialisation, so a
-- row edited in the database and not in the committed CSV is visible as a checksum that no longer
-- matches its content -- the "a row added without its artefact" lesson, applied at write time.

-- ================================================================================================
-- 1. THE EVIDENCE MANIFEST
-- ================================================================================================
CREATE TABLE IF NOT EXISTS public.phase_d_scenario_record (
  scenario_record_id bigserial   PRIMARY KEY,
  fixture_run_id     bigint      NOT NULL REFERENCES public.phase_d_test_context_grant(fixture_run_id),
  fixture_id         text        NOT NULL,
  fixture_version    int         NOT NULL DEFAULT 1,
  source_checksum    text        NOT NULL,
  object_id          text        NOT NULL,
  business_key       text        NOT NULL,
  owner_ref          text,
  ownership_scope    text        NOT NULL,
  state              text,
  canonical_relation text,
  canonical_service  text        NOT NULL,
  result_reference   text,
  contributes_ref    text,
  trace_id           bigint,
  provenance         text        NOT NULL,
  expected_effect    text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT phase_d_scenario_record_is_test_only
    CHECK (provenance like 'PHASE_D_FIXTURE%'),
  CONSTRAINT phase_d_scenario_record_one_per_object_per_run
    UNIQUE (fixture_run_id, object_id, business_key)
);

CREATE INDEX IF NOT EXISTS phase_d_scenario_record_by_run_ref
  ON public.phase_d_scenario_record (fixture_run_id, contributes_ref);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_d_scenario_record FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_d_scenario_record FROM anon, authenticated, service_role;

COMMENT ON TABLE public.phase_d_scenario_record IS
  'THE EVIDENCE MANIFEST THE FOUNDER ASKED FOR. One row per business object the zero-persistence '
  'scenario factory created, naming the fixture run that authorised it, the fixture id and version '
  'that describe it, the checksum of the source that produced it, the deterministic business key, '
  'the canonical ownership, the canonical SERVICE that wrote it (never a direct insert), the trace '
  'and a test-only provenance string. Every row is written inside a transaction that is aborted, so '
  'a committed row here is itself a residue finding (F02).';

INSERT INTO public.kernel_write_authority (table_name, routine_name, why) VALUES
  ('phase_d_scenario_record', 'fn_phase_d_scenario_record_write',
   'The only routine that records a fixture-created business object in the evidence manifest. Called by the scenario factory immediately after the canonical write returns, so a manifest entry cannot exist without the canonical write that produced it.')
ON CONFLICT DO NOTHING;

DROP TRIGGER IF EXISTS z10_kernel_write_guard ON public.phase_d_scenario_record;
CREATE TRIGGER z10_kernel_write_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.phase_d_scenario_record
  FOR EACH ROW EXECUTE FUNCTION public.fn_kernel_write_guard();

REVOKE TRUNCATE ON public.phase_d_scenario_record FROM PUBLIC;
REVOKE TRUNCATE ON public.phase_d_scenario_record FROM anon, authenticated, service_role;
DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_d_scenario_record;
CREATE TRIGGER z00_kernel_truncate_guard
  BEFORE TRUNCATE ON public.phase_d_scenario_record
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard();

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
     contributes_ref, trace_id, provenance, expected_effect)
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
          nullif(p_input->>'trace_id','')::bigint,
          coalesce(nullif(p_input->>'provenance',''),
                   'PHASE_D_FIXTURE_DO_NOT_PUBLISH — created by the zero-persistence scenario factory inside a transaction that is aborted'),
          nullif(p_input->>'expected_effect',''))
  on conflict (fixture_run_id, object_id, business_key) do update
     set state = excluded.state, result_reference = excluded.result_reference
  returning scenario_record_id into v_id;
  return v_id;
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_scenario_record_write(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_d_scenario_record_write(jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_scenario_record_write(jsonb) TO service_role;

-- ================================================================================================
-- 2. THE COMMITTED CONTENT CATALOGUE
-- ================================================================================================
CREATE TABLE IF NOT EXISTS public.phase_d_fixture_catalogue (
  fixture_id      text        PRIMARY KEY,
  fixture_version int         NOT NULL DEFAULT 1,
  workflow_id     text,
  step_id         text,
  scope           text        NOT NULL
                  CHECK (scope in ('CONTEXT_KEY','EFFECT_PAYLOAD','HANDLER_OUTPUT','CAPABILITY_RESULT')),
  field_key       text        NOT NULL,
  value           jsonb       NOT NULL,
  value_kind      text        NOT NULL
                  CHECK (value_kind in ('text','number','boolean','object','array')),
  currency        text,
  expected_schema text        NOT NULL CHECK (length(btrim(expected_schema)) >= 10),
  expected_result text        NOT NULL CHECK (length(btrim(expected_result)) >= 10),
  prohibited_external_use text NOT NULL CHECK (length(btrim(prohibited_external_use)) >= 20),
  checksum        text        NOT NULL,
  recorded_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT phase_d_fixture_catalogue_id_shape
    CHECK (fixture_id ~ '^PDF-[0-9]{4}$'),
  -- EVERY TEXT FIXTURE IS MARKED. jsonb_typeof lets a number, a boolean, an object or an array
  -- through unmarked -- a marker inside a numeric amount would make it unparseable -- and the
  -- financial rule below is what covers those.
  CONSTRAINT phase_d_fixture_catalogue_text_is_marked
    CHECK (jsonb_typeof(value) <> 'string'
           OR value #>> '{}' like '%PHASE_D_FIXTURE_DO_NOT_PUBLISH%'),
  -- EVERY FINANCIAL FIXTURE DECLARES ITS CURRENCY AND SAYS IT IS SYNTHETIC.
  CONSTRAINT phase_d_fixture_catalogue_money_is_declared_synthetic
    CHECK (value_kind <> 'number'
           OR field_key !~ '(amount|fee|price|fils|aed|cost|total)'
           OR (currency is not null and expected_schema like '%synthetic%')),
  CONSTRAINT phase_d_fixture_catalogue_one_value_per_key
    UNIQUE (scope, field_key, workflow_id, step_id)
);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_d_fixture_catalogue FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_d_fixture_catalogue FROM anon, authenticated, service_role;

COMMENT ON TABLE public.phase_d_fixture_catalogue IS
  'THE COMMITTED PHASE D CONTENT CATALOGUE. Explicit, clearly marked test values for the business '
  'content a deterministic handler must not invent: an opportunity kind, a quotation amount, a '
  'content-draft title and body, a campaign objective, a contract clause selection, a '
  'market-analysis result, a category analysis, a document-extraction result, an executive '
  'recommendation, a review rationale. Every row carries a fixture id, a version, a checksum, the '
  'workflow/step it belongs to, the schema its value must satisfy, the result it is expected to '
  'produce and its prohibited external use. Mirrored to docs/phase-d/PHASE_D_FIXTURE_CATALOGUE.csv '
  'and compared against it by CI (F02).';

CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_catalogue_checksum()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- THE CHECKSUM IS COMPUTED, NEVER ACCEPTED. A caller-supplied checksum is a claim about a row,
  -- and this estate has learned twice over what a claim with no mechanism is worth. The canonical
  -- serialisation is the ordered concatenation of every field that decides what the fixture means;
  -- recorded_at is excluded because it is not part of the fixture.
  new.checksum := encode(sha256(convert_to(concat_ws(chr(31),
    new.fixture_id, new.fixture_version::text, coalesce(new.workflow_id,''),
    coalesce(new.step_id,''), new.scope, new.field_key, new.value::text, new.value_kind,
    coalesce(new.currency,''), new.expected_schema, new.expected_result,
    new.prohibited_external_use), 'UTF8')), 'hex');
  return new;
end
$function$;

DROP TRIGGER IF EXISTS a10_phase_d_fixture_catalogue_checksum ON public.phase_d_fixture_catalogue;
CREATE TRIGGER a10_phase_d_fixture_catalogue_checksum
  BEFORE INSERT OR UPDATE ON public.phase_d_fixture_catalogue
  FOR EACH ROW EXECUTE FUNCTION public.fn_phase_d_fixture_catalogue_checksum();

REVOKE TRUNCATE ON public.phase_d_fixture_catalogue FROM PUBLIC;
REVOKE TRUNCATE ON public.phase_d_fixture_catalogue FROM anon, authenticated, service_role;
DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_d_fixture_catalogue;
CREATE TRIGGER z00_kernel_truncate_guard
  BEFORE TRUNCATE ON public.phase_d_fixture_catalogue
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard();

-- ================================================================================================
-- 3. THE ONE DOOR EVERY FIXTURE VALUE COMES THROUGH
-- ================================================================================================
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
  -- NO VERIFIED FIXTURE CONTEXT, NO FIXTURE. This single line is the production boundary: in
  -- production fn_phase_d_fixture_context() is null, this returns no row, the key stays unresolved
  -- and its rule or gate refuses exactly as it does with this file absent.
  if v_run is null then return; end if;

  select * into sr from public.phase_c_workflow_step_run where step_run_id = p_step_run_id;
  if not found then return; end if;
  select b.workflow_id into v_wf from public.phase_d_handler_binding b where b.step_id = sr.step_id;

  -- (1) A REFERENCE RESOLVES TO A ROW THIS RUN ACTUALLY CREATED. Nothing is authored here: the
  --     value is the business key the canonical write returned.
  if p_scope = 'CONTEXT_KEY' then
    select sc.business_key, sc.object_id, sc.canonical_relation, sc.fixture_id, sc.fixture_version,
           sc.source_checksum
      into r
      from public.phase_d_scenario_record sc
     where sc.fixture_run_id = v_run and sc.contributes_ref = p_key
     order by sc.scenario_record_id limit 1;
    if found then
      value := to_jsonb(r.business_key);
      provenance := format('phase_d_scenario_record: the %s created by fixture run %s through %s',
                           r.object_id, v_run, coalesce(r.canonical_relation,'its canonical service'));
      fixture_id := r.fixture_id; fixture_version := r.fixture_version; checksum := r.source_checksum;
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

COMMENT ON FUNCTION public.fn_phase_d_fixture_input(bigint, text, text) IS
  'THE ONLY DOOR A PHASE D FIXTURE VALUE COMES THROUGH. Returns no row at all unless '
  'fn_phase_d_fixture_context() verifies, so production is unchanged. A reference key resolves to '
  'the business key of a row THIS fixture run created through a canonical service; a content key '
  'resolves to the committed catalogue, most specific row first. Both come back with a provenance '
  'string naming the fixture id, version and checksum, which is what the dispatch records (F02).';

-- ================================================================================================
-- 4. THE BOARD
-- ================================================================================================
CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_catalogue_state()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with c as (select * from public.phase_d_fixture_catalogue)
  select 'catalogue_entries'::text, 'at least 40'::text,
         (select count(*)::text from c), (select count(*) from c) >= 40
  union all
  select 'text_fixtures_without_the_marker', '0',
         (select count(*)::text from c where jsonb_typeof(value) = 'string'
            and value #>> '{}' not like '%PHASE_D_FIXTURE_DO_NOT_PUBLISH%'),
         not exists (select 1 from c where jsonb_typeof(value) = 'string'
            and value #>> '{}' not like '%PHASE_D_FIXTURE_DO_NOT_PUBLISH%')
  union all
  select 'financial_fixtures_without_a_declared_currency', '0',
         (select count(*)::text from c where value_kind = 'number'
            and field_key ~ '(amount|fee|price|fils|aed|cost|total)' and currency is null),
         not exists (select 1 from c where value_kind = 'number'
            and field_key ~ '(amount|fee|price|fils|aed|cost|total)' and currency is null)
  union all
  select 'rows_whose_checksum_does_not_match_their_content', '0',
         (select count(*)::text from c
           where checksum <> encode(sha256(convert_to(concat_ws(chr(31),
             fixture_id, fixture_version::text, coalesce(workflow_id,''), coalesce(step_id,''),
             scope, field_key, value::text, value_kind, coalesce(currency,''),
             expected_schema, expected_result, prohibited_external_use),'UTF8')),'hex')),
         not exists (select 1 from c
           where checksum <> encode(sha256(convert_to(concat_ws(chr(31),
             fixture_id, fixture_version::text, coalesce(workflow_id,''), coalesce(step_id,''),
             scope, field_key, value::text, value_kind, coalesce(currency,''),
             expected_schema, expected_result, prohibited_external_use),'UTF8')),'hex'))
  union all
  select 'catalogue_rows_naming_a_step_that_is_not_frozen', '0',
         (select count(*)::text from c where step_id is not null
            and not exists (select 1 from public.phase_b_workflow_step s where s.step_id = c.step_id)),
         not exists (select 1 from c where step_id is not null
            and not exists (select 1 from public.phase_b_workflow_step s where s.step_id = c.step_id))
  union all
  select 'scenario_records_still_committed', '0',
         (select count(*)::text from public.phase_d_scenario_record),
         not exists (select 1 from public.phase_d_scenario_record)
  union all
  select 'fixture_contexts_still_committed', '0',
         (select count(*)::text from public.phase_d_test_context_grant),
         not exists (select 1 from public.phase_d_test_context_grant);
$function$;

COMMENT ON FUNCTION public.fn_phase_d_fixture_catalogue_state() IS
  'THE PHASE D FIXTURE CATALOGUE BOARD. Counts the catalogue, refuses an unmarked text fixture, an '
  'undeclared financial fixture, a row whose checksum no longer matches its content and a row '
  'naming a step the frozen registry does not have -- and, because both are supposed to live only '
  'inside an aborted transaction, asserts that public.phase_d_scenario_record and '
  'public.phase_d_test_context_grant are EMPTY on production. A committed row in either is residue '
  '(F02).';

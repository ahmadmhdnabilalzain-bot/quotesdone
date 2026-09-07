-- F43 - one canonical reference for every business object, derived from the frozen 56-object map
--
-- THE DEFECT THIS CLOSES, measured across the whole estate rather than one workflow at a time.
-- The same business object was identified four different ways depending on who was asking:
--
--   public.phase_d_scenario_record.business_key   the primary key of the row in the real relation
--   public.phase_d_object_record.business_key     a derived key of the Phase D store
--   the context resolver                          whichever of those a stage happened to contribute
--   the rules                                     whichever of those their own body looked up
--
-- Measured 22 Aug 2026 inside one fixture scenario: customer_terms_acceptance was 44779 on the
-- scenario record and a0744275-... on the object record, and the two matched on 0 rows. Every rule
-- that reads public.phase_d_object_record therefore refused an object that had been created,
-- approved and left in exactly the state it asked for. F42 fixed two references by reclassifying
-- two stages; that was the right shape and the wrong scale, and the founder's ruling of 23 Aug 2026
-- says so: "Do not work around this one workflow or rule at a time. Implement one canonical
-- reference contract and migrate every Phase D execution path to it."
--
-- WHAT A REFERENCE IS, FROM HERE ON. One envelope, the same shape for all 56 objects:
--
--   {"object_id": ..., "storage_kind": "PHASE_D_STORE|EXISTING_TABLE|KERNEL_OWNED",
--    "business_key": ..., "version": n,
--    "physical_ref": {"schema": ..., "relation": ..., "pk_column": ..., "pk_value": ...},
--    "owner_scope": "CUSTOMER|SUPPLIER|COMPANY", "owner_ref": ...,
--    "source_object_ref": ..., "trace_id": ..., "fixture_run_id": ...}
--
-- The business identity and the physical identity are BOTH carried, and which one is canonical is a
-- property of the object, recorded once. Nothing downstream guesses, and nothing downstream has to.
--
-- THE STRATEGY REGISTRY IS DERIVED, NOT TYPED. Every row below comes from
-- public.phase_d_business_object_binding, which is the frozen map, plus the write map and the state
-- contract. A hand-typed list of 56 objects would be an expectation checked against itself and
-- would go stale the first time a binding moved -- this estate has been bitten by that exact shape.
-- The derivation is a single INSERT ... SELECT and re-running it is idempotent.
--
--   relation_kind = 'PHASE_D_OBJECT_VIEW'        -> PHASE_D_STORE   (30 objects)
--   canonical_relation like 'public.phase_c_%'   -> KERNEL_OWNED    (3 objects)
--   otherwise                                    -> EXISTING_TABLE  (23 objects)
--
-- A REFERENCE THAT CANNOT BE RESOLVED IS AN ERROR, NOT A NULL. fn_phase_d_ref_resolve refuses with
-- pd_ref_unknown_object, pd_ref_unresolved or pd_ref_ambiguous. The estate's recurring defect is a
-- resolver that answers with something plausible -- a row id where a digest was wanted, the first of
-- several matches -- and every one of those refusals exists so that cannot happen again.

begin;

-- ---- 1. THE REGISTRY --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.phase_d_object_reference_strategy (
  object_id                text PRIMARY KEY,
  storage_kind             text NOT NULL
                             CHECK (storage_kind in ('PHASE_D_STORE','EXISTING_TABLE','KERNEL_OWNED')),
  canonical_identity_type  text NOT NULL
                             CHECK (canonical_identity_type in
                                    ('OBJECT_ID_BUSINESS_KEY_VERSION','RELATION_PRIMARY_KEY','KERNEL_ID')),
  physical_schema          text NOT NULL,
  physical_relation        text NOT NULL,
  physical_pk_column       text NOT NULL,
  business_key_derivation  text NOT NULL,
  version_rule             text NOT NULL,
  ownership_rule           text NOT NULL,
  reader                   text NOT NULL,
  writer                   text NOT NULL,
  evidence_lookup          text NOT NULL,
  fixture_creation_service text NOT NULL,
  trace_relationship       text NOT NULL,
  derived_at               timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.phase_d_object_reference_strategy IS
  'How each of the 56 frozen business objects is identified, and by which service. Derived '
  'mechanically from public.phase_d_business_object_binding, public.phase_d_object_write_map and '
  'public.phase_d_object_state_contract by F43 -- never typed. A hand-written list would be an '
  'expectation checked against itself and would go stale the first time a binding moved.';

REVOKE ALL ON public.phase_d_object_reference_strategy FROM PUBLIC;
REVOKE ALL ON public.phase_d_object_reference_strategy FROM anon, authenticated;
GRANT SELECT ON public.phase_d_object_reference_strategy TO service_role;

-- Derived. Idempotent: re-running refreshes every column from the binding.
INSERT INTO public.phase_d_object_reference_strategy
  (object_id, storage_kind, canonical_identity_type, physical_schema, physical_relation,
   physical_pk_column, business_key_derivation, version_rule, ownership_rule, reader, writer,
   evidence_lookup, fixture_creation_service, trace_relationship)
SELECT
  b.object_id,
  case when b.relation_kind = 'PHASE_D_OBJECT_VIEW'          then 'PHASE_D_STORE'
       when b.canonical_relation like 'public.phase_c!_%' escape '!' then 'KERNEL_OWNED'
       else 'EXISTING_TABLE' end,
  case when b.relation_kind = 'PHASE_D_OBJECT_VIEW'          then 'OBJECT_ID_BUSINESS_KEY_VERSION'
       when b.canonical_relation like 'public.phase_c!_%' escape '!' then 'KERNEL_ID'
       else 'RELATION_PRIMARY_KEY' end,
  coalesce(nullif(split_part(b.canonical_relation, '.', 1), ''), 'public'),
  case when position('.' in b.canonical_relation) > 0
       then split_part(b.canonical_relation, '.', 2) else b.canonical_relation end,
  case when b.relation_kind = 'PHASE_D_OBJECT_VIEW' then 'business_key'
       else coalesce(nullif(btrim(b.primary_identity),''), 'id') end,
  case when b.relation_kind = 'PHASE_D_OBJECT_VIEW'
       then 'deterministic: md5(phase_d_fixture:<fixture_run>:<object_id>:<run_id>) inside a fixture '
            || 'run, or the caller-supplied key derived from the run business_object_id prefix'
       else 'the canonical relation''s own primary key, ' || coalesce(nullif(btrim(b.primary_identity),''),'id')
            || ', assigned by the relation' end,
  coalesce(nullif(btrim(b.versioning),''), '(not stated on the frozen binding)'),
  b.ownership_scope || case when coalesce(btrim(b.ownership_column),'') = '' then ' (no ownership column on the relation)'
                            else ' via ' || b.ownership_column end,
  coalesce(nullif(btrim(b.canonical_read_service),''), 'fn_phase_d_object_read'),
  coalesce(nullif(btrim(b.canonical_write_service),''), 'fn_phase_d_object_write'),
  case when b.relation_kind = 'PHASE_D_OBJECT_VIEW'
       then 'public.phase_d_object_record where object_id = <object_id> and business_key = <business_key>'
       else 'public.' || case when position('.' in b.canonical_relation) > 0
                              then split_part(b.canonical_relation,'.',2) else b.canonical_relation end
            || ' where ' || coalesce(nullif(btrim(b.primary_identity),''),'id') || ' = <pk_value>' end,
  case when exists (select 1 from public.phase_d_fixture_stage s where s.object_id = b.object_id)
       then 'fn_phase_d_fixture_scenario stage ' ||
            (select min(s.stage_key) from public.phase_d_fixture_stage s where s.object_id = b.object_id)
       else 'no fixture stage creates this object; it is created by a handler effect or not at all' end,
  coalesce(nullif(btrim(b.trace_relationship),''), '(not stated on the frozen binding)')
FROM public.phase_d_business_object_binding b
ON CONFLICT (object_id) DO UPDATE SET
  storage_kind             = excluded.storage_kind,
  canonical_identity_type  = excluded.canonical_identity_type,
  physical_schema          = excluded.physical_schema,
  physical_relation        = excluded.physical_relation,
  physical_pk_column       = excluded.physical_pk_column,
  business_key_derivation  = excluded.business_key_derivation,
  version_rule             = excluded.version_rule,
  ownership_rule           = excluded.ownership_rule,
  reader                   = excluded.reader,
  writer                   = excluded.writer,
  evidence_lookup          = excluded.evidence_lookup,
  fixture_creation_service = excluded.fixture_creation_service,
  trace_relationship       = excluded.trace_relationship,
  derived_at               = now();

commit;

-- ---- 2. BUILD ---------------------------------------------------------------------------------
-- Takes what a caller actually has -- an object and an identity -- and returns the full envelope.
-- It does NOT verify that the row exists; that is fn_phase_d_ref_resolve's job, and keeping them
-- apart is what lets a reference be built for an object about to be created and resolved after.
CREATE OR REPLACE FUNCTION public.fn_phase_d_ref(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'pg_temp'
AS $function$
declare
  s        public.phase_d_object_reference_strategy%rowtype;
  b        public.phase_d_business_object_binding%rowtype;
  v_obj    text := nullif(btrim(coalesce(p_input->>'object_id','')),'');
  v_ident  text := nullif(btrim(coalesce(p_input->>'identity','')),'');
  v_ver    int  := nullif(btrim(coalesce(p_input->>'version','')),'')::int;
  v_owner  text := nullif(btrim(coalesce(p_input->>'owner_ref','')),'');
begin
  if v_obj is null then
    raise exception 'fn_phase_d_ref: object_id is required (pd_ref_unknown_object)'
      using errcode = '22023';
  end if;

  select * into s from public.phase_d_object_reference_strategy where object_id = v_obj;
  if not found then
    raise exception 'fn_phase_d_ref: % is not one of the 56 frozen business objects, so no reference strategy exists for it (pd_ref_unknown_object)',
      v_obj using errcode = '23503';
  end if;
  select * into b from public.phase_d_business_object_binding where object_id = v_obj;

  -- THE IDENTITY IS REQUIRED AND IS NEVER INVENTED. A reference with no identity is the defect this
  -- whole contract exists to remove: it is what let a resolver pick whichever key was nearest.
  if v_ident is null then
    raise exception 'fn_phase_d_ref: % needs an identity (%). A reference with no identity is not a reference. (pd_ref_unresolved)',
      v_obj,
      case s.canonical_identity_type
        when 'OBJECT_ID_BUSINESS_KEY_VERSION' then 'its business key'
        else 'its ' || s.physical_relation || '.' || s.physical_pk_column end
      using errcode = '22023';
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'object_id',    v_obj,
    'storage_kind', s.storage_kind,
    'business_key', case when s.storage_kind = 'PHASE_D_STORE' then v_ident else v_ident end,
    'version',      coalesce(v_ver, 1),
    'physical_ref', jsonb_build_object(
                      'schema',    s.physical_schema,
                      'relation',  s.physical_relation,
                      'pk_column', case when s.storage_kind = 'PHASE_D_STORE'
                                        then 'business_key' else s.physical_pk_column end,
                      'pk_value',  v_ident),
    'owner_scope',  b.ownership_scope,
    'owner_ref',    v_owner,
    'source_object_ref', p_input->'source_object_ref',
    'trace_id',     nullif(btrim(coalesce(p_input->>'trace_id','')),''),
    'fixture_run_id', nullif(btrim(coalesce(p_input->>'fixture_run_id','')),'')::bigint));
end
$function$;

REVOKE EXECUTE ON FUNCTION public.fn_phase_d_ref(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_ref(jsonb) TO service_role;

COMMENT ON FUNCTION public.fn_phase_d_ref(jsonb) IS
  'Builds the canonical reference envelope for one business object from its object_id and identity, '
  'using the strategy registry. Does not check that the row exists -- that is fn_phase_d_ref_resolve '
  '-- so a reference can be built for an object about to be created. F43.';

-- ---- 3. RESOLVE -------------------------------------------------------------------------------
-- Exactly one object and version, or an explicit refusal. The storage kind selects the lookup
-- MECHANICALLY: there is no fallback chain and no second guess.
CREATE OR REPLACE FUNCTION public.fn_phase_d_ref_resolve(p_ref jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'pg_temp'
AS $function$
declare
  s       public.phase_d_object_reference_strategy%rowtype;
  v_obj   text := nullif(btrim(coalesce(p_ref->>'object_id','')),'');
  v_key   text := nullif(btrim(coalesce(p_ref->'physical_ref'->>'pk_value',
                                        p_ref->>'business_key','')),'');
  v_ver   int  := nullif(btrim(coalesce(p_ref->>'version','')),'')::int;
  v_n     int;
  v_rec   record;
  v_sql   text;
begin
  if v_obj is null or v_key is null then
    raise exception 'fn_phase_d_ref_resolve: a reference must name an object_id and an identity; got % / % (pd_ref_unresolved)',
      coalesce(v_obj,'(none)'), coalesce(v_key,'(none)') using errcode = '22023';
  end if;

  select * into s from public.phase_d_object_reference_strategy where object_id = v_obj;
  if not found then
    raise exception 'fn_phase_d_ref_resolve: % is not one of the 56 frozen business objects (pd_ref_unknown_object)',
      v_obj using errcode = '23503';
  end if;

  if s.storage_kind = 'PHASE_D_STORE' then
    -- THE VERSION IS PART OF THE IDENTITY. With no version the live one is the record that has not
    -- been superseded; with a version it is that version exactly, superseded or not, because
    -- evidence about what was approved must stay readable after a later revision.
    if v_ver is null then
      select count(*) into v_n from public.phase_d_object_record
       where object_id = v_obj and business_key = v_key and superseded_by is null;
    else
      select count(*) into v_n from public.phase_d_object_record
       where object_id = v_obj and business_key = v_key and version = v_ver;
    end if;

    if v_n = 0 then
      raise exception 'fn_phase_d_ref_resolve: % / % %resolves to no record in public.phase_d_object_record (pd_ref_unresolved)',
        v_obj, v_key, case when v_ver is null then '' else 'version ' || v_ver || ' ' end
        using errcode = '23503';
    elsif v_n > 1 then
      raise exception 'fn_phase_d_ref_resolve: % / % %resolves to % records; a reference must name exactly one (pd_ref_ambiguous)',
        v_obj, v_key, case when v_ver is null then '' else 'version ' || v_ver || ' ' end, v_n
        using errcode = '23505';
    end if;

    if v_ver is null then
      select record_id, business_key, version, state, owner_scope, owner_ref, trace_id
        into v_rec from public.phase_d_object_record
       where object_id = v_obj and business_key = v_key and superseded_by is null;
    else
      select record_id, business_key, version, state, owner_scope, owner_ref, trace_id
        into v_rec from public.phase_d_object_record
       where object_id = v_obj and business_key = v_key and version = v_ver;
    end if;

    return jsonb_build_object(
      'ok', true, 'object_id', v_obj, 'storage_kind', s.storage_kind,
      'business_key', v_rec.business_key, 'version', v_rec.version, 'state', v_rec.state,
      'owner_scope', v_rec.owner_scope, 'owner_ref', v_rec.owner_ref,
      'trace_id', v_rec.trace_id,
      'physical_ref', jsonb_build_object('schema','public','relation','phase_d_object_record',
                                         'pk_column','record_id','pk_value', v_rec.record_id::text));
  end if;

  -- EXISTING_TABLE and KERNEL_OWNED: the relation's own primary key, compared as text so a uuid, a
  -- bigint and a natural key all work without the caller having to know which it is.
  v_sql := format('select count(*) from %I.%I where %I::text = $1',
                  s.physical_schema, s.physical_relation, s.physical_pk_column);
  execute v_sql into v_n using v_key;

  if v_n = 0 then
    raise exception 'fn_phase_d_ref_resolve: % / % resolves to no row in %.% by % (pd_ref_unresolved)',
      v_obj, v_key, s.physical_schema, s.physical_relation, s.physical_pk_column
      using errcode = '23503';
  elsif v_n > 1 then
    raise exception 'fn_phase_d_ref_resolve: % / % resolves to % rows in %.%; a reference must name exactly one (pd_ref_ambiguous)',
      v_obj, v_key, v_n, s.physical_schema, s.physical_relation
      using errcode = '23505';
  end if;

  return jsonb_build_object(
    'ok', true, 'object_id', v_obj, 'storage_kind', s.storage_kind,
    'business_key', v_key, 'version', coalesce(v_ver, 1),
    'physical_ref', jsonb_build_object('schema', s.physical_schema, 'relation', s.physical_relation,
                                       'pk_column', s.physical_pk_column, 'pk_value', v_key));
end
$function$;

REVOKE EXECUTE ON FUNCTION public.fn_phase_d_ref_resolve(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_ref_resolve(jsonb) TO service_role;

COMMENT ON FUNCTION public.fn_phase_d_ref_resolve(jsonb) IS
  'Resolves a canonical reference to exactly one object and version, or refuses with '
  'pd_ref_unknown_object, pd_ref_unresolved or pd_ref_ambiguous. The storage kind selects the lookup '
  'mechanically: no fallback chain, no second guess, no answering with the nearest key. F43.';

-- ---- 4. THE BOARD -----------------------------------------------------------------------------
-- ROUTINE REMOVED 7 September 2026. public.fn_phase_d_reference_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


REVOKE EXECUTE ON FUNCTION public.fn_phase_d_reference_state() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_reference_state() TO service_role;

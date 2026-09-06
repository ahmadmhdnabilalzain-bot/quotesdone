CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_effect_payload(p_step_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_run bigint := public.fn_phase_d_fixture_context();
  sr    public.phase_c_workflow_step_run%rowtype;
  e     public.phase_d_step_effect%rowtype;
  v_rel text;
  v_out jsonb := '{}'::jsonb;
  r     record;
  fi    record;
  v_ctx_val jsonb;   -- G14: what the step context already resolved for this key
begin
  -- NO VERIFIED FIXTURE CONTEXT, NO CONTENT. In production this returns an empty object, the
  -- effect payload is exactly what it is today, and a NOT NULL column with no value still raises
  -- 23502 and is still classified pd_effect_payload_incomplete.
  if v_run is null then return '{}'::jsonb; end if;

  select * into sr from public.phase_c_workflow_step_run where step_run_id = p_step_run_id;
  if not found then return '{}'::jsonb; end if;
  select * into e from public.phase_d_step_effect where step_id = sr.step_id;
  if not found then return '{}'::jsonb; end if;

  select wm.target_relation into v_rel from public.phase_d_object_write_map wm
   where wm.object_id = e.effect_object_id;

  -- THE POPULATION IS THE COLUMNS THE TARGET RELATION ACTUALLY DEMANDS, read from the catalogue of
  -- the database rather than listed by hand. A column that is NOT NULL, has no default, is not
  -- generated, and is mapped by the object's write map to a payload key -- that is exactly the set
  -- fn_phase_d_effect_produce raises 23502 on today.
  if v_rel is not null and to_regclass(v_rel) is not null then
    for r in
      with m as (
        select k.col, k.key
          from public.phase_d_object_write_map wm,
               lateral jsonb_each_text(wm.column_map) k(col, key)
         where wm.object_id = e.effect_object_id)
      select m.key as src
        from m
        join pg_attribute a on a.attrelid = to_regclass(v_rel) and a.attname = m.col
        left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
       where a.attnum > 0 and a.attidentity = '' and a.attgenerated = ''
         and m.key not in ('business_key','owner_ref','state')
         and (   (a.attnotnull and d.adbin is null)
              -- H04 (3). A mapped column the committed catalogue speaks for, at this step or in
              -- this workflow. Scoped rows only: a global fixture fills nothing here.
              or exists (select 1 from public.phase_d_fixture_catalogue c
                          where c.scope = 'EFFECT_PAYLOAD' and c.field_key = m.key
                            and (c.step_id = sr.step_id
                                 or (c.step_id is null and c.workflow_id = e.workflow_id))))
    loop
      -- G14. A KEY THAT NAMES A ROW IS ANSWERED FROM THE ROW, NOT FROM A CONSTANT.
      -- Five of the sixteen keys in this population name something: inquiry_id, transaction_id,
      -- group_id, field_id, requested_by. fn_phase_d_step_context resolves an object key from the
      -- object it names, from a declared foreign key on the run's own relation, or from the
      -- canonical reference the scenario recorded -- so it is asked first, and the committed
      -- catalogue answers only what it could not. Handing a committed constant to a key that names
      -- a row is the mistake this estate has now corrected four times in one session.
      v_ctx_val := (public.fn_phase_d_step_context(p_step_run_id))->'context'->(r.src);
      if v_ctx_val is not null and v_ctx_val <> 'null'::jsonb then
        v_out := v_out || jsonb_build_object(r.src, v_ctx_val);
        continue;
      end if;
      -- H04 (1). A KEY THAT NAMES AN OBJECT IS ANSWERED FROM THE OBJECT THE SCENARIO CREATED, whether
      -- or not this step's rules declared the key. The register is public.phase_d_context_key_object;
      -- the identity is the canonical reference the scenario recorded for that object.
      select to_jsonb(sc.canonical_ref->>'canonical_identity') into v_ctx_val
        from public.phase_d_context_key_object cko
        join public.phase_d_scenario_record sc
          on sc.object_id = cko.object_id and sc.fixture_run_id = v_run
       where cko.context_key = r.src and cko.key_role = 'IDENTIFIES'
         and coalesce(btrim(sc.canonical_ref->>'canonical_identity'),'') <> ''
       order by sc.scenario_record_id desc
       limit 1;
      if v_ctx_val is not null then
        v_out := v_out || jsonb_build_object(r.src, v_ctx_val);
        continue;
      end if;
      select * into fi from public.fn_phase_d_fixture_input(p_step_run_id, 'EFFECT_PAYLOAD', r.src) fi;
      if fi.value is not null then
        -- H04 (2). A CONSTANT CANNOT BE AN IDENTITY. Where this column belongs to a UNIQUE index of
        -- the target relation, the step run id is appended so each versioned row of one run is its
        -- own row and a replay of the same step run lands on the same value.
        if jsonb_typeof(fi.value) = 'string'
           and exists (select 1
                         from pg_index i
                         join pg_attribute a2 on a2.attrelid = i.indrelid and a2.attnum = any(i.indkey)
                        where i.indrelid = to_regclass(v_rel) and i.indisunique
                          and a2.attname = (select m2.col
                                              from public.phase_d_object_write_map wm2,
                                                   lateral jsonb_each_text(wm2.column_map) m2(col, key)
                                             where wm2.object_id = e.effect_object_id and m2.key = r.src
                                             limit 1)) then
          v_out := v_out || jsonb_build_object(r.src,
                     to_jsonb((fi.value #>> '{}') || '/' || sr.step_id || '/' || p_step_run_id::text));
        else
          v_out := v_out || jsonb_build_object(r.src, fi.value);
        end if;
      end if;
    end loop;
  end if;

  -- The three effect types that demand named keys of their own, whatever the relation is.
  if e.expected_effect_type = 'EXTERNAL_EFFECT_INTENT' then
    for r in select unnest(array['recipient','consent_basis']) src loop
      select * into fi from public.fn_phase_d_fixture_input(p_step_run_id, 'EFFECT_PAYLOAD', r.src) fi;
      if fi.value is not null then v_out := v_out || jsonb_build_object(r.src, fi.value); end if;
    end loop;
    v_out := v_out || jsonb_build_object('suppressed', true);
  elsif e.expected_effect_type = 'MEASUREMENT_RECORD' then
    for r in select unnest(array['numerator','denominator']) src loop
      select * into fi from public.fn_phase_d_fixture_input(p_step_run_id, 'CONTEXT_KEY', r.src) fi;
      if fi.value is not null then v_out := v_out || jsonb_build_object(r.src, fi.value); end if;
    end loop;
  elsif e.expected_effect_type = 'REVIEW_VERDICT' then
    select * into fi from public.fn_phase_d_fixture_input(p_step_run_id, 'EFFECT_PAYLOAD', 'verdict') fi;
    if fi.value is not null then v_out := v_out || jsonb_build_object('verdict', fi.value); end if;
  end if;

  return v_out;
end
$function$

-- =================================================================================================
-- Phase D — D46. A contract that recorded intent and checked presence.
--
-- public.phase_d_handler_schema has nine columns and none of them is a type, a domain, a version or
-- an optionality marker. public.fn_phase_d_schema_validate checks exactly four things — the schema
-- exists, the payload is an object, every required key is PRESENT, and no required key is empty. So
-- all three payloads the acceptance audit sent were accepted:
--
--     every value the wrong type      status 12345, acceptance_assertions "not-an-array"   -> valid
--     an out-of-domain enum           status "purple-elephant"                             -> valid
--     invented keys                   refund_amount_aed 999999, __proto__ "polluted"       -> valid
--
-- A schema that accepts every payload is not a schema, and "schema changes are versioned" had no
-- mechanism at all: there was no version column.
--
-- WHERE THE TYPES AND THE DOMAIN COME FROM, AND WHERE THEY DO NOT.
--
-- The output schemas' own key_derivation names their authority: "kernel envelope (status, output)
-- required by public.fn_phase_c_output_validate, which the frozen fn_kernel_step_complete calls".
-- That routine is the declared source and it is read here rather than guessed:
--
--     status   it does  p_output->>'status' not in ('ok','success','completed','refused','empty')
--              -> type string, and a REAL frozen enum domain of five values
--     output   it does  coalesce(p_output->>'output',''), right(v_txt,3), length(v_txt)
--              -> type string
--
-- denominator and numerator are typed `number` because that is the fix for a gap the audit did not
-- name: fn_phase_d_handler_execute refuses a zero denominator only when
-- jsonb_typeof(v_output->'denominator') = 'number', and jsonb_typeof('"0"') is 'string', so a
-- denominator of "0" as text passed the guard AND passed the validator. A ratio over a string zero
-- is the least(100, NULL) defect in a different costume.
--
-- EVERY OTHER KEY IS RECORDED `unconstrained`, EXPLICITLY, ONE ROW AT A TIME. Nothing in the frozen
-- registry declares a vocabulary for `decision`, `verdict`, `authority_ref` or the rest, and
-- inventing one here would be this file deciding what the business has not. The audit's second
-- payload is still refused — but the reason names `status`, not `decision`, and the file says so
-- rather than letting a reader assume a decision vocabulary exists.
--
-- `unconstrained` is written as a value, never left as a column default. A key absent from
-- field_types is a FAILURE below, not a permissive pass: absent input scoring as satisfied is the
-- exact shape this phase exists to remove.
--
-- additional_properties: FALSE on the 257 output schemas, TRUE on the 257 input schemas, and both
-- stated rather than defaulted. An output is constructed by the executor from a closed contract, so
-- an unknown key there is a defect; `business_effect` is named in optional_keys because the executor
-- legitimately merges it. An input is a caller's context, and no declared source says a caller may
-- not carry more than the step names — so refusing extra input keys would be an invention too.
-- =================================================================================================


-- ---- 1. THE COLUMNS -----------------------------------------------------------------------------

alter table public.phase_d_handler_schema
  add column if not exists schema_version         int,
  add column if not exists field_types            jsonb,
  add column if not exists enum_domains           jsonb,
  add column if not exists optional_keys          text[],
  add column if not exists additional_properties  boolean,
  add column if not exists type_source            text;

comment on column public.phase_d_handler_schema.field_types is
  'One entry per required key AND per optional key. The value is a jsonb type name (string, number, '
  'boolean, array, object) or the literal ''unconstrained''. A key missing from this object makes '
  'fn_phase_d_schema_validate refuse the schema itself — an unstated type must not read as permissive.';
comment on column public.phase_d_handler_schema.enum_domains is
  'Only keys with a domain declared by a frozen source appear here. Today that is exactly one: '
  'status, from public.fn_phase_c_output_validate. Absence means unconstrained, which field_types '
  'states explicitly.';


-- ---- 2. THE VALUES, DERIVED ---------------------------------------------------------------------

update public.phase_d_handler_schema sc
   set schema_version = 1,
       additional_properties = (sc.schema_kind <> 'output'),
       optional_keys = case when sc.schema_kind = 'output'
                            then array['business_effect']::text[]
                            else '{}'::text[] end,
       type_source = case when sc.schema_kind = 'output'
         then 'status and output from public.fn_phase_c_output_validate (the authority this schema''s '
              'own key_derivation names); denominator and numerator number, which is what closes the '
              'string-denominator gap; every other key recorded unconstrained because no frozen '
              'source declares its type'
         else 'input keys are prose slugs of phase_b_workflow_step.required_inputs and no frozen '
              'source declares a type for any of them; all are recorded unconstrained, explicitly' end,
       enum_domains = case
         when sc.schema_kind = 'output' and sc.required_keys @> array['status']
           then jsonb_build_object('status',
                  jsonb_build_array('ok','success','completed','refused','empty'))
         else '{}'::jsonb end,
       field_types = (
         select coalesce(jsonb_object_agg(k, t), '{}'::jsonb)
           from (
             select k,
                    case
                      when sc.schema_kind <> 'output' then 'unconstrained'
                      when k in ('status','output')   then 'string'
                      when k in ('denominator','numerator') then 'number'
                      else 'unconstrained'
                    end as t
               from unnest(sc.required_keys
                           || case when sc.schema_kind = 'output'
                                   then array['business_effect']::text[] else '{}'::text[] end) k
           ) q)
 where true;

alter table public.phase_d_handler_schema
  alter column schema_version        set not null,
  alter column field_types           set not null,
  alter column enum_domains          set not null,
  alter column optional_keys         set not null,
  alter column additional_properties set not null,
  alter column type_source           set not null;

do $c$
begin
  if not exists (select 1 from pg_constraint where conname = 'phase_d_handler_schema_field_types_ck') then
    alter table public.phase_d_handler_schema
      add constraint phase_d_handler_schema_field_types_ck
      check (jsonb_typeof(field_types) = 'object' and field_types <> '{}'::jsonb);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'phase_d_handler_schema_version_ck') then
    alter table public.phase_d_handler_schema
      add constraint phase_d_handler_schema_version_ck check (schema_version >= 1);
  end if;
end
$c$;


-- ---- 3. THE VALIDATOR ---------------------------------------------------------------------------
-- The four existing checks are kept verbatim and run first; three are added after them. A payload
-- that used to be refused must still be refused, which the control below asserts.

create or replace function public.fn_phase_d_schema_validate(p_schema_id text, p_payload jsonb)
returns table(valid boolean, reason text, missing text[])
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $fn$
declare
  sc public.phase_d_handler_schema%rowtype;
  v_missing text[];
  v_empty   text[];
  v_untyped text[];
  v_wrong   text[];
  v_badenum text[];
  v_unknown text[];
  v_known   text[];
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

  -- ---- D46 (a) A KEY WITH NO RECORDED TYPE IS A BROKEN SCHEMA, NOT A PERMITTED ONE --------------
  -- If field_types does not mention a key the schema requires, the schema itself is refused. The
  -- alternative — treating an unstated type as "anything goes" — is how a missing declaration reads
  -- as a satisfied one.
  select array_agg(k order by k) into v_untyped
    from unnest(sc.required_keys) k where not (sc.field_types ? k);
  if v_untyped is not null then
    valid := false;
    reason := format('schema %s is incomplete: no declared type for [%s]. An unstated type is not an unconstrained one.',
                     p_schema_id, array_to_string(v_untyped, ', '));
    missing := v_untyped; return next; return;
  end if;

  -- ---- D46 (b) DECLARED TYPES ------------------------------------------------------------------
  select array_agg(format('%s expected %s got %s', k, sc.field_types->>k, jsonb_typeof(p_payload->k))
                   order by k)
    into v_wrong
    from unnest(sc.required_keys || coalesce(sc.optional_keys,'{}')) k
   where p_payload ? k
     and coalesce(sc.field_types->>k,'unconstrained') <> 'unconstrained'
     and jsonb_typeof(p_payload->k) is distinct from (sc.field_types->>k);
  if v_wrong is not null then
    valid := false;
    reason := format('schema %s: wrong types [%s]', p_schema_id, array_to_string(v_wrong, '; '));
    missing := '{}'; return next; return;
  end if;

  -- ---- D46 (c) DECLARED DOMAINS ----------------------------------------------------------------
  select array_agg(format('%s=%L is not one of [%s]', k, p_payload->>k,
                          (select string_agg(d, ', ')
                             from jsonb_array_elements_text(sc.enum_domains->k) d))
                   order by k)
    into v_badenum
    from jsonb_object_keys(sc.enum_domains) k
   where p_payload ? k
     and not (sc.enum_domains->k @> to_jsonb(p_payload->>k));
  if v_badenum is not null then
    valid := false;
    reason := format('schema %s: outside the declared domain [%s]',
                     p_schema_id, array_to_string(v_badenum, '; '));
    missing := '{}'; return next; return;
  end if;

  -- ---- D46 (d) UNKNOWN KEYS, WHERE THE CONTRACT IS CLOSED --------------------------------------
  if not coalesce(sc.additional_properties, true) then
    v_known := sc.required_keys || coalesce(sc.optional_keys, '{}');
    select array_agg(k order by k) into v_unknown
      from jsonb_object_keys(p_payload) k where not (k = any (v_known));
    if v_unknown is not null then
      valid := false;
      reason := format('schema %s declares a closed contract and the payload carries [%s]',
                       p_schema_id, array_to_string(v_unknown, ', '));
      missing := '{}'; return next; return;
    end if;
  end if;

  valid := true;
  reason := format('payload satisfies %s v%s (%s keys, %s typed, %s domain(s), %s, source digest %s)',
                   p_schema_id, sc.schema_version, cardinality(sc.required_keys),
                   (select count(*) from jsonb_each_text(sc.field_types) t
                     where t.value <> 'unconstrained'),
                   (select count(*) from jsonb_object_keys(sc.enum_domains)),
                   case when coalesce(sc.additional_properties,true)
                        then 'open to further keys' else 'closed' end,
                   left(sc.source_digest,12));
  missing := '{}'; return next;
end
$fn$;


-- ---- 4. THE BOARD — THE THREE PAYLOADS THAT PASSED ARE NOW CHECKS -------------------------------

create or replace function public.fn_phase_d_contract_state()
returns table(check_name text, expected text, actual text, ok boolean)
language sql
stable
as $fn$
  with p as (
    select 'schema_output_w17_s06'::text sid
  ),
  probe(nm, res) as (
    values
      ('wrong_types_are_refused',
       (select valid from public.fn_phase_d_schema_validate('schema_output_w17_s06',
         '{"status":12345,"output":true,"acceptance_assertions":"not-an-array","evidence_refs":99,
           "decision":[1,2],"rationale":{"x":1},"authority_ref":-1}'::jsonb))),
      ('out_of_domain_status_is_refused',
       (select valid from public.fn_phase_d_schema_validate('schema_output_w17_s06',
         '{"status":"purple-elephant","output":"o","acceptance_assertions":["a"],"evidence_refs":["e"],
           "decision":"NOT_A_DECISION","rationale":"r","authority_ref":"auth"}'::jsonb))),
      ('invented_keys_are_refused',
       (select valid from public.fn_phase_d_schema_validate('schema_output_w17_s06',
         '{"status":"ok","output":"o","acceptance_assertions":["a"],"evidence_refs":["e"],
           "decision":"APPROVE","rationale":"r","authority_ref":"auth",
           "totally_invented_field":"x","refund_amount_aed":999999}'::jsonb))),
      ('a_string_zero_denominator_is_refused',
       (select valid from public.fn_phase_d_schema_validate('schema_output_w02_s08',
         (select jsonb_object_agg(k, case when k='denominator' then to_jsonb('0'::text)
                                          when k='numerator' then to_jsonb(1)
                                          when k='status' then to_jsonb('ok'::text)
                                          when k in ('acceptance_assertions','evidence_refs')
                                               then jsonb_build_array('x')
                                          else to_jsonb('x'::text) end)
            from unnest((select required_keys from public.phase_d_handler_schema
                          where schema_id='schema_output_w02_s08')) k)))),
      ('a_conforming_payload_is_accepted',
       (select valid from public.fn_phase_d_schema_validate('schema_output_w17_s06',
         '{"status":"completed","output":"o","acceptance_assertions":["a"],"evidence_refs":["e"],
           "decision":"APPROVE","rationale":"r","authority_ref":"auth"}'::jsonb))),
      ('a_missing_required_key_is_still_refused',
       (select valid from public.fn_phase_d_schema_validate('schema_output_w17_s06',
         '{"status":"ok"}'::jsonb))),
      ('an_unknown_schema_is_still_refused',
       (select valid from public.fn_phase_d_schema_validate('schema_output_does_not_exist',
         '{"status":"ok"}'::jsonb)))
  )
  select nm,
         case when nm in ('a_conforming_payload_is_accepted') then 'accepted' else 'refused' end,
         case when res then 'accepted' else 'refused' end,
         case when nm in ('a_conforming_payload_is_accepted') then res else not res end
    from probe
  union all
  select 'every_schema_types_every_required_key', '0',
         (select count(*)::text from public.phase_d_handler_schema sc
           where exists (select 1 from unnest(sc.required_keys) k where not (sc.field_types ? k))),
         (select count(*) from public.phase_d_handler_schema sc
           where exists (select 1 from unnest(sc.required_keys) k where not (sc.field_types ? k))) = 0
  union all
  select 'every_schema_carries_a_version', '514',
         (select count(*)::text from public.phase_d_handler_schema where schema_version >= 1),
         (select count(*) from public.phase_d_handler_schema where schema_version >= 1) = 514;
$fn$;

revoke execute on function public.fn_phase_d_contract_state() from public, anon, authenticated;
grant  execute on function public.fn_phase_d_contract_state() to service_role;


-- ---- 5. CONTROL ---------------------------------------------------------------------------------
-- Every one of these seven had to be able to go both ways, and four of them passed before this file
-- and must now fail. That is the whole point: a check that has never been seen to move is not a check.

do $ctl$
declare r record; v_bad text := ''; v_n int;
begin
  for r in select * from public.fn_phase_d_contract_state() loop
    if not r.ok then
      v_bad := v_bad || format(' [%s expected %s got %s]', r.check_name, r.expected, r.actual);
    end if;
  end loop;
  if v_bad <> '' then
    raise exception 'D46: the contract board is red:%', v_bad;
  end if;

  -- The four existing checks must still be the reason a payload is refused when they apply, so the
  -- new ones cannot be masking a regression in the old ones.
  if (select reason from public.fn_phase_d_schema_validate('schema_output_w17_s06','{"status":"ok"}'::jsonb))
       not like '%required keys missing%' then
    raise exception 'D46: a payload missing six required keys is no longer refused for that reason.';
  end if;
  if (select reason from public.fn_phase_d_schema_validate('schema_output_w17_s06',
        '{"status":"","output":"o","acceptance_assertions":["a"],"evidence_refs":["e"],
          "decision":"d","rationale":"r","authority_ref":"a"}'::jsonb))
       not like '%present but empty%' then
    raise exception 'D46: an empty required key is no longer refused for that reason.';
  end if;

  -- The domain is the frozen one, not one this file invented.
  select count(*) into v_n from public.phase_d_handler_schema
   where schema_kind = 'output' and enum_domains ? 'status'
     and enum_domains->'status' = '["ok","success","completed","refused","empty"]'::jsonb;
  if v_n <> 257 then
    raise exception 'D46: % of 257 output schemas carry the frozen status domain from fn_phase_c_output_validate.', v_n;
  end if;

  -- unconstrained is a recorded value, never a default.
  if exists (select 1 from public.phase_d_handler_schema sc
              where exists (select 1 from unnest(sc.required_keys) k where not (sc.field_types ? k))) then
    raise exception 'D46: at least one required key has no entry in field_types.';
  end if;

  raise notice 'D46: %s',
    (select string_agg(format('%s=%s', check_name, actual), '  ' order by check_name)
       from public.fn_phase_d_contract_state());
end
$ctl$;

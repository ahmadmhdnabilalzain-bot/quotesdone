-- WHY (follow-up): zero-back-and-forth must never become zero-dispatch.
-- Two defects found while sweeping all 56 categories against the new gate:
--  1) 9 categories (solar, smart-home, swimming-pools, interior-design, it-networking,
--     epoxy-flooring, kitchens, marble-granite, roofing) declare required fields that have
--     a "question" but NO "key". They are unaddressable: no intake answer can ever be
--     stored against them, so gating on them would deadlock those categories forever.
--     They also made the function raise (FOREACH over a null array), which in a BEFORE
--     trigger would have blocked every insert for those categories.
--     Fix: keyless required fields are ADVISORY ONLY (surfaced, never blocking). Add a
--     "key" to those category_specs rows to promote them to real gates.
--  2) _rfq_concept matched "Emirate / area" to the quantity concept because 'area' was
--     tested before 'emirate'. Location is now tested first.

create or replace function public._rfq_concept(k text)
returns text language sql immutable
set search_path to 'public','pg_temp'
as $con$
  select case
    when k is null or btrim(k) = '' then null
    -- location first: "emirate / area" is a place, not a quantity
    when k ~ '(location|emirate|address|site|floor|region|area/|/area)' then 'loc'
    when k ~ '(quantity|qty|size|sizes|dimension|dimensions|area|volume|units|linear|count|sqm|sqft)' then 'qty'
    when k ~ '(scope|supply_install|install)'         then 'scope'
    when k ~ '(timeline|schedule|duration|deadline|when)' then 'time'
    when k ~ '(budget|price|cost)'                    then 'budget'
    when k ~ '(finish|material|fabric|fibre|colou?r)' then 'material'
    when k ~ '(item|product|element|service)'         then 'item'
    else null end;
$con$;

create or replace function public.fn_rfq_required_check(i public.inquiries)
returns jsonb language plpgsql stable security definer
set search_path to 'public','pg_temp'
as $chk$
declare
  spec_fields jsonb; f jsonb; bag jsonb := '{}'::jsonb; blob text;
  k text; v text; bk text; opt text; tok text; toks text[];
  reqn int := 0; have text[] := '{}';
  miss jsonb := '[]'::jsonb; advisory jsonb := '[]'::jsonb; found boolean;
begin
  select cs.fields into spec_fields
    from public.category_specs cs
   where lower(cs.category) = lower(coalesce(i.category,''))
   limit 1;

  if spec_fields is null or jsonb_typeof(spec_fields) <> 'array' then
    return jsonb_build_object('applicable', false, 'reason', 'no category_specs row',
      'category', i.category, 'required_ok', true, 'required_total', 0,
      'present','[]'::jsonb, 'missing','[]'::jsonb, 'advisory_missing','[]'::jsonb, 'checked_at', now());
  end if;

  if i.spec is not null and jsonb_typeof(i.spec) = 'object' then
    for k, v in
      select e.key, case when jsonb_typeof(e.value) in ('object','array')
                         then e.value::text else coalesce(e.value #>> '{}','') end
        from jsonb_each(i.spec) e
    loop
      bag := bag || jsonb_build_object(lower(k), v);
    end loop;

    for k, v in
      select e2.key, case when jsonb_typeof(e2.value) in ('object','array')
                          then e2.value::text else coalesce(e2.value #>> '{}','') end
        from jsonb_each(i.spec) e1
        join lateral jsonb_each(case when jsonb_typeof(e1.value)='object'
                                     then e1.value else '{}'::jsonb end) e2 on true
    loop
      if not public._rfq_answered(bag->>lower(k)) then
        bag := bag || jsonb_build_object(lower(k), v);
      end if;
    end loop;
  end if;

  bag := bag
    || case when coalesce(i.emirate,'') <> '' then
            jsonb_build_object('emirate', i.emirate,
              'location', coalesce(nullif(bag->>'location',''), i.emirate)) else '{}'::jsonb end
    || case when coalesce(i.scope_type,'') <> '' then
            jsonb_build_object('scope', coalesce(nullif(bag->>'scope',''), i.scope_type)) else '{}'::jsonb end
    || case when coalesce(i.budget,'') <> '' then jsonb_build_object('budget', i.budget) else '{}'::jsonb end
    || case when coalesce(array_length(i.trades,1),0) > 0 then
            jsonb_build_object('trades', array_to_string(i.trades,', ')) else '{}'::jsonb end
    || case when coalesce(i.drawing_file_path,'') <> '' or i.boq is not null then
            jsonb_build_object('drawing','provided') else '{}'::jsonb end;

  blob := lower(concat_ws(' ', i.summary, i.raw_input, i.spec::text));
  foreach tok in array coalesce(regexp_split_to_array(lower(coalesce(i.category,'')), '[^a-z0-9]+'), '{}'::text[]) loop
    if length(coalesce(tok,'')) >= 4 then blob := replace(blob, tok, ' '); end if;
  end loop;

  for f in select value from jsonb_array_elements(spec_fields)
            where coalesce((value->>'required')::boolean, false)
  loop
    k := nullif(btrim(lower(coalesce(f->>'key',''))), '');

    -- Keyless required field: unaddressable, so ADVISORY ONLY (never blocks dispatch).
    if k is null then
      advisory := advisory || jsonb_build_object(
        'question', f->>'question', 'reason', 'category_specs field has no key - cannot be gated');
      continue;
    end if;

    reqn := reqn + 1; found := false;

    if public._rfq_answered(bag->>k) then found := true; end if;

    if not found then
      for bk in select key from jsonb_each_text(bag) loop
        if public._rfq_answered(bag->>bk) then
          if public._rfq_concept(k) is not null
             and public._rfq_concept(k) = public._rfq_concept(bk) then
            found := true;
          else
            foreach tok in array coalesce(string_to_array(k,'_'), '{}'::text[]) loop
              if length(coalesce(tok,'')) >= 4
                 and (bk = tok or bk like '%'||tok||'%' or tok like '%'||bk||'%') then
                found := true;
              end if;
            end loop;
          end if;
        end if;
        exit when found;
      end loop;
    end if;

    if not found and jsonb_typeof(f->'options') = 'array' then
      for opt in select lower(o) from jsonb_array_elements_text(f->'options') o loop
        toks := coalesce(regexp_split_to_array(regexp_replace(coalesce(opt,''),'[^a-z0-9 ]',' ','g'), '\s+'), '{}'::text[]);
        foreach tok in array toks loop
          if length(coalesce(tok,'')) >= 4 and blob like '%'||tok||'%' then found := true; end if;
        end loop;
        exit when found;
      end loop;
    end if;

    if found then
      have := array_append(have, k);
    else
      miss := miss || jsonb_build_object('key', k, 'question', f->>'question', 'type', f->>'type');
    end if;
  end loop;

  return jsonb_build_object(
    'applicable', true, 'category', i.category,
    'required_total', reqn,
    'required_ok', (jsonb_array_length(miss) = 0),
    'present', to_jsonb(have),
    'missing', miss,
    'advisory_missing', advisory,
    'checked_at', now());
end $chk$;

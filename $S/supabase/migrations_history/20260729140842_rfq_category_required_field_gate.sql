-- WHY: The founder's goal is zero back-and-forth — a supplier must be able to quote
-- from the RFQ alone. Until now the ONLY gate before broadcast was fn_rfq_score, which
-- scores 6 GENERIC fields and dispatches at >= 70. An inquiry with no quantity and no
-- timeline could therefore reach 70 and be broadcast, guaranteeing back-and-forth.
-- Meanwhile category_specs.fields already declares the per-trade REQUIRED fields, and
-- inquiry_intake computes readiness/missing against them — but purely advisorily.
-- This migration makes those per-category required fields a REAL gate: rfq_ready is now
-- true only when the generic score passes AND no category-required field is missing.
-- The generic score is kept intact; the requirement is added on top.
--
-- DEADLOCK SAFETY: the intake brief does NOT use category_specs field keys (a brief has
-- quantity/location/timeline/details{...}, the spec asks for quantity_size/location_floor/
-- item_type). A naive key-equality check would mark a 100%-complete brief as missing and
-- freeze it forever. The resolver below therefore accepts an answer found by (a) exact key,
-- (b) synonym/concept or shared-token key match anywhere in the flattened brief and the
-- inquiry columns, or (c) the free text naming one of the field's enumerated options.
-- A category with no category_specs row is NOT gated (falls back to generic behaviour).

-- Is a stored answer actually an answer?
create or replace function public._rfq_answered(v text)
returns boolean language sql immutable
set search_path to 'public','pg_temp'
as $ans$
  select v is not null
     and btrim(v) <> ''
     and btrim(v) not in ('[]','{}','-','?')
     and lower(btrim(v)) not in ('null','not sure','unknown','tbd','n/a','na');
$ans$;

-- Map a field key onto a coarse concept so brief keys and spec keys can meet.
-- NOTE: 'category' is deliberately NOT an 'item' synonym — category is always present,
-- so treating it as an answer would make item-type fields trivially satisfied.
create or replace function public._rfq_concept(k text)
returns text language sql immutable
set search_path to 'public','pg_temp'
as $con$
  select case
    when k ~ '(quantity|qty|size|sizes|dimension|dimensions|area|volume|units|linear|count)' then 'qty'
    when k ~ '(location|emirate|address|site|floor|region)'                                  then 'loc'
    when k ~ '(scope|supply_install|install)'                                                then 'scope'
    when k ~ '(timeline|schedule|duration|deadline|when)'                                    then 'time'
    when k ~ '(budget|price|cost)'                                                           then 'budget'
    when k ~ '(finish|material|fabric|fibre|colou?r)'                                        then 'material'
    when k ~ '(item|product|element|service)'                                                then 'item'
    else null end;
$con$;

-- THE GATE. For one inquiry: which of its category's REQUIRED fields are answered?
create or replace function public.fn_rfq_required_check(i public.inquiries)
returns jsonb language plpgsql stable security definer
set search_path to 'public','pg_temp'
as $chk$
declare
  spec_fields jsonb; f jsonb; bag jsonb := '{}'::jsonb; blob text;
  k text; v text; bk text; opt text; tok text;
  reqn int := 0; have text[] := '{}'; miss jsonb := '[]'::jsonb; found boolean;
begin
  select cs.fields into spec_fields
    from public.category_specs cs
   where lower(cs.category) = lower(coalesce(i.category,''))
   limit 1;

  -- No spec for this category -> do NOT gate it (unmapped categories stay dispatchable).
  if spec_fields is null or jsonb_typeof(spec_fields) <> 'array' then
    return jsonb_build_object('applicable', false, 'reason', 'no category_specs row',
      'category', i.category, 'required_ok', true,
      'required_total', 0, 'present', '[]'::jsonb, 'missing', '[]'::jsonb, 'checked_at', now());
  end if;

  -- (1) Flatten the intake brief / spec: top level plus one nested object level (brief.details).
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

  -- (2) Structured inquiry columns count as answers too.
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

  -- (3) Free-text haystack, with the category's own words stripped out so that a field
  --     whose options happen to echo the category name is not trivially satisfied.
  blob := lower(concat_ws(' ', i.summary, i.raw_input, i.spec::text));
  foreach tok in array regexp_split_to_array(lower(coalesce(i.category,'')), '[^a-z0-9]+') loop
    if length(tok) >= 4 then blob := replace(blob, tok, ' '); end if;
  end loop;

  for f in select value from jsonb_array_elements(spec_fields)
            where coalesce((value->>'required')::boolean, false)
  loop
    k := lower(f->>'key'); reqn := reqn + 1; found := false;

    -- (a) exact key
    if public._rfq_answered(bag->>k) then found := true; end if;

    -- (b) concept synonym or shared significant token
    if not found then
      for bk in select key from jsonb_each_text(bag) loop
        if public._rfq_answered(bag->>bk) then
          if public._rfq_concept(k) is not null
             and public._rfq_concept(k) = public._rfq_concept(bk) then
            found := true;
          else
            foreach tok in array string_to_array(k,'_') loop
              if length(tok) >= 4 and (bk = tok or bk like '%'||tok||'%' or tok like '%'||bk||'%') then
                found := true;
              end if;
            end loop;
          end if;
        end if;
        exit when found;
      end loop;
    end if;

    -- (c) the free text names one of this field's enumerated options
    if not found and jsonb_typeof(f->'options') = 'array' then
      for opt in select lower(o) from jsonb_array_elements_text(f->'options') o loop
        foreach tok in array regexp_split_to_array(regexp_replace(opt,'[^a-z0-9 ]',' ','g'), '\s+') loop
          if length(tok) >= 4 and blob like '%'||tok||'%' then found := true; end if;
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
    'checked_at', now());
end $chk$;

-- Extend the score: generic scoring is UNCHANGED; the category requirement is added on top.
create or replace function public.fn_rfq_score(i public.inquiries)
returns jsonb language plpgsql stable
set search_path to 'public','pg_temp'
as $sc$
declare pts int:=0; miss text[]:='{}'; have text[]:='{}'; spectxt text;
        catchk jsonb; catmiss text[]:='{}'; m jsonb; gready boolean; catok boolean;
begin
  spectxt := coalesce(i.spec::text,'');
  if coalesce(i.category,'')<>'' then pts:=pts+20; have:=array_append(have,'category'); else miss:=array_append(miss,'category'); end if;
  if coalesce(i.emirate,'')<>'' then pts:=pts+10; have:=array_append(have,'emirate'); else miss:=array_append(miss,'emirate'); end if;
  if length(regexp_replace(spectxt,'[^a-zA-Z0-9]','','g')) > 20 then pts:=pts+25; have:=array_append(have,'scope_detail'); else miss:=array_append(miss,'scope_detail'); end if;
  if coalesce(i.scope_type,'')<>'' then pts:=pts+15; have:=array_append(have,'scope_type'); else miss:=array_append(miss,'scope_type'); end if;
  if i.budget is not null then pts:=pts+15; have:=array_append(have,'budget'); else miss:=array_append(miss,'budget'); end if;
  if coalesce(array_length(i.trades,1),0)>0 or coalesce(i.drawing_file_path,'')<>'' or i.boq is not null then
     pts:=pts+15; have:=array_append(have,'supporting_detail'); else miss:=array_append(miss,'supporting_detail'); end if;

  gready := pts >= 70;

  catchk := public.fn_rfq_required_check(i);
  catok  := coalesce((catchk->>'required_ok')::boolean, true);

  if coalesce((catchk->>'applicable')::boolean,false) then
    for m in select value from jsonb_array_elements(coalesce(catchk->'missing','[]'::jsonb)) loop
      catmiss := array_append(catmiss, coalesce(nullif(m->>'question',''), m->>'key'));
    end loop;
  end if;

  return jsonb_build_object(
    'score', pts,
    'generic_ready', gready,
    'category_required_ok', catok,
    'ready', (gready and catok),
    'have', to_jsonb(have),
    'missing', to_jsonb(miss || catmiss),
    'category_missing', coalesce(catchk->'missing','[]'::jsonb),
    'category_check', catchk,
    'scored_at', now());
end $sc$;

comment on function public.fn_rfq_required_check(public.inquiries) is
  'Per-category required-field gate. Resolves category_specs.fields[] where required=true against the inquiry brief/spec/columns by exact key, concept synonym, shared token, or enumerated option mentioned in free text. Returns required_ok + the missing list. Categories with no spec row are not gated.';

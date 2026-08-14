-- Stage 7 — connect the 86 category specialists to the inquiry that actually runs.
--
-- Two vocabularies again. category_specs holds 56 customer-facing trade slugs with
-- qualification fields (`aluminium`, `blinds-curtains`); kb_operational_route holds the
-- 86 supplier catalogue routes (`opcat-019`, `aluminium-and-glass-suppliers`). NOT ONE of
-- the 56 spec rows matches a route_key, so the "REFERENCE CHECKLIST for this category" the
-- estimator is given in inquiry_ai comes from a table that cannot see the route corpus, and
-- 30 of the 86 routes have no checklist at all.
--
-- The packaged delivery supplies a field-and-question bank and a minimum-sufficient policy
-- for all 86 routes. fn_category_checklist joins them: it resolves the caller's slug through
-- the route resolver that already passes 344/344 route tests, then returns the curated
-- fields and the packaged bank together, marked by origin so nothing is silently invented.

create or replace function fn_category_checklist(
  p_category text,
  p_label    text default null,
  p_text     text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_decide   jsonb;
  v_num      integer;
  v_cat_key  text;
  v_route    record;
  v_curated  jsonb;
  v_bank     jsonb;
  v_policy   jsonb;
  v_resolved text;
begin
  -- 1. curated fields for the customer-facing slug, if the company has any
  select fields into v_curated from category_specs where category = p_category limit 1;

  -- 2a. a system category slug the company assigned resolves deterministically; only
  --     customer prose goes to the language resolver.
  select catalog_num into v_num from category_route_map where category = p_category;
  if v_num is not null then v_resolved := 'category_route_map'; end if;

  -- 2b. resolve to a catalogue route using the existing resolver, not a new matcher
  if v_num is null then
  v_decide := fn_kb_route_decide(coalesce(nullif(btrim(concat_ws(' ', p_label, p_category, p_text)), ''), p_category));
  v_num := nullif(v_decide->>'catalog_num', '')::integer;
  v_resolved := 'route_decider';
  end if;
  if v_num is null then
    -- the decider asked for clarification; take its top candidate only when it is unambiguous
    if coalesce(jsonb_array_length(v_decide->'candidates'), 0) = 1 then
      v_num := (v_decide->'candidates'->0->>'catalog_num')::integer;
      v_resolved := 'single_candidate';
    end if;
  end if;
  if v_num is null then
    select catalog_num into v_num from kb_operational_route
     where expected_catalog_slug = p_category or route_key = p_category limit 1;
    if v_num is not null then v_resolved := 'exact_slug'; end if;
  end if;

  if v_num is null then
    return jsonb_build_object(
      'category', p_category, 'route_resolved', false,
      'resolution', 'unresolved',
      'clarification', v_decide->>'clarification',
      'candidates', coalesce(v_decide->'candidates', '[]'::jsonb),
      'curated_fields', coalesce(v_curated, '[]'::jsonb),
      'packaged_questions', '[]'::jsonb, 'mandatory_fields', '[]'::jsonb,
      'never_infer', '[]'::jsonb, 'knowledge_ids', '[]'::jsonb);
  end if;

  select * into v_route from kb_operational_route where catalog_num = v_num;
  select category_key into v_cat_key from org_category_identity where catalog_num = v_num;

  -- 3. the packaged question bank for that route (field / question / mandatory / why)
  select structured_data->'questions' into v_bank
    from ops_knowledge
   where category_key = v_cat_key and runtime_eligible and supersession_state = 'current'
     and source_path like '%02_FIELD_AND_QUESTION_BANK_V2.yaml'
   limit 1;

  -- 4. the V3 minimum-sufficient policy: what must be answered, and what may never be guessed
  select structured_data into v_policy
    from ops_knowledge
   where category_key = v_cat_key and runtime_eligible and supersession_state = 'current'
     and source_path like '%02_MINIMUM_SUFFICIENT_QUESTION_POLICY_V3.yaml'
   limit 1;

  return jsonb_build_object(
    'category', p_category,
    'route_resolved', true,
    'resolution', v_resolved,
    'catalog_num', v_num,
    'route_key', v_route.route_key,
    'route_name', v_route.catalog_name,
    'category_key', v_cat_key,
    'coverage_status', v_route.coverage_status,
    'regulatory_coverage_status', v_route.regulatory_coverage_status,
    'curated_fields', coalesce(v_curated, '[]'::jsonb),
    'packaged_questions', coalesce(v_bank, '[]'::jsonb),
    'mandatory_fields', coalesce(v_policy->'mandatory_fields', '[]'::jsonb),
    'route_specific_fields', coalesce(v_policy->'route_specific_fields', '[]'::jsonb),
    'ask_order', coalesce(v_policy->'ask_order', '[]'::jsonb),
    'stop_rule', v_policy->>'stop_rule',
    'never_infer', coalesce(v_policy->'never_infer', '[]'::jsonb),
    'knowledge_ids', coalesce((
      select jsonb_agg(record_id) from ops_knowledge
       where category_key = v_cat_key and runtime_eligible and supersession_state = 'current'), '[]'::jsonb));
end $$;

revoke all on function fn_category_checklist(text, text, text) from public;
grant execute on function fn_category_checklist(text, text, text) to service_role;

-- Quote-readiness: the brief may only go to suppliers when every mandatory field for the
-- resolved route is present. Returns the blocking fields rather than a bare boolean, so the
-- caller can ask for exactly what is missing instead of asking again for everything.
create or replace function fn_category_quote_ready(
  p_category text,
  p_spec     jsonb,
  p_label    text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_chk     jsonb;
  v_missing text[] := '{}';
  f         text;
begin
  v_chk := fn_category_checklist(p_category, p_label, null);
  if not (v_chk->>'route_resolved')::boolean then
    return jsonb_build_object('ready', false, 'reason', 'route_unresolved',
                              'clarification', v_chk->>'clarification',
                              'missing', '[]'::jsonb, 'checklist', v_chk);
  end if;
  for f in select jsonb_array_elements_text(v_chk->'mandatory_fields') loop
    if coalesce(p_spec, '{}'::jsonb) ->> f is null
       or btrim(coalesce(p_spec ->> f, '')) = '' then
      v_missing := v_missing || f;
    end if;
  end loop;
  return jsonb_build_object(
    'ready', coalesce(array_length(v_missing, 1), 0) = 0,
    'reason', case when coalesce(array_length(v_missing,1),0) = 0 then 'complete' else 'missing_mandatory_fields' end,
    'missing', to_jsonb(v_missing),
    'route_key', v_chk->>'route_key',
    'category_key', v_chk->>'category_key',
    'stop_rule', v_chk->>'stop_rule',
    'never_infer', v_chk->'never_infer',
    'knowledge_ids', v_chk->'knowledge_ids');
end $$;

revoke all on function fn_category_quote_ready(text, jsonb, text) from public;
grant execute on function fn_category_quote_ready(text, jsonb, text) to service_role;

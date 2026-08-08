-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724160651   name: comparison_agent_expert_knowledge_and_supplier_coaching
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- 1) Feed the comparison agent QuotesDone's own curated per-category depth: UAE market
--    price benchmarks + red flags, what a complete quote must itemise, and the spec
--    hierarchy. Maps the inquiry category to its cat:* expert agent.
create or replace function public.fn_category_expert_ref(p_category text)
returns text language plpgsql stable security definer set search_path to 'public','pg_temp'
as $fn$
declare v_slug text; v_txt text;
begin
  v_slug := case
    when p_category ~* 'cctv|security|surveillance' then 'cctv-security'
    when p_category ~* 'hvac|air.?con|ac-' then 'ac-maintenance'
    when p_category ~* 'duct' then 'ac-duct-cleaning'
    when p_category ~* 'glass|glaz|alumin' then 'aluminium-glass'
    when p_category = 'carpentry' then 'carpentry-joinery'
    when p_category ~* 'joinery|kitchen' then 'joinery-kitchens'
    when p_category ~* 'tiling|tile|marble|granite' then 'tiling-marble'
    when p_category ~* 'gypsum|false.?ceiling|ceiling' then 'false-ceiling'
    when p_category ~* 'upholstery|blind|curtain' then 'curtains-blinds'
    when p_category ~* 'fit.?out' then 'commercial-retail-fitout'
    when p_category ~* 'combined.?mep|^mep$' then 'combined-mep'
    when p_category ~* 'steel|fabrication' then 'structural-steel-fabrication'
    when p_category ~* 'pest' then 'pest-control'
    when p_category ~* 'tent|shade' then 'tents-and-shade-structures'
    when p_category ~* 'general|other|handyman|facilit' then coalesce(
        (select 'general-services-other' where exists (select 1 from agent_knowledge where agent_key='cat:general-services-other')), p_category)
    else p_category end;
  select string_agg('## '||topic||E'\n'||content, E'\n\n')
    into v_txt from agent_knowledge
    where agent_key = 'cat:'||v_slug
      and topic in ('Pricing benchmarks & red flags','Quote analysis & comparison',
                    'Standards, materials & specifications','Field expertise — UAE codes, standards & specs');
  return left(coalesce(v_txt,''), 4500);
end $fn$;
revoke execute on function public.fn_category_expert_ref(text) from public, anon, authenticated;

-- 2) Supplier coaching: turn the missing generic + category specs into a warm, plain ask
--    the supplier portal can show ("to help customers compare fairly, please add ...").
create or replace function public.fn_quote_coach_text(p_quote text)
returns jsonb language plpgsql stable security definer set search_path to 'public','pg_temp'
as $fn$
declare gen jsonb; cat jsonb; asks text[] := '{}'; m jsonb; lbl text;
        gen_labels jsonb := jsonb_build_object(
          'line_items','an itemised breakdown (not just a lump sum)',
          'unit_prices_on_all_items','a unit price on every line',
          'brand_model_per_item','the brand/model for each item',
          'specifications','the key specifications',
          'labour_or_installation','the labour / installation cost',
          'warranty','the warranty period','lead_time','the lead / delivery time',
          'payment_terms','the payment terms','exclusions','what is excluded',
          'validity','how long the quote is valid');
begin
  select quality into gen from quotes where id = p_quote::uuid;
  -- generic completeness gaps
  if gen ? 'missing' then
    for m in select * from jsonb_array_elements(gen->'missing') loop
      lbl := gen_labels->>(m #>> '{}'); if lbl is null then lbl := m #>> '{}'; end if;
      asks := asks || lbl;
    end loop;
  end if;
  -- category-specific domain gaps (mandatory only)
  cat := fn_quote_category_score(p_quote);
  if (cat->>'applicable')::boolean and cat ? 'missing' then
    for m in select * from jsonb_array_elements(cat->'missing') loop
      if (m->>'mandatory')::boolean then asks := asks || lower(m->>'label'); end if;
    end loop;
  end if;
  asks := (select array_agg(distinct a) from unnest(asks) a);
  if coalesce(array_length(asks,1),0) = 0 then
    return jsonb_build_object('complete', true, 'message',
      'Your quote looks complete — thank you. Customers will be able to compare it fairly.');
  end if;
  return jsonb_build_object('complete', false, 'missing_count', array_length(asks,1),
    'message', 'Almost there. To help customers compare your quote fairly and pick you, please add: '
      || array_to_string(asks, '; ') || '. This makes your quote stronger, not harder — complete quotes win more often.',
    'asks', to_jsonb(asks));
end $fn$;
revoke execute on function public.fn_quote_coach_text(text) from public, anon, authenticated;

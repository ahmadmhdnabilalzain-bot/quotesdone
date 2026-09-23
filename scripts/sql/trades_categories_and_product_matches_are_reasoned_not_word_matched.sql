-- TRADES, CATEGORIES AND PRODUCT MATCHES ARE REASONED, NOT WORD-MATCHED — decision points 23-27 of
-- supabase/functions/_shared/decision_points.json (batch B3). Seat: sales_engineer. 23 Sep 2026,
-- founder_instruction 886-903 (ledger 890: no word matching anywhere).
--
-- WHY. Five routines decided what a customer's or a supplier's WORDS mean by spotting words:
--   23 fn_norm_trades            taxonomy_trade.aliases matched as '\m'-anchored regexes over free text -> trade codes
--   24 fn_kb_route               kb_operational_alias substrings (like '% alias %') scored -> catalogue category
--   25 fn_match_capability       products / brands / project type compared with ilike '%x%' BOTH ways -> score
--   26 fn_supplier_product_match position(term in the enquiry) over >= 4-letter words -> matched_terms, match_pct
--   27 fn_quote_spec_group       a 45-branch category regex -> which spec group a quote is checked against
--
-- WHAT. None of them reads free text for meaning any more:
--   23 fn_norm_trades resolves EXACTLY: a value that is a live taxonomy code or an intake slug resolves through
--      public.fn_taxonomy_trades_for (the estate's exact resolver, founder 14 Sep 2026: "either exact match or
--      no match"); anything else returns NULL = NEEDS REASONING. Its SQL callers pass inquiries.category (a
--      slug, always exact); a TS caller holding free text reasons it with think() (decision point 35,
--      sales_engineer.brief_trades) instead of asking this routine to read words.
--   24 fn_kb_route is dropped. fn_kb_route_decide(p_text, p_catalog_num) takes the category the CALLER reasoned
--      (think(), supabase/functions/_shared/reasoned_matching.ts catalogueCategoryOf); without one it answers
--      action 'needs_reasoning' with the activated categories to reason over. A deactivated category can
--      still never be routed to.
--   25 fn_match_capability compares products, brands and project type by EXACT normalised equality (lower +
--      btrim) — the supplier's declared vocabulary against the request's, "exact or none" as the trade
--      gate already is — and the emirate the same way. No substring can make a hit.
--   26 fn_supplier_product_match(p_inquiry_id, p_lead_id, p_asked) takes the product ids the CALLER reasoned the
--      enquiry asks for (reasoned_matching.ts productsAsked); without them it answers 'needs_reasoning' with
--      the enquiry and the products to reason over, and scores nothing.
--   27 fn_quote_spec_group reads public.category_specs.quote_spec_group, a keyed column seeded below with
--      the value the old regex returned for each of the 56 categories (measured on production 23 Sep 2026,
--      the same 56-row map line_specs/model.ts carries). A new category has no group until its row says so.
--
-- MEASURED BEFORE THIS FILE (production, 23 Sep 2026, read-only):
--   * callers — fn_norm_trades: fn_customer_decision_support, fn_supplier_market (both pass a category
--     slug) and sales_engineer (free text: point 35); fn_kb_route: only fn_kb_route_decide; fn_kb_route_decide:
--     no SQL caller, TS inquiry_intake + public_site; fn_supplier_product_match: supplier_portal only, no UI
--     reader; fn_quote_spec_group: trg_quote_quality, fn_os_catalog_get/list/test_gate (all SECURITY DEFINER).
--   * 86 catalogue categories; 56 category_specs rows, every inquiry category among them; 3,071 capability
--     rows carry products_norm, 4 carry brands.
--   * ACLs: fn_quote_spec_group was executable by PUBLIC; the rest were service_role only. After: all service_role only.
--
-- Pending: scripts/sql/pending/trades_categories_and_product_matches_are_reasoned_not_word_matched.txt.
-- Proved in one aborted transaction: scripts/checks/decision_points_are_reasoned.test.mjs (batch B3 probe).

-- ── 23. fn_norm_trades: exact or NULL (needs reasoning) ─────────────────────────────────────────────────
create or replace function public.fn_norm_trades(p_text text)
returns text[]
language sql
stable
set search_path to 'public', 'pg_temp'
as $fn$
  -- A live taxonomy code or an intake slug resolves exactly; free text resolves to NULL, which every
  -- caller already treats as "no trade" and which a TS caller reasons (think()) instead.
  select case when cardinality(r.codes) > 0 then r.codes end
    from (select array(select c from unnest(public.fn_taxonomy_trades_for(array[btrim(coalesce(p_text, ''))])) c
                        where exists (select 1 from public.taxonomy_trade t where t.code = c and t.active)
                        order by c) as codes) r;
$fn$;
revoke execute on function public.fn_norm_trades(text) from public, anon, authenticated;
grant execute on function public.fn_norm_trades(text) to service_role;

-- ── 24. fn_kb_route is gone; fn_kb_route_decide routes only a reasoned category ─────────────────────────
drop function if exists public.fn_kb_route_decide(text);
drop function if exists public.fn_kb_route(text, integer);

create or replace function public.fn_kb_route_decide(p_text text, p_catalog_num integer default null)
returns jsonb
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_open jsonb; v_cat record; v_rules jsonb; v_blocked boolean;
begin
  -- The categories a route may land on: every catalogue category whose activation is not blocked.
  select coalesce(jsonb_agg(jsonb_build_object('catalog_num', c.num, 'live_slug', c.slug, 'live_name', c.name) order by c.num), '[]'::jsonb)
    into v_open
    from public.catalog_supplier_categories c
   where not coalesce((public.fn_kb_route_activation_blocked(c.num)->>'blocked')::boolean, true);

  if p_catalog_num is null then
    -- NEEDS REASONING. The customer's wording is read by the caller's think() over these categories;
    -- nothing here matches it against an alias.
    return jsonb_build_object(
      'action', 'needs_reasoning', 'catalog_num', null, 'candidates', v_open, 'rules', '[]'::jsonb,
      'reason', 'the customer''s wording is reasoned by the caller (think()) over the activated categories, never matched on words',
      'clarification', 'Could you tell me in your own words what you need supplied or done? For example "waterproof a warehouse roof" or "supply 200 office chairs".');
  end if;

  select c.num, c.slug, c.name into v_cat from public.catalog_supplier_categories c where c.num = p_catalog_num;
  v_blocked := coalesce((public.fn_kb_route_activation_blocked(p_catalog_num)->>'blocked')::boolean, true);
  if v_cat.num is null or v_blocked then
    return jsonb_build_object(
      'action', 'ask_clarifying_question', 'catalog_num', null, 'candidates', v_open, 'rules', '[]'::jsonb,
      'reason', case when v_cat.num is null then 'no such catalogue category' else 'that category is not activated for live use' end,
      'clarification', 'Could you tell me in your own words what you need supplied or done? For example "waterproof a warehouse roof" or "supply 200 office chairs".');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'rule_id', d.rule_id, 'type', d.rule_type, 'priority', d.priority,
           'when', d.when_json, 'then', d.then_json,
           'requires_human_review', d.requires_human_review,
           'confidence', d.confidence) order by d.priority desc nulls last, d.rule_id), '[]'::jsonb)
    into v_rules
    from (select * from kb_stage.decision_rules dr
           where dr.category_slug in (select m.package_slug from public.kb_operational_route_map m where m.catalog_num = p_catalog_num)
           order by dr.priority desc nulls last, dr.rule_id
           limit 5) d;

  return jsonb_build_object(
    'action', 'route_or_ask_scope_details', 'catalog_num', v_cat.num,
    'candidates', jsonb_build_array(jsonb_build_object('catalog_num', v_cat.num, 'live_slug', v_cat.slug, 'live_name', v_cat.name)),
    'reason', 'the category was reasoned by the caller', 'clarification', null, 'rules', coalesce(v_rules, '[]'::jsonb));
end $fn$;
revoke execute on function public.fn_kb_route_decide(text, integer) from public, anon, authenticated;
grant execute on function public.fn_kb_route_decide(text, integer) to service_role;

-- ── 25. fn_match_capability: products, brands, project type and emirate compared exactly ─────────────────
-- Canonical body: scripts/sql/a_supplier_receives_a_service_inquiry_only_for_what_he_ticked.sql (MANIFEST
-- 1282, read back from production 23 Sep 2026). Only the comparisons marked EXACT change.
create or replace function public.fn_match_capability(p_trades text[], p_need text DEFAULT 'executes'::text, p_products text[] DEFAULT '{}'::text[], p_brands text[] DEFAULT '{}'::text[], p_project_type text DEFAULT NULL::text, p_value numeric DEFAULT NULL::numeric, p_emirate text DEFAULT NULL::text, p_limit integer DEFAULT 12, p_services text[] DEFAULT '{}'::text[])
returns table(supplier_id bigint, company_name text, score numeric, trades text[], roles text[], product_hits integer, brand_hit boolean, ptype_hit boolean, track numeric, why text, service_hits text[], via_implication text[])
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
with w as (
  select coalesce((select value::text::numeric from decision_policy where key='score_w_product'),40)      as w_prod,
         coalesce((select value::text::numeric from decision_policy where key='score_w_brand'),20)        as w_brand,
         coalesce((select value::text::numeric from decision_policy where key='score_w_project_type'),15) as w_ptype,
         coalesce((select value::text::numeric from decision_policy where key='score_w_track_record'),15) as w_track,
         coalesce((select value::text::numeric from decision_policy where key='score_w_size_fit'),10)     as w_size
),
-- EXACT (23 Sep 2026, decision point 25): the request's terms and the supplier's, each lower-cased and
-- trimmed, then compared for equality. A substring is not a match: "door" is not "door closer".
q as (
  select array(select distinct lower(btrim(x)) from unnest(coalesce(p_products, '{}'::text[])) x where nullif(btrim(x), '') is not null) as products,
         array(select distinct lower(btrim(x)) from unnest(coalesce(p_brands, '{}'::text[])) x where nullif(btrim(x), '') is not null) as brands,
         nullif(lower(btrim(coalesce(p_project_type, ''))), '') as ptype,
         nullif(lower(btrim(coalesce(p_emirate, ''))), '') as emirate
),
req_auth as (
  select coalesce(array_agg(distinct a),'{}') as codes
  from public.taxonomy_trade t, unnest(t.authority_required) a
  where t.code = any(p_trades)
),
named as (
  select distinct s as key, split_part(s, '.', 1) as tr
  from unnest(coalesce(p_services, '{}'::text[])) s
  where position('.' in s) > 0
    and exists (select 1 from public.taxonomy_trade_service ts
                where ts.active and ts.trade_code || '.' || ts.code = s)
),
n as (select count(*)::int as k from named),
loc as (
  select sc.supplier_id,
         array(select distinct lower(btrim(e)) from unnest(coalesce(sc.coverage_emirates, '{}'::text[])
                                           || coalesce(l.service_emirates, '{}'::text[])) e
                where nullif(btrim(e), '') is not null) as stated
  from public.supplier_capabilities sc
  join public.leads l on l.id = sc.supplier_id
),
cand as (
  select sc.supplier_id, sc.trades, sc.roles, sc.products_norm, sc.brands, sc.project_types,
         sc.min_project_value, sc.max_project_value, sc.coverage_emirates,
         sc.services, sc.services_removed,
         l.company_name, l.emirate as lead_emirate,
         least(1, greatest(0, coalesce(sp.quote_rate, sp.perf_score, 0))) as track,
         ((select emirate from q) is not null and (select emirate from q) = any(loc.stated)) as in_emirate,
         cardinality(loc.stated) as stated_n
  from public.supplier_capabilities sc
  join public.leads l on l.id = sc.supplier_id
  join loc on loc.supplier_id = sc.supplier_id
  left join public.supplier_perf sp on sp.supplier_id = sc.supplier_id
  where sc.confirmed_at is not null
    and sc.trades && p_trades
    and not (sc.excluded_trades && p_trades)
    and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                               l.approval_status, l.permanently_closed, l.chat_strikes)
    and exists (
      select 1 from public.taxonomy_role r
      where r.code = any(sc.roles)
        and case p_need when 'supplies'    then r.supplies
                        when 'whole_scope' then r.whole_scope
                        else r.executes end
    )
    and not exists (
      select 1 from unnest((select codes from req_auth)) a
      where not (sc.authority_approvals ? a)
    )
    and (p_value is null or (
          (sc.min_project_value is null or p_value >= sc.min_project_value)
      and (sc.max_project_value is null or p_value <= sc.max_project_value)))
    and ((select emirate from q) is null
      or cardinality(loc.stated) = 0
      or (select emirate from q) = any(loc.stated))
),
eff as (
  select c.*,
         case when (select k from n) = 0 then '{}'::text[]
              else public.fn_services_effective(c.services, c.trades, c.services_removed) end as eff_services
  from cand c
),
svc as (
  select e.*,
    array(select unnest(e.eff_services) intersect select key from named) as service_hits,
    not exists (select 1 from named t where t.tr = any(coalesce(e.trades, '{}'::text[]))) as never_asked,
    -- ponytail: one scan of service_implication per candidate (113 curated rows); batch it with a single
    -- unnest+join if the map or the candidate count grows an order of magnitude.
    array(
      select distinct i.from_code || ' -> ' || i.implies_trade || '.' || i.implies_code
      from public.service_implication i
      where i.active
        and (i.implies_trade || '.' || i.implies_code) = any(e.eff_services)
        and (i.implies_trade || '.' || i.implies_code) in (select key from named)
        and not ((i.implies_trade || '.' || i.implies_code) = any(coalesce(e.services, '{}'::text[])))
        and (i.from_code = any(coalesce(e.trades, '{}'::text[]))
          or i.from_code = any(coalesce(e.services, '{}'::text[])))
      order by 1) as via_implication
  from eff e
),
scored as (
  select c.*,
    -- EXACT: a requested product counts when the supplier declares that same product.
    (select count(*) from unnest((select products from q)) pq
      where pq = any(array(select lower(btrim(pp)) from unnest(coalesce(c.products_norm, '{}'::text[])) pp)))::int as product_hits,
    (cardinality((select brands from q)) > 0 and exists (
       select 1 from unnest(coalesce(c.brands, '{}'::text[])) bb where lower(btrim(bb)) = any((select brands from q))
     )) as brand_hit,
    ((select ptype from q) is not null and exists (
       select 1 from unnest(coalesce(c.project_types, '{}'::text[])) pt where lower(btrim(pt)) = (select ptype from q)
     )) as ptype_hit,
    (p_value is not null and c.min_project_value is not null and c.max_project_value is not null) as size_known
  from svc c
  where (select k from n) = 0
     or cardinality(c.service_hits) > 0
     or c.never_asked
),
ranked as (
  select s.*,
    round(
        w.w_prod  * (case when cardinality((select products from q)) > 0
                          then s.product_hits::numeric / cardinality((select products from q)) else 0 end)
      + w.w_brand * (case when s.brand_hit then 1 else 0 end)
      + w.w_ptype * (case when s.ptype_hit then 1 else 0 end)
      + w.w_track * s.track
      + w.w_size  * (case when s.size_known then 1 else 0.5 end)
    , 1) as score_v
  from scored s, w
)
select r.supplier_id, r.company_name, r.score_v as score,
  r.trades, r.roles, r.product_hits, r.brand_hit, r.ptype_hit, round(r.track,3) as track,
  concat_ws(' · ',
    'trades ' || array_to_string(array(select unnest(r.trades) intersect select unnest(p_trades)), '+'),
    case when cardinality(r.service_hits) > 0 then cardinality(r.service_hits)||'/'||(select k from n)||' services' end,
    case when (select k from n) > 0 and r.never_asked and cardinality(r.service_hits) = 0
           then 'trade level (no service named in this supplier''s trades)' end,
    case when cardinality(r.via_implication) > 0 then 'implied: ' || array_to_string(r.via_implication, ', ') end,
    case when r.product_hits > 0 then r.product_hits||'/'||cardinality((select products from q))||' products' end,
    case when r.brand_hit then 'brand match' end,
    case when r.ptype_hit then 'project type' end,
    case when p_emirate is not null then
      case when r.in_emirate then 'in ' || p_emirate else 'UAE-wide (no stated limit)' end end
  ) as why,
  r.service_hits, r.via_implication
from ranked r
order by r.score_v desc, cardinality(r.service_hits) desc, r.in_emirate desc, r.track desc, r.supplier_id
limit greatest(1, p_limit);
$function$;
revoke execute on function public.fn_match_capability(text[], text, text[], text[], text, numeric, text, integer, text[]) from public, anon, authenticated;
grant execute on function public.fn_match_capability(text[], text, text[], text[], text, numeric, text, integer, text[]) to service_role;

-- ── 26. fn_supplier_product_match: the reasoned product ids, or needs_reasoning ─────────────────────────
drop function if exists public.fn_supplier_product_match(uuid, bigint);

create or replace function public.fn_supplier_product_match(p_inquiry_id uuid, p_lead_id bigint, p_asked bigint[] default null)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with inq as (
    select coalesce(category, '') cat,
           concat_ws(' ', nullif(summary, ''), nullif(raw_input, ''), nullif(category, '')) want
      from public.inquiries where id = p_inquiry_id
  ),
  prod as (
    select p.id, p.name, p.brand, p.model, p.category_slug, left(coalesce(p.description, ''), 300) description
      from public.supplier_product p
     where p.supplier_id = p_lead_id
     order by p.id
     limit 40
  )
  select jsonb_build_object(
    'inquiry_id', p_inquiry_id,
    'supplier_id', p_lead_id,
    'status', case when p_asked is null then 'needs_reasoning' else 'reasoned' end,
    'basis', 'reasoned: which of your products the enquiry asks for is read by reasoning over the enquiry and each product record (think()), never by shared words. The category match is the category key itself.',
    'population', jsonb_build_object(
      'products', (select count(*) from prod),
      'note', case when (select count(*) from prod) = 0
                   then 'you have no products yet — upload a catalog and these become matchable' end),
    -- What the caller reasons over, handed back only while no reasoning has been supplied.
    'to_reason', case when p_asked is null then jsonb_build_object(
        'want', (select left(want, 4000) from inq),
        'products', coalesce((select jsonb_agg(jsonb_build_object('product_id', pr.id, 'name', pr.name, 'brand', pr.brand, 'model', pr.model,
                                  'category_slug', pr.category_slug, 'description', pr.description) order by pr.id) from prod), '[]'::jsonb)) end,
    'matches', case when p_asked is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
          'product_id', pr.id, 'name', pr.name, 'brand', pr.brand, 'model', pr.model,
          'asked', pr.id = any(p_asked),
          'category_match', pr.category_slug is not null and pr.category_slug = (select cat from inq))
        order by (pr.id = any(p_asked)) desc, pr.name)
      from prod pr), '[]'::jsonb) end
  );
$fn$;
revoke execute on function public.fn_supplier_product_match(uuid, bigint, bigint[]) from public, anon, authenticated;
grant execute on function public.fn_supplier_product_match(uuid, bigint, bigint[]) to service_role;

-- ── 27. fn_quote_spec_group: a keyed column, not a category regex ───────────────────────────────────────
alter table public.category_specs add column if not exists quote_spec_group text;
comment on column public.category_specs.quote_spec_group is
  'The spec group (category_quote_specs.spec_group) a quote in this category is checked against. Keyed, set with the category; NULL = no group. Seeded 23 Sep 2026 from the value the retired category regex returned. Owner: sales_engineer.';

update public.category_specs cs
   set quote_spec_group = m.grp
  from (values
    ('acrylic','acrylic'), ('aluminium','glazing'), ('av-systems','avsystems'), ('blinds-curtains','upholstery'),
    ('carpentry','joinery'), ('carpentry-joinery','joinery'), ('carpets','carpet'), ('cleaning','cleaning'),
    ('combined-mep','mep'), ('commercial-retail-fitout','fitout'), ('custom-furniture','joinery'), ('demolition','demolition'),
    ('electrical','electrical'), ('elevators','elevators'), ('epoxy-flooring','flooring'), ('facade-cleaning','facade'),
    ('fitout','fitout'), ('flooring','flooring'), ('garage-doors','shutters'), ('general','general'),
    ('general-building-contracting','general'), ('general-services-other','general'), ('generators','generators'), ('glass','glazing'),
    ('gypsum','gypsum'), ('hvac','hvac'), ('insulation','insulation'), ('interior-design','interiordesign'),
    ('it-networking','networking'), ('kitchens','joinery'), ('landscaping','landscaping'), ('marble-granite','tiling'),
    ('masonry','masonry'), ('mep','mep'), ('movers','movers'), ('painting','painting'),
    ('pest','pestcontrol'), ('plumbing','plumbing'), ('roofing','roofing'), ('safety','fire'),
    ('scaffolding','scaffolding'), ('security','security'), ('signage','signage'), ('smart-home','smarthome'),
    ('solar','solar'), ('steel','steel'), ('structural-steel-fabrication','steel'), ('swimming-pools','pools'),
    ('tents-and-shade-structures','shade'), ('tiling','tiling'), ('upholstery','upholstery'), ('wallpaper','wallpaper'),
    ('water-tank-cleaning','watertank'), ('waterproofing','waterproofing')
  ) as m(category, grp)
 where cs.category = m.category and cs.quote_spec_group is distinct from m.grp;

create or replace function public.fn_quote_spec_group(p_category text)
returns text
language sql
stable
set search_path to 'public', 'pg_temp'
as $fn$
  select cs.quote_spec_group from public.category_specs cs where cs.category = p_category;
$fn$;
revoke execute on function public.fn_quote_spec_group(text) from public, anon, authenticated;
grant execute on function public.fn_quote_spec_group(text) to service_role;

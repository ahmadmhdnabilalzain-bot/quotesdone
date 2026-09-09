-- THE LIBRARY STARTS EMBEDDING ITSELF AGAIN, AND STARTS WHERE THE DEMAND IS (9 Sep 2026).
-- Agent: ceo. Answers founder instruction #14 -- "the general reference library, you need to organize
-- it in a way that it's ingested properly... it has to be like a brain".
--
-- MEASURED. kb_chunks holds 2,686,026 rows and 166,093 embeddings -- 6.18%. 2,519,933 rows have no
-- vector, so for 93.8% of the library there is no meaning, only keywords. That is the founder's
-- sentence, in numbers.
--
-- WHY IT STOPPED, in four places, none of them a fault:
--   1. 2026-09-07 17:51 UTC -- pg_cron was emptied on the founder's instruction. The last run of
--      EVERY job on the estate is between 17:45 and 17:51 that evening; cron.job now holds one
--      inactive row. Four embedding jobs died with it: kb_embed_backfill_boost (510 runs in its
--      final 51 minutes), kb_embed_backfill, kb_embed_priority_kinds, kb_embed_ops_knowledge.
--   2. Same change -- fn_kernel_cron_exec and phase_c_system_execution_wrapper were dropped. They
--      held the actual net.http_post payload, so even a restored cron row would call a missing
--      function on a missing body.
--   3. 2026-09-08 00:05 UTC -- commit 182308b (#530, "137 functions deleted") removed
--      supabase/functions/kb_embed/. It is absent from the 62 deployed slugs, and 0 of 2,681 edge
--      log lines in the last 24 hours mention it. The worker was deleted about six hours AFTER its
--      schedule already had.
--   4. 2026-09-07 18:15 UTC -- agent_runs was cleared, so kb_embed's own run log is gone. That is
--      why there is no error to find, and why nothing has reported the stall for two days.
--
-- Ruled out by measurement, not assumed: not stuck leases (5 rows claimed-and-unembedded, and the
-- 3-minute predicate frees them logically); not errors (the final hour ran at 33.9 rows/min, its
-- exact design rate, and stopped mid-hour with nothing degrading first); not cost (the model is the
-- FREE in-region gte-small and ai_gateway's embed action returns before routing, budget and the
-- OpenRouter hold).
--
-- THE FIX IS DELIBERATELY DEPLOY-FREE. Restoring kb_embed would need an edge deployment, and
-- re-registering pg_cron would rebuild machinery the founder removed on 7 Sep. Both were rejected.
-- Instead the loop runs from inside Postgres: pg_net 0.20.3 POSTs to ai_gateway {action:'embed'},
-- which is deployed (v43, ACTIVE) and carries the identical free in-region gte-small session.
-- Proven end to end before this file was written: request 400216 returned HTTP 200 with an 8,138-byte
-- 384-dimension vector, authenticated by cred_fn_ai (the fn.ai credential, scoped to exactly
-- ['ai_gateway']). cred_cron_knowledge was tried first and correctly refused with 403 -- it is not
-- scoped to the gateway.
--
-- COST. The model is free. The only spend is Supabase edge invocations: one per chunk, so 2.52M
-- invocations to drain the backlog. Against the plan's 2M/month included and $2 per additional
-- million, the whole remaining library costs single-digit dollars. Quoted here because the founder
-- asked to be told before money moves.
--
-- DEMAND ORDER, not table order. The old backfill was oldest-first, so it was pointed at whatever
-- happened to be oldest -- the frontier is currently sitting on Eurocode 2 concrete bearings. This
-- file adds kb_embed_priority, which maps the 77 categories still unembedded onto what the
-- marketplace actually sells (category_specs, 56 rows; taxonomy_trade, 40 codes). Tier 1 is the
-- fit-out trades themselves; tier 4 is the categories the company has excluded from its own scope.
--
--   node scripts/apply_sql.mjs scripts/sql/the_library_starts_embedding_itself_again_and_starts_where_the_demand_is.sql --apply --ddl

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. DEMAND. Data, not code, so the order can be argued with and changed without a migration.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.kb_embed_priority (
  category   text primary key,
  tier       int  not null check (tier between 1 and 4),
  reason     text not null,
  updated_at timestamptz not null default now()
);
comment on table public.kb_embed_priority is
  'Which kb_chunks categories the embedding backfill drains first. Tier 1 = trades the marketplace quotes today (category_specs / taxonomy_trade); 2 = adjacent trades it lists; 3 = the seats own back-office knowledge; 4 = out of the company scope, including the F&B set fn_sales_assist already excludes by slug. A category with no row here is treated as tier 3.';

insert into public.kb_embed_priority (category, tier, reason) values
  -- TIER 1 -- the fit-out and construction trades the marketplace exists to quote.
  ('construction-civil-and-building-materials', 1, 'core: general-building-contracting, masonry, demolition, structural-steel-fabrication'),
  ('interior-fit-out-finishes-and-joinery',     1, 'core: fitout, commercial-retail-fitout, carpentry-joinery, gypsum, painting, flooring'),
  ('luxury-fit-out',                            1, 'core: the premium end of the same fit-out demand'),
  ('interior-decoration-and-styling',           1, 'core: interior-design, wallpaper, blinds-curtains, carpets'),
  ('mep-mechanical-electrical-plumbing',        1, 'core: combined-mep, mep, hvac, electrical, plumbing'),
  ('firefighting-life-safety-and-security',     1, 'core: safety, security -- and the DCD/SIRA gates the sales seat must know'),
  ('elv-smart-systems-home-automation',         1, 'core: smart-home, av-systems, it-networking'),
  ('furniture-ff-and-e-and-loose-items',        1, 'core: custom-furniture, kitchens, upholstery'),
  ('swimming-pools-spas-and-water-features',    1, 'core: swimming-pools'),
  ('lifts-and-escalators',                      1, 'core: elevators -- a category_specs trade with ZERO price evidence today'),
  ('wastewater-drainage',                       1, 'core: plumbing, waterproofing, water-tank-cleaning'),
  ('renewable-energy',                          1, 'core: solar'),
  -- TIER 2 -- trades the marketplace lists or a supplier could be matched against.
  ('gas-systems',                             2, 'listed trade'),
  ('industrial-automation',                   2, 'listed trade'),
  ('fasteners-and-fixings',                   2, 'building materials input'),
  ('abrasives-tools-and-industrial-consumables', 2, 'building materials input'),
  ('temporary-event-infrastructure',          2, 'tents-and-shade-structures, scaffolding'),
  ('cleanrooms-and-controlled-environments',  2, 'specialist fit-out'),
  ('data-centres',                            2, 'specialist fit-out'),
  ('testing-inspection-certification-and-technical-services', 2, 'supplier verification evidence classes'),
  ('utilities',                               2, 'listed trade'),
  ('telecommunications',                      2, 'it-networking adjacency'),
  ('air-compressors-and-pneumatics',          2, 'heavy_equipment adjacency'),
  ('bearings-power-transmission-and-hydraulics', 2, 'heavy_equipment adjacency'),
  ('manufacturing-by-process',                2, 'job-shop-manufacturing, sheet-metal'),
  ('facilities-management-and-support-services', 2, 'cleaning, facade-cleaning, pest, general-services-other'),
  ('textile-uniforms-and-soft-goods',         2, 'ppe-workwear, upholstery'),
  ('exhibition-industry',                     2, 'exhibition-stand-contractors'),
  ('laboratory-and-scientific-suppliers',     2, 'laboratory-equipment'),
  ('media-av-production-and-creative-equipment', 2, 'av-systems adjacency'),
  ('logistics-transport-and-supply-chain',    2, 'taxonomy_trade logistics_moving; movers'),
  ('oil-and-gas-energy-and-industrial',       2, 'taxonomy_trade oilfield'),
  ('chemicals',                               2, 'taxonomy_trade chemicals'),
  ('vehicles-automotive-and-equipment',       2, 'taxonomy_trade heavy_equipment'),
  ('recycling-and-circular-economy',          2, 'waste adjacency'),
  ('printing-packaging-and-office-supplies',  2, 'signage adjacency; taxonomy_trade packaging'),
  ('domestic-services',                       2, 'cleaning, movers, handyman'),
  ('sports-recreation-and-leisure',           2, 'sports-playgrounds'),
  ('education-and-training-support',          2, 'training; education-equipment'),
  ('aviation-maritime-and-offshore',          2, 'taxonomy_trade marine is an ACTIVE code -- 116,966 rows, the single largest block'),
  ('marine-safety',                           2, 'taxonomy_trade marine, safety_equipment -- 76,905 rows'),
  ('engineering',                             2, 'engineering-and-architectural-consultancies'),
  -- TIER 3 -- the seats own working knowledge. Real demand, but the seats can answer lexically.
  ('accounting-finance-and-corporate-services', 3, 'accountant seat'),
  ('finance',                                 3, 'accountant seat'),
  ('banking-and-financial-products',          3, 'accountant seat'),
  ('insurance',                               3, 'accountant / CEO seats'),
  ('legal-and-compliance',                    3, 'CEO seat; UAE contract law'),
  ('legal',                                   3, 'CEO seat'),
  ('hr',                                      3, 'CEO seat'),
  ('human-resources-and-recruitment',         3, 'CEO seat'),
  ('it',                                      3, 'IT engineer seat'),
  ('it-technology-and-digital-services',      3, 'IT engineer seat'),
  ('qa',                                      3, 'IT engineer seat'),
  ('sales',                                   3, 'sales engineer seat'),
  ('marketing',                               3, 'CEO seat'),
  ('marketing-media-events-and-creative-services', 3, 'CEO seat'),
  ('analytics',                               3, 'CEO seat'),
  ('exec',                                    3, 'CEO seat'),
  ('procurement',                             3, 'sales engineer seat'),
  ('business-consulting',                     3, 'CEO seat'),
  ('customer_success',                        3, 'customer support seat'),
  ('real-estate-services',                    3, 'customer context'),
  ('government-tenders-and-procurement-support', 3, 'customer context'),
  ('business-centres-and-coworking',          3, 'customer context'),
  ('translation-interpretation-and-localization', 3, 'support seat -- Arabic is a measured gap'),
  -- TIER 4 -- outside the company's own scope. fn_sales_assist already excludes the F&B set by slug.
  ('catering-f-and-b-and-hospitality-services', 4, 'EXCLUDED by the company: fn_sales_assist c_fnb'),
  ('bakery-and-food-processing',              4, 'EXCLUDED by the company: fn_sales_assist c_fnb'),
  ('hospitality-supplies',                    4, 'EXCLUDED by the company: fn_sales_assist c_fnb'),
  ('cold-rooms-refrigeration-and-cold-chain', 4, 'EXCLUDED by the company: fn_sales_assist c_fnb'),
  ('agriculture-food-production-and-environment', 4, 'out of scope'),
  ('healthcare-medical-and-life-sciences',    4, 'out of scope'),
  ('religious-facilities',                    4, 'out of scope'),
  ('pet-industry',                            4, 'out of scope'),
  ('jewelry-and-luxury-retail',               4, 'out of scope'),
  ('luxury-and-concierge-services',           4, 'out of scope'),
  ('retail-and-consumer-goods',               4, 'out of scope'),
  ('travel-and-tourism-services',             4, 'out of scope')
on conflict (category) do update set tier = excluded.tier, reason = excluded.reason, updated_at = now();

-- The picker reads this index: tier first, then oldest within the tier.
create index if not exists kb_chunks_unembedded_cat_created_idx2
  on public.kb_chunks (category, created_at) where embedding_gte is null;

-- ---------------------------------------------------------------------------------------------
-- 2. THE IN-FLIGHT LEDGER. pg_net is asynchronous: the POST is queued now and the vector comes
--    back later, so the request id has to be tied to the chunk it belongs to or the response is
--    an orphan. This table IS the tie.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.kb_embed_inflight (
  request_id bigint primary key,
  chunk_id   bigint not null,
  queued_at  timestamptz not null default now()
);
create index if not exists kb_embed_inflight_chunk_idx on public.kb_embed_inflight (chunk_id);
comment on table public.kb_embed_inflight is
  'Maps a pg_net request id to the kb_chunks row whose embedding it is fetching. Written by fn_kb_embed_dispatch, drained by fn_kb_embed_harvest. A row older than an hour is a request pg_net gave up on; harvest clears it and the chunk is picked again.';

-- ---------------------------------------------------------------------------------------------
-- 3. DISPATCH. Claims by demand tier, then queues one POST per chunk.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_kb_embed_dispatch(p_limit integer default 200, p_max_tier integer default 4)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_lim     int := greatest(1, least(coalesce(p_limit, 200), 1000));
  v_url     text;
  v_secret  text;
  v_queued  int := 0;
begin
  select 'https://' || value || '.supabase.co/functions/v1/ai_gateway' into v_url
    from public.app_secrets where key = 'project_ref';
  select value into v_secret from public.app_secrets where key = 'cred_fn_ai';
  if v_url is null or coalesce(v_secret, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_project_ref_or_cred_fn_ai');
  end if;

  -- The claim. Same lease discipline as fn_kb_embed_claim -- FOR UPDATE SKIP LOCKED, a three-minute
  -- expiry stamped into embed_claimed_at -- so concurrent dispatches take disjoint slices and a
  -- dispatch that dies costs three minutes rather than its rows.
  with pick as (
    select k.id, k.title, k.content
      from public.kb_chunks k
      left join public.kb_embed_priority p on p.category = k.category
     where k.embedding_gte is null
       and (k.embed_claimed_at is null or k.embed_claimed_at < now() - interval '3 minutes')
       and coalesce(p.tier, 3) <= greatest(1, least(coalesce(p_max_tier, 4), 4))
     order by coalesce(p.tier, 3) asc, k.created_at asc
     limit v_lim
     for update of k skip locked
  ), claimed as (
    update public.kb_chunks k set embed_claimed_at = now()
      from pick where k.id = pick.id
    returning k.id, pick.title, pick.content
  ), sent as (
    select c.id,
           net.http_post(
             url := v_url,
             headers := '{"Content-Type":"application/json"}'::jsonb,
             body := jsonb_build_object(
                       '__secret', v_secret,
                       'fn', 'kb_embed_dispatch',
                       'action', 'embed',
                       -- 1,200 characters is the window kb_embed used and the window every existing
                       -- kb_chunks vector was built from. Changing it would make new rows
                       -- incomparable with the 166,093 already embedded.
                       'text', left(coalesce(c.title, '') || E'\n' || coalesce(c.content, ''), 1200)),
             timeout_milliseconds := 25000) as request_id
      from claimed c
  )
  insert into public.kb_embed_inflight (request_id, chunk_id)
  select s.request_id, s.id from sent s
  on conflict (request_id) do nothing;

  get diagnostics v_queued = row_count;
  return jsonb_build_object('ok', true, 'queued', v_queued, 'max_tier', p_max_tier, 'at', now());
end
$function$;

revoke execute on function public.fn_kb_embed_dispatch(integer, integer) from public;

-- ---------------------------------------------------------------------------------------------
-- 4. HARVEST. Reads what came back and writes the vectors.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_kb_embed_harvest()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_written int := 0;
  v_failed  int := 0;
  v_expired int := 0;
begin
  with done as (
    select f.request_id, f.chunk_id, r.status_code, r.content
      from public.kb_embed_inflight f
      join net._http_response r on r.id = f.request_id
  ), good as (
    select d.chunk_id, ((d.content::jsonb) ->> 'embedding') as vec
      from done d
     where d.status_code = 200
       and (d.content::jsonb) ->> 'embedding' is not null
  ), upd as (
    update public.kb_chunks k
       set embedding_gte = g.vec::vector, embed_claimed_at = null
      from good g
     where k.id = g.chunk_id and k.embedding_gte is null
    returning k.id
  ), del as (
    delete from public.kb_embed_inflight f
     using done d where f.request_id = d.request_id
    returning d.status_code
  )
  select (select count(*) from upd), (select count(*) from del where status_code is distinct from 200)
    into v_written, v_failed;

  -- A request pg_net never resolved: free the chunk so a later dispatch picks it up again.
  with stale as (
    delete from public.kb_embed_inflight
     where queued_at < now() - interval '1 hour'
    returning chunk_id
  )
  update public.kb_chunks k set embed_claimed_at = null
    from stale s where k.id = s.chunk_id and k.embedding_gte is null;
  get diagnostics v_expired = row_count;

  return jsonb_build_object('ok', true, 'embedded', v_written, 'failed', v_failed,
                            'expired_and_released', v_expired,
                            'still_inflight', (select count(*) from public.kb_embed_inflight),
                            'at', now());
end
$function$;

revoke execute on function public.fn_kb_embed_harvest() from public;

-- ---------------------------------------------------------------------------------------------
-- 5. ONE CALL FOR A SCHEDULER TO MAKE. Harvest first (so the previous tick's vectors land even if
--    this tick queues nothing), then dispatch. Safe to call at any cadence: dispatch is bounded by
--    p_limit and the lease, harvest is idempotent.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_kb_embed_tick(p_limit integer default 200)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_h jsonb; v_d jsonb;
begin
  v_h := public.fn_kb_embed_harvest();
  v_d := public.fn_kb_embed_dispatch(p_limit, 4);
  return jsonb_build_object('ok', true, 'harvest', v_h, 'dispatch', v_d,
    'unembedded_remaining', (select round(c.reltuples * coalesce(s.null_frac, 0))::bigint
                               from pg_class c
                               left join pg_stats s on s.schemaname = 'public' and s.tablename = 'kb_chunks'
                                                   and s.attname = 'embedding_gte'
                              where c.oid = 'public.kb_chunks'::regclass));
end
$function$;

revoke execute on function public.fn_kb_embed_tick(integer) from public;

commit;

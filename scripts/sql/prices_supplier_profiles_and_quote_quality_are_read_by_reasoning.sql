-- PRICES, SUPPLIER PROFILES AND QUOTE QUALITY ARE READ BY REASONING, NOT BY WORD MATCHING — batch B5.
-- Seat: sales_engineer (every point in this file is the sales engineer's). 23 Sep 2026,
-- founder_instruction 886-903 (ledger 890: "NO word matching anywhere").
--
-- WHAT WAS WRONG, read from production 23 Sep 2026 (pg_get_functiondef), one line per decision point
-- (supabase/functions/_shared/decision_points.json, orders 40-46):
--   40 fn_price_guidance      decided "is this a price question" with v_q ~ '(cost|price|...)' and WHICH
--                             TRADE with `v_q like '%' || term || '%'` over price_trade_term and a score of
--                             latin words against price_benchmark.item. A question naming "supplier" was
--                             once answered with flooring prices (the routine's own header says so).
--   41 fn_supplier_opportunities  capacity_hit := position(category in capability_summary) > 0.
--   42 fn_supplier_twin       Manufacturing / Installation / Maintenance / Design := capability_summary
--                             ilike '%manufactur%' / '%install%' / '%service%' / '%design%' — "we do not
--                             install" was Installation, "customer service" was Maintenance.
--   43 fn_supplier_portfolio_gaps  a supplier's own service words were matched to taxonomy services by a
--                             regex built from each service's aliases.
--   44 fn_rfq_short_of_quotes_tick  the need was scope_type ilike '%turnkey%' / ~* 'supply|material|product'.
--   45 trg_quote_quality      each category aspect was "addressed" when the quote blob ~* its match_regex
--                             (141 rows of category_quote_specs): "size" anywhere passed Dimensions.
--   46 fn_category_key_from_text  step 4 picked a category when a catalogue name was a substring of the
--                             task text, the longest name winning.
--
-- WHAT THIS CHANGES. No routine here reads free text for meaning any more. The meaning arrives either as
-- KEYED data somebody chose, or as a REASONED reading written by _shared/reasoned_suppliers.ts (think()):
--   40  fn_price_guidance(p_trade, p_limit, p_asked_item): the trade is chosen by reasoning in site_assistant
--       and public_site (priceQuestion). Called with no trade it returns the trade list to reason over.
--       The old (text, integer) signature is DROPPED. fn_org_task_consume_tick still calls it with a
--       task's question as the first argument; that is now an equality test on a trade slug, which a
--       sentence never passes, so the tick falls through to its other paths instead of guessing.
--   41  capacity is the supplier's CONFIRMED trades (supplier_capabilities.trades, ticked by the supplier)
--       against the enquiry's trade codes (fn_taxonomy_trades_for, a keyed map).
--   42  public.supplier_capability_reading: the four capabilities as reasoned from the CURRENT
--       capability_summary (keyed by its md5, so an edited summary is read again). Machinery lines and
--       engineers on file stay as keyed evidence. Until read, a capability is shown only from keyed data
--       and capability_reading says 'needs_reasoning'.
--   43  public.supplier_own_word_reading: which listed service (if any) each own word names, reasoned
--       once per word. An unread word is listed as "not on our list", which is true of it as written.
--   44  the need is keyed: scope_type = 'turnkey' (customer_api's own set) or role_needed when it is one of
--       fn_match_capability's needs.
--   45  public.quote_aspect_reading: which category aspects the quote states, reasoned over the quote's
--       text (md5-keyed). Until read, quality.category.status = 'needs_reasoning' and the verdict is NOT
--       a pass: the quote is held, never passed on a word guess. When the reading lands the quote's
--       quality is recomputed (the record routine re-fires the trigger).
--   46  step 4 is deleted: a task that names no inquiry, run or category key gets no category pack.
-- Replay effects (fn_reason_held_resolve -> fn_reason_apply_<surface>): sql.fn_supplier_twin,
-- sql.fn_supplier_portfolio_gaps and sql.trg_quote_quality each record their reading when the hold lifts.
--
-- MEASURED 23 Sep 2026: 975 active taxonomy services in 195 trades; 56 trades and 1,086 rows in
-- price_benchmark; 141 category_quote_specs rows; 3 quotes; 3 inquiries, all scope_type 'single' and
-- role_needed 'executes'; 20,448 of 22,272 leads carry a capability_summary; 4 supplier_capabilities rows
-- are confirmed.
--
-- Pending: scripts/sql/pending/prices_supplier_profiles_and_quote_quality_are_read_by_reasoning.txt.
-- Applies AFTER a_reasoned_answer_is_applied_by_its_own_surface.sql. Proved in one aborted transaction by
-- scripts/checks/decision_points_are_reasoned.test.mjs.

-- ── 1. the reasoned readings ─────────────────────────────────────────────────────────────────────
create table if not exists public.supplier_capability_reading (
  lead_id        bigint primary key references public.leads(id) on delete cascade,
  summary_md5    text not null check (summary_md5 ~ '^[0-9a-f]{32}$'),
  manufacturing  boolean,
  installation   boolean,
  maintenance    boolean,
  design         boolean,
  status         text not null check (status in ('reasoned', 'needs_reasoning')),
  held_id        bigint,
  reasoned_at    timestamptz,
  updated_at     timestamptz not null default now(),
  check (status = 'needs_reasoning' or (manufacturing is not null and installation is not null and maintenance is not null and design is not null))
);
alter table public.supplier_capability_reading enable row level security;
drop policy if exists supplier_capability_reading_service_role_only on public.supplier_capability_reading;
create policy supplier_capability_reading_service_role_only on public.supplier_capability_reading
  as permissive for all to public using (false) with check (false);
revoke all on public.supplier_capability_reading from anon, authenticated;
comment on table public.supplier_capability_reading is
  'What a supplier''s capability_summary says it does (manufacturing, installation, maintenance, design), reasoned by think() (_shared/reasoned_suppliers.ts), keyed by the md5 of the summary it read. Replaces capability_summary ilike (founder_instruction 886-903).';

create table if not exists public.supplier_own_word_reading (
  supplier_id  bigint not null references public.leads(id) on delete cascade,
  word         text not null check (btrim(word) <> '' and length(word) <= 200),
  service_key  text,
  status       text not null check (status in ('reasoned', 'needs_reasoning')),
  held_id      bigint,
  reasoned_at  timestamptz,
  updated_at   timestamptz not null default now(),
  primary key (supplier_id, word),
  check (status = 'reasoned' or service_key is null)
);
alter table public.supplier_own_word_reading enable row level security;
drop policy if exists supplier_own_word_reading_service_role_only on public.supplier_own_word_reading;
create policy supplier_own_word_reading_service_role_only on public.supplier_own_word_reading
  as permissive for all to public using (false) with check (false);
revoke all on public.supplier_own_word_reading from anon, authenticated;
comment on table public.supplier_own_word_reading is
  'Which listed service (trade_code.code) a supplier''s own service word names, or none, reasoned by think(). Replaces the alias regex in fn_supplier_portfolio_gaps (founder_instruction 886-903).';

create table if not exists public.quote_aspect_reading (
  quote_id     uuid primary key references public.quotes(id) on delete cascade,
  content_md5  text not null check (content_md5 ~ '^[0-9a-f]{32}$'),
  present      text[],
  status       text not null check (status in ('reasoned', 'needs_reasoning')),
  held_id      bigint,
  reasoned_at  timestamptz,
  updated_at   timestamptz not null default now(),
  check (status = 'needs_reasoning' or present is not null)
);
alter table public.quote_aspect_reading enable row level security;
drop policy if exists quote_aspect_reading_service_role_only on public.quote_aspect_reading;
create policy quote_aspect_reading_service_role_only on public.quote_aspect_reading
  as permissive for all to public using (false) with check (false);
revoke all on public.quote_aspect_reading from anon, authenticated;
comment on table public.quote_aspect_reading is
  'Which category_quote_specs aspects a quote states, reasoned by think() over the quote text whose md5 it carries. trg_quote_quality reads it; replaces match_regex (founder_instruction 886-903).';

-- ── 2. fn_price_guidance: the trade arrives reasoned ─────────────────────────────────────────────
drop function if exists public.fn_price_guidance(text, integer);
create or replace function public.fn_price_guidance(p_trade text, p_limit integer default 6, p_asked_item text default null)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_gap text; v_items jsonb; v_lim int := greatest(1, coalesce(p_limit, 6));
begin
  -- No trade: the caller has not reasoned yet. Hand it the trades we publish for, never a guess.
  if p_trade is null then
    return jsonb_build_object('ok', false, 'reason', 'needs_reasoning',
      'trades', (select coalesce(jsonb_agg(distinct pb.category order by pb.category), '[]'::jsonb) from public.price_benchmark pb),
      'note', 'Decide by reasoning whether the question asks what something costs and which of these trades it is about.');
  end if;
  if not exists (select 1 from public.price_benchmark pb where pb.category = p_trade) then
    return jsonb_build_object('ok', false, 'reason', 'no_trade_matched', 'trade', p_trade,
      'note', 'QuotesDone publishes no range for this trade. Say so plainly and offer to collect quotes; never substitute a nearby trade.');
  end if;
  select pb.gap_reason into v_gap from public.price_benchmark pb where pb.category = p_trade and pb.source_kind = 'gap' limit 1;
  if v_gap is not null then
    return jsonb_build_object('ok', false, 'reason', 'trade_has_a_recorded_gap', 'trade', p_trade, 'gap_reason', v_gap,
      'note', 'Tell the visitor plainly that we publish no range for this trade rather than estimating one, and offer to put it out to suppliers.');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', i.item, 'unit', i.unit, 'basis', i.basis_kind, 'low', i.low, 'high', i.high,
           'currency', coalesce(i.currency, 'AED'), 'evidence', left(i.evidence, 180),
           'source', i.source_kind || coalesce(':' || i.source_ref, ''), 'as_of', i.as_of) order by i.low), '[]'::jsonb)
    into v_items
    from (
      select distinct on (pb.item, pb.unit) pb.item, pb.unit, pb.basis_kind, pb.low, pb.high, pb.currency, pb.evidence,
             pb.source_kind, pb.source_ref, pb.as_of
        from public.price_benchmark pb
       where pb.category = p_trade and pb.source_kind <> 'gap' and pb.item is not null
       -- the same tiebreak as before: the same question always gets the same band, auditable to one row
       order by pb.item, pb.unit, (case when pb.source_kind = 'blog_post' then 0 else 1 end), pb.as_of desc nulls last, pb.id
    ) i;
  return jsonb_build_object(
    'ok', true, 'trade', p_trade, 'resolved_via', 'reasoning',
    'asked_item', nullif(btrim(coalesce(p_asked_item, '')), ''),
    'band_count', jsonb_array_length(v_items),
    'bands', case when jsonb_array_length(v_items) > v_lim
                  then (select jsonb_agg(s.e) from (select e from jsonb_array_elements(v_items) e limit v_lim) s)
                  else v_items end,
    'how_to_use', 'These are PUBLISHED GUIDE RANGES in AED for the UAE market, for the trade as a whole, with their source '
               || 'and date. They are orientation, never a quotation. QuotesDone does not price the work - suppliers do. '
               || 'Give the range, name it as a guide, and offer to collect real quotes. Never present a single figure as '
               || 'the price, never average a band into one number, and never state a figure that is not in bands above. '
               || 'If asked_item is set and no band is for that item, say plainly that the platform publishes no range for '
               || 'it rather than letting the trade bands stand in for it.');
end $fn$;
revoke execute on function public.fn_price_guidance(text, integer, text) from public, anon, authenticated;
grant execute on function public.fn_price_guidance(text, integer, text) to service_role;

-- ── 3. fn_supplier_opportunities: capacity is the trades the supplier confirmed ──────────────────
create or replace function public.fn_supplier_opportunities(p_lead_id bigint)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with me as (
    select l.id, lower(coalesce(l.sector, '')) sector, l.emirate,
           coalesce(l.service_emirates, '{}'::text[]) service_emirates,
           (select sc.trades from public.supplier_capabilities sc
             where sc.supplier_id = l.id and sc.confirmed_at is not null) confirmed_trades,
           l.verified
      from public.leads l where l.id = p_lead_id
  ),
  -- ONLY THE ENQUIRIES WE SENT THIS SUPPLIER (public.inquiry_matches is the answer to "what may this
  -- supplier quote for"; matching is exact trade or none).
  cand as (
    select i.id, i.category, i.emirate, i.summary_masked as summary, i.scope_type, i.created_at, i.budget_masked as budget,
           nullif(btrim(coalesce(i.raw_input_masked, '')), '') requirement,
           lower(coalesce(i.category, '')) cat
      from public.inquiries i
     where coalesce(i.status, 'open') = 'open'
       and exists (select 1 from public.inquiry_matches m
                    where m.inquiry_id = i.id and m.supplier_id = p_lead_id)
  ),
  scored as (
    select c.*,
      (c.cat = me.sector and me.sector <> '')                                    as trade_hit,
      (c.emirate is not null and (c.emirate = me.emirate
        or c.emirate = any(me.service_emirates)))                                as location_hit,
      (coalesce(cardinality(me.confirmed_trades), 0) > 0)                        as capacity_known,
      -- KEYED, NOT READ: the trades the supplier ticked against the enquiry's trade codes.
      (coalesce(cardinality(me.confirmed_trades), 0) > 0 and c.category is not null
        and public.fn_taxonomy_trades_for(array[c.category]) && me.confirmed_trades) as capacity_hit,
      (select count(*) from public.quotes q
         join public.inquiries qi on qi.id = q.inquiry_id
        where q.supplier_id = p_lead_id and lower(coalesce(qi.category,'')) = c.cat) as similar_jobs
      from cand c cross join me
  ),
  ranked as (
    select s.*,
      round(100.0 * (
        (case when s.trade_hit then 40 else 0 end)
      + (case when s.location_hit then 30 else 0 end)
      + (case when s.capacity_known and s.capacity_hit then 30 else 0 end)
      ) / nullif(40 + 30 + (case when s.capacity_known then 30 else 0 end), 0)) as fit_score
      from scored s
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'count', (select count(*) from ranked),
    'ordered_by', 'fit_score desc — a ranked list, never chronological',
    'population', jsonb_build_object(
      'matched_to_me', (select count(*) from public.inquiry_matches where supplier_id = p_lead_id),
      'open_for_me', (select count(*) from cand),
      'my_quotes', (select count(*) from public.quotes where supplier_id = p_lead_id)
    ),
    'note', case when (select count(*) from ranked) = 0
                 then 'no open opportunities yet — nothing has been matched to you'
                 else null end,
    'opportunities', coalesce((
      select jsonb_agg(x order by x->>'fit_score' desc) from (
        select jsonb_build_object(
          'inquiry_id', r.id,
          'project_title', coalesce(nullif(btrim(coalesce(public.fn_supplier_safe_text(r.id, r.summary), '')), ''), r.category, 'Untitled project'),
          'category', r.category,
          'emirate', r.emirate,
          'requirement', public.fn_supplier_safe_text(r.id, r.requirement),
          'estimated_value', public.fn_supplier_safe_text(r.id, r.budget),
          'fit_score', r.fit_score,
          'match_pct', r.fit_score,
          'reasons', jsonb_build_array(
            jsonb_build_object('key', 'trade', 'applies', r.trade_hit,
              'text', case when r.trade_hit then 'This is your trade — ' || coalesce(r.category,'the same category')
                           else 'Matched to you on capability rather than on your registered sector' end),
            jsonb_build_object('key', 'location', 'applies', r.location_hit,
              'text', case when r.location_hit then 'Nearby location — ' || coalesce(r.emirate,'your service area')
                           else 'Outside the emirates you serve' end),
            jsonb_build_object('key', 'capacity', 'applies', r.capacity_known and r.capacity_hit, 'available', r.capacity_known,
              'text', case when not r.capacity_known
                           then 'Your capacity fits: not assessable — you have not confirmed your services yet'
                           when r.capacity_hit
                           then 'Your capacity fits — this trade is among the services you confirmed'
                           else 'Not among the services you confirmed' end),
            jsonb_build_object('key', 'history', 'applies', r.similar_jobs > 0,
              'available', (select count(*) from public.quotes where supplier_id = p_lead_id) > 0,
              'similar_jobs', r.similar_jobs,
              'text', case when (select count(*) from public.quotes where supplier_id = p_lead_id) = 0
                           then 'Previous similar project: you have not quoted on QuotesDone yet'
                           when r.similar_jobs > 0
                           then 'You worked on ' || r.similar_jobs || ' previous similar project(s)'
                           else 'No previous similar project on record' end)
          )
        ) x from ranked r
      ) s
    ), '[]'::jsonb)
  )
$fn$;
revoke execute on function public.fn_supplier_opportunities(bigint) from public, anon, authenticated;
grant execute on function public.fn_supplier_opportunities(bigint) to service_role;

-- ── 4. the supplier's readings: what is due, and how a reading is recorded ───────────────────────
-- What _shared/reasoned_suppliers.ts still has to reason for one supplier: the capability summary when no
-- reading (reasoned or queued) exists for its current text, own service words with no reading, and the
-- services of the trades the supplier confirmed (the candidates an own word may name).
create or replace function public.fn_supplier_readings_due(p_lead_id bigint)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with l as (select id, nullif(btrim(coalesce(capability_summary, '')), '') summary from public.leads where id = p_lead_id),
  sc as (select * from public.supplier_capabilities where supplier_id = p_lead_id and confirmed_at is not null),
  keys as (select s.trade_code || '.' || s.code as k from public.taxonomy_trade_service s where s.active),
  own as (
    select distinct btrim(w) as w from sc, unnest(coalesce(sc.services, '{}'::text[])) w
     where nullif(btrim(w), '') is not null and btrim(w) not in (select k from keys)
       and length(btrim(w)) <= 200   -- the reading table's own limit: a longer entry is never sent to a model it cannot be recorded for
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'capability', (select jsonb_build_object('summary', left(l.summary, 4000), 'summary_md5', md5(l.summary)) from l
                    where l.summary is not null
                      and not exists (select 1 from public.supplier_capability_reading r where r.lead_id = l.id and r.summary_md5 = md5(l.summary))),
    'own_words', coalesce((select jsonb_agg(o.w order by o.w) from own o
                    where not exists (select 1 from public.supplier_own_word_reading r where r.supplier_id = p_lead_id and r.word = o.w)), '[]'::jsonb),
    'candidates', coalesce((select jsonb_agg(jsonb_build_object('key', s.trade_code || '.' || s.code, 'label', s.label_en, 'label_ar', s.label_ar) order by s.trade_code, s.sort, s.code)
                    from public.taxonomy_trade_service s, sc
                   where s.active and s.trade_code = any(coalesce(sc.trades, '{}'::text[]))), '[]'::jsonb))
$fn$;
revoke execute on function public.fn_supplier_readings_due(bigint) from public, anon, authenticated;
grant execute on function public.fn_supplier_readings_due(bigint) to service_role;

-- p_kinds null = held (queued as p_held_id); otherwise {manufacturing, installation, maintenance, design} booleans.
create or replace function public.fn_supplier_capability_reading_record(p_lead_id bigint, p_summary_md5 text, p_kinds jsonb, p_held_id bigint default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_status text := case when p_kinds is null then 'needs_reasoning' else 'reasoned' end;
begin
  if p_kinds is not null and not (jsonb_typeof(p_kinds->'manufacturing') = 'boolean' and jsonb_typeof(p_kinds->'installation') = 'boolean'
                                  and jsonb_typeof(p_kinds->'maintenance') = 'boolean' and jsonb_typeof(p_kinds->'design') = 'boolean') then
    raise exception 'a capability reading needs four booleans' using errcode = '22023';
  end if;
  insert into public.supplier_capability_reading as r (lead_id, summary_md5, manufacturing, installation, maintenance, design, status, held_id, reasoned_at, updated_at)
  values (p_lead_id, p_summary_md5, (p_kinds->>'manufacturing')::boolean, (p_kinds->>'installation')::boolean,
          (p_kinds->>'maintenance')::boolean, (p_kinds->>'design')::boolean, v_status, p_held_id,
          case when p_kinds is null then null else now() end, now())
  on conflict (lead_id) do update set summary_md5 = excluded.summary_md5, manufacturing = excluded.manufacturing,
    installation = excluded.installation, maintenance = excluded.maintenance, design = excluded.design,
    status = excluded.status, held_id = coalesce(excluded.held_id, r.held_id), reasoned_at = excluded.reasoned_at, updated_at = now()
  -- a queued reading never overwrites a reasoned one of the same text
  where not (excluded.status = 'needs_reasoning' and r.status = 'reasoned' and r.summary_md5 = excluded.summary_md5);
  return jsonb_build_object('lead_id', p_lead_id, 'status', v_status);
end $fn$;
revoke execute on function public.fn_supplier_capability_reading_record(bigint, text, jsonb, bigint) from public, anon, authenticated;
grant execute on function public.fn_supplier_capability_reading_record(bigint, text, jsonb, bigint) to service_role;

-- p_reasoned false = held; p_service_key null with p_reasoned = the word names no listed service.
create or replace function public.fn_supplier_own_word_reading_record(p_supplier_id bigint, p_word text, p_service_key text, p_reasoned boolean, p_held_id bigint default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_status text := case when p_reasoned then 'reasoned' else 'needs_reasoning' end;
begin
  if p_reasoned and p_service_key is not null and not exists (
       select 1 from public.taxonomy_trade_service s where s.active and s.trade_code || '.' || s.code = p_service_key) then
    raise exception 'not a listed service: %', p_service_key using errcode = '22023';
  end if;
  insert into public.supplier_own_word_reading as r (supplier_id, word, service_key, status, held_id, reasoned_at, updated_at)
  values (p_supplier_id, btrim(p_word), case when p_reasoned then p_service_key end, v_status, p_held_id,
          case when p_reasoned then now() end, now())
  on conflict (supplier_id, word) do update set service_key = excluded.service_key, status = excluded.status,
    held_id = coalesce(excluded.held_id, r.held_id), reasoned_at = excluded.reasoned_at, updated_at = now()
  where not (excluded.status = 'needs_reasoning' and r.status = 'reasoned');
  return jsonb_build_object('supplier_id', p_supplier_id, 'word', btrim(p_word), 'status', v_status);
end $fn$;
revoke execute on function public.fn_supplier_own_word_reading_record(bigint, text, text, boolean, bigint) from public, anon, authenticated;
grant execute on function public.fn_supplier_own_word_reading_record(bigint, text, text, boolean, bigint) to service_role;

-- ── 5. fn_supplier_twin: capabilities from keyed data and the reasoned reading ───────────────────
create or replace function public.fn_supplier_twin(p_lead_id bigint)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with l as (select * from public.leads where id = p_lead_id),
  s as (select *, quality_rating as q_pct from public.supplier_score where lead_id = p_lead_id),
  q as (
    select count(*)::int submitted,
           greatest(count(*) filter (where status = 'won')::int,
                    (select count(*)::int from public.inquiries where hired_supplier_id = p_lead_id)) won
    from public.quotes where supplier_id = p_lead_id
  ),
  home as (select * from public.fn_supplier_document_home(p_lead_id)),
  -- THE READING OF THE CURRENT SUMMARY ONLY: an edited summary is read again (its md5 changes).
  rd as (
    select r.* from public.supplier_capability_reading r, l
     where r.lead_id = l.id and r.status = 'reasoned'
       and r.summary_md5 = md5(nullif(btrim(coalesce(l.capability_summary, '')), ''))
  ),
  caps as (
    select
      (select coalesce(jsonb_array_length(case when jsonb_typeof(l.machinery)='array' then l.machinery else '[]'::jsonb end), 0) > 0 from l)
        or coalesce((select manufacturing from rd), false)                  as manufacturing,
      (select coalesce(l.engineers_count, 0) > 0 from l)
        or coalesce((select installation from rd), false)                   as installation,
      coalesce((select maintenance from rd), false)                         as maintenance,
      coalesce((select design from rd), false)                              as design
  ),
  conf as (
    select round(100.0 * (
        (case when l.company_name       is not null then 1 else 0 end)
      + (case when l.sector             is not null then 1 else 0 end)
      + (case when l.capability_summary is not null then 1 else 0 end)
      + (case when l.founded_year        is not null then 1 else 0 end)
      + (case when l.employee_count      is not null or l.team_size is not null then 1 else 0 end)
      + (case when coalesce(array_length(l.service_emirates, 1), 0) > 0 then 1 else 0 end)
      + (case when coalesce(l.certifications, '') <> ''
                or (jsonb_typeof(l.iso_certifications)='array' and jsonb_array_length(l.iso_certifications) > 0) then 1 else 0 end)
      + (case when l.products is not null and l.products <> '' then 1 else 0 end)
      + (case when l.website is not null then 1 else 0 end)
      + (case when l.description is not null then 1 else 0 end)
      ) / 10.0) as pct
    from l
  ),
  risk as (
    select case
      when l.banned then 'BANNED'
      when l.matching_blocked then 'BLOCKED'
      when (select path from home where key = 'trade_licence') is null
           and coalesce(l.chat_strikes, 0) = 0 and (select reliability from s) is null then null
      when l.license_expiry is not null and l.license_expiry < current_date then 'HIGH'
      when (select expiry from home where key = 'iso') < current_date then 'HIGH'
      when l.license_expiry is not null and l.license_expiry < current_date + 60 then 'MEDIUM'
      when coalesce(l.chat_strikes, 0) > 0 then 'MEDIUM'
      when (select reliability from s) is not null and (select reliability from s) < 60 then 'MEDIUM'
      else 'LOW' end as level
    from l
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'company_name', (select company_name from l),
    'verified', (select coalesce(verified, false) from l),
    'approval_status', (select approval_status from l),
    'intelligence_score', (
      select round(avg(v)) from (
        select (select q_pct from s) as v
        union all select (select reliability    from s)
        union all select (select response_rate  from s)
        union all select (select price_index    from s)
      ) t where v is not null
    ),
    'star_rating', (
      select case when avg(v) is null then null else greatest(1, least(5, round(avg(v) / 20.0))) end
      from (
        select (select q_pct from s) as v
        union all select (select reliability   from s)
        union all select (select response_rate from s)
      ) t where v is not null
    ),
    'health', jsonb_build_object(
      'quality', (select q_pct from s),
      'quality_raw',   (select quality_rating from s),
      'quality_scale', (select case when quality_rating is null then 'unrated' else 'earned_pct' end from s),
      'delivery', (select reliability    from s),
      'response', coalesce((select response_rate from s), (select rv_response_rate from l)),
      'pricing',  (select price_index    from s),
      'overall', (
        select round(avg(v)) from (
          select (select q_pct from s) as v
          union all select (select reliability   from s)
          union all select (select response_rate from s)
          union all select (select price_index   from s)
        ) t where v is not null
      ),
      'computed_at',        (select computed_at        from s),
      'avg_response_hours', (select avg_response_hours from s),
      'quotes_submitted',   (select submitted from q),
      'quotes_won',         (select won from q)
    ),
    'company_strength', (select capability_score from l),
    'capabilities', (
      select jsonb_build_array(
        jsonb_build_object('name', 'Manufacturing', 'has', (select manufacturing from caps)),
        jsonb_build_object('name', 'Installation',  'has', (select installation  from caps)),
        jsonb_build_object('name', 'Maintenance',   'has', (select maintenance   from caps)),
        jsonb_build_object('name', 'Design',        'has', (select design        from caps))
      )
    ),
    -- 'reasoned': the summary was read; 'needs_reasoning': it waits for the reasoning (shown from keyed
    -- data meanwhile); 'no_summary': there is nothing to read.
    'capability_reading', (select case when nullif(btrim(coalesce(l.capability_summary, '')), '') is null then 'no_summary'
                                       when exists (select 1 from rd) then 'reasoned' else 'needs_reasoning' end from l),
    'product_count', (
      select case when l.products is null or l.products = '' then 0
             else array_length(string_to_array(l.products, ','), 1) end from l
    ),
    'certifications', (
      select (case when jsonb_typeof(l.iso_certifications)='array' then l.iso_certifications else '[]'::jsonb end)
          || (case when coalesce(l.certifications,'') = '' then '[]'::jsonb
                   else to_jsonb(string_to_array(l.certifications, ',')) end) from l
    ),
    'production_capacity', (
      select jsonb_build_object(
        'estimated', case
          when l.team_size is null and l.engineers_count is null and l.warehouse_area is null then null
          else coalesce(l.team_size, 0) * 40 + coalesce(l.engineers_count, 0) * 120
               + coalesce(round(nullif(regexp_replace(coalesce(l.warehouse_area,''), '[^0-9]', '', 'g'), '')::numeric / 10.0), 0) end,
        'is_estimate', true,
        'basis', jsonb_build_object('team_size', l.team_size, 'engineers', l.engineers_count,
                                    'warehouse_area', l.warehouse_area,
                                    'machinery_lines', coalesce(jsonb_array_length(case when jsonb_typeof(l.machinery)='array' then l.machinery else '[]'::jsonb end), 0))
      ) from l
    ),
    'best_opportunities', (
      select case when coalesce(l.categories,'') = '' then '[]'::jsonb
                  else to_jsonb(string_to_array(l.categories, ',')) end from l
    ),
    'risk_level', (select level from risk),
    'risk_basis', case when (select level from risk) is null
                       then 'not assessed: no trade licence on file and no history yet'
                       else 'trade licence and certificate expiry, bans, strikes and computed reliability' end,
    'established_year', (select founded_year from l),
    'employee_count',   (select coalesce(l.employee_count, l.team_size) from l),
    'emirates',         (select coalesce(to_jsonb(coalesce(l.service_emirates, '{}'::text[])), '[]'::jsonb) from l),
    'countries',        (select coalesce(to_jsonb(coalesce(l.service_emirates, '{}'::text[])), '[]'::jsonb) from l),
    'ai_confidence',    (select pct from conf),
    'capability_map', (
      select jsonb_build_object(
        'root', coalesce(l.sector, 'Supplier'),
        'children', (
          select jsonb_agg(jsonb_build_object('name', c.name))
          from (
            select 'Manufacturing' as name where (select manufacturing from caps)
            union all select 'Installation' where (select installation from caps)
            union all select 'Maintenance'  where (select maintenance  from caps)
            union all select 'Design'       where (select design       from caps)
          ) c
        )
      ) from l
    ),
    'documents', (
      select jsonb_agg(jsonb_build_object(
        'kind', case h.key when 'trade_licence' then 'Trade licence' when 'iso' then 'ISO certification' else 'Manufacturer authorisation' end,
        'key', h.key, 'expiry', h.expiry, 'source', h.source,
        'doc_status', case when h.path is null then 'MISSING'
                           when h.expiry is null then 'UNDATED'
                           when h.expiry < current_date then 'EXPIRED'
                           else 'VALID' end)
        order by case h.key when 'trade_licence' then 0 when 'iso' then 1 else 2 end)
      from home h where h.key in ('trade_licence', 'iso', 'manufacturer_auth')
    ),
    -- the demo fence is the leads.is_demo flag, never a word found in the tags
    'is_demo', (select coalesce(l.is_demo, false) from l),
    'matchable', (select public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                          l.approval_status, l.permanently_closed, l.chat_strikes) from l)
  );
$fn$;
revoke execute on function public.fn_supplier_twin(bigint) from public, anon, authenticated;
grant execute on function public.fn_supplier_twin(bigint) to service_role;

-- ── 6. fn_supplier_portfolio_gaps: an own word names a service only by reasoning ─────────────────
create or replace function public.fn_supplier_portfolio_gaps(p_lead_id bigint)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with sc as (select * from public.supplier_capabilities where supplier_id = p_lead_id and confirmed_at is not null),
  keys as (select s.trade_code, s.trade_code || '.' || s.code as k from public.taxonomy_trade_service s where s.active),
  silent as (
    select t.code, t.label, coalesce(t.label_ar, t.label) as label_ar
      from sc, unnest(coalesce(sc.trades, '{}'::text[])) tr
      join public.taxonomy_trade t on t.code = tr
     where public.fn_supplier_portfolio_match_reads_ticks()
       and exists (select 1 from keys where keys.trade_code = tr)
       and not exists (select 1 from unnest(coalesce(sc.services, '{}'::text[])) s
                         join keys on keys.k = btrim(s)
                        where keys.trade_code = tr and btrim(s) <> all (coalesce(sc.services_removed, '{}'::text[])))
  ),
  own as (
    select distinct btrim(w) as w
      from sc, unnest(coalesce(sc.services, '{}'::text[])) w
     where nullif(btrim(w), '') is not null and btrim(w) not in (select k from keys)
  ),
  -- THE SERVICE A WORD NAMES IS A REASONED READING (supplier_own_word_reading), never an alias pattern.
  named as (
    select o.w, array[r.service_key] as keys,
           '"' || s.label_en || '" under ' || t.label as en_list,
           '«' || s.label_ar || '» ضمن ' || coalesce(t.label_ar, t.label) as ar_list
      from own o
      join public.supplier_own_word_reading r on r.supplier_id = p_lead_id and r.word = o.w and r.status = 'reasoned'
      join public.taxonomy_trade_service s on s.active and s.trade_code || '.' || s.code = r.service_key
      join public.taxonomy_trade t on t.code = s.trade_code
  ),
  unnamed as (select o.w from own o where o.w not in (select w from named)),
  proposed as (
    select exists (select 1 from public.taxonomy_trade_proposal p, unnamed u
                    where p.supplier_id = p_lead_id and p.status = 'pending'
                      and (btrim(p.label_en) = u.w or btrim(p.label_ar) = u.w)) as yes
  )
  select case
    when not exists (select 1 from sc) then jsonb_build_array(jsonb_build_object(
      'code', 'services_not_confirmed',
      'en', 'You have not confirmed the services your company provides yet, so no inquiry can reach you.',
      'ar', 'لم تؤكّدوا بعد الخدمات التي تقدّمها شركتكم، ولذلك لا يصلكم أي استفسار.'))
    else
      coalesce((select jsonb_agg(jsonb_build_object(
          'code', 'trade_without_service', 'trade', s.code,
          'en', s.label || ': no service is ticked yet, so inquiries that name a service in this trade do not reach you.',
          'ar', s.label_ar || ': لم تحدّدوا أي خدمة فيه بعد، ولذلك لا تصلكم الاستفسارات التي تذكر خدمة في هذا التخصص.')
          order by s.code) from silent s), '[]'::jsonb)
      || coalesce((select jsonb_agg(jsonb_build_object(
          'code', 'own_word_is_a_service', 'word', n.w, 'services', to_jsonb(n.keys),
          'en', '«' || n.w || '» is on our list as ' || n.en_list
                || '. Tick the ones you provide in the Services tab so the inquiries that name them reach you.',
          'ar', '«' || n.w || '» مدرجة في قائمتنا باسم ' || n.ar_list
                || '. يُرجى تحديد ما تقدّمونه منها في تبويب «الخدمات» لتصلكم الاستفسارات التي تذكرها.')
          order by n.w) from named n), '[]'::jsonb)
      || coalesce((select jsonb_build_array(jsonb_build_object(
          'code', 'own_words', 'words', jsonb_agg(u.w order by u.w),
          'en', 'Written in your own words and not on our list: '
                || string_agg('«' || u.w || '»', ', ' order by u.w)
                || '. As written they match no inquiry. If one of them is on the list under another name, tick it there'
                || case when (select yes from proposed) then '; our sales engineer is reviewing them for the list' else '' end || '.',
          'ar', 'خدمات كتبتموها بأسلوبكم وليست في قائمتنا: '
                || string_agg('«' || u.w || '»', '، ' order by u.w)
                || '. ولا تُطابَق بصيغتها هذه مع أي استفسار. وإن وجدتم أيًّا منها في القائمة باسم آخر، فحدّدوه هناك'
                || case when (select yes from proposed) then '، ويراجعها مهندس المبيعات حاليًا لإضافتها إلى القائمة' else '' end || '.'))
          from unnamed u having count(*) > 0), '[]'::jsonb)
  end
$fn$;
revoke execute on function public.fn_supplier_portfolio_gaps(bigint) from public, anon, authenticated;
grant execute on function public.fn_supplier_portfolio_gaps(bigint) to service_role;

-- ── 7. fn_rfq_short_of_quotes_tick: the need is keyed ────────────────────────────────────────────
create or replace function public.fn_rfq_short_of_quotes_tick(p_include_fixtures boolean default false)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  -- the top-3 rule: the comparison report is the top 3 (founder rule). A constant, not a setting.
  c_target constant int := 3;
  v_window numeric; v_lead numeric := public.fn_seat_clock_policy('rfq_short_sweep_hours_before_deadline', 8);
  v_fanout int := coalesce(public.fn_seat_clock_policy('match_max_fanout', 5), 5)::int;
  r record; s record; l public.leads; v jsonb; v_codes text[]; v_need text; v_value numeric; v_new int;
  v_swept int := 0; v_invited int := 0; v_reminded int := 0; v_told int := 0; v_skipped jsonb := '[]'::jsonb;
begin
  select nullif(regexp_replace(coalesce(value, ''), '[^0-9.]', '', 'g'), '')::numeric into v_window
    from public.app_secrets where key = 'sla_quote_hours';
  v_window := coalesce(v_window, 24);

  for r in
    with open_rfq as (
      select i.*, c.email as cemail, c.locale as clocale, c.full_name as cname,
             public.fn_seat_clock_customer_is_fixture(c) as fixture,
             (select min(m.sent_at) from public.inquiry_matches m where m.inquiry_id = i.id) as first_sent,
             (select count(*) from public.quotes q where q.inquiry_id = i.id
                and coalesce(q.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'held', 'cancelled')
                and q.stale_at is null)::int as live_quotes
        from public.inquiries i
        join public.customers c on c.id = i.customer_id
       where i.status in ('sent', 'quoted')
    )
    select o.*, o.first_sent + make_interval(secs => (v_window * 3600)::double precision) as deadline
      from open_rfq o
     where o.first_sent is not null
       and o.live_quotes < c_target
       and now() >= o.first_sent + make_interval(secs => ((v_window - v_lead) * 3600)::double precision)
       and now() <  o.first_sent + interval '14 days'
       and (p_include_fixtures or not o.fixture)
     order by o.first_sent
  loop
    v_swept := v_swept + 1;

    -- (a) widen ONCE, from the same matcher, same-kind suppliers only.
    if not coalesce(r.routing ? 'short_sweep', false) then
      v_new := 0;
      v_codes := public.fn_taxonomy_trades_for(case when coalesce(cardinality(r.trades), 0) > 0 then r.trades
                                                    else array[coalesce(r.category, '')] end);
      if coalesce(cardinality(v_codes), 0) > 0 then
        -- KEYED, NOT READ: scope_type is customer_api's own set (single | multi | turnkey) and role_needed is
        -- one of fn_match_capability's needs when the request carried one.
        v_need := case when r.scope_type = 'turnkey' then 'whole_scope'
                       when r.role_needed in ('whole_scope', 'supplies', 'executes') then r.role_needed
                       else 'executes' end;
        v_value := coalesce(r.expected_value, nullif(regexp_replace(coalesce(r.budget, ''), '[^0-9.]', '', 'g'), '')::numeric);
        if v_value is not null and v_value <= 0 then v_value := null; end if;
        for s in select m.supplier_id, m.score, m.why
                   from public.fn_match_capability(v_codes, v_need, '{}'::text[], '{}'::text[], r.scope_type, v_value, r.emirate, 60) m
                   join public.leads ld on ld.id = m.supplier_id
                  where not exists (select 1 from public.inquiry_matches x where x.inquiry_id = r.id and x.supplier_id = m.supplier_id)
                    and public.fn_seat_clock_lead_is_fixture(ld) = r.fixture
                  order by m.score desc
                  limit v_fanout loop
          insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, match_reason)
          values (r.id, s.supplier_id, least(1, greatest(0, round(s.score / 100, 3))),
                  left('short-of-quotes sweep (fn_rfq_short_of_quotes_tick): ' || coalesce(s.why, ''), 400))
          on conflict (inquiry_id, supplier_id) do nothing;
          if found then
            v_new := v_new + 1;
            select * into l from public.leads where id = s.supplier_id;
            v := public.fn_seat_clock_deliver('sales_engineer', 'supplier_rfq_widened_invite', 'supplier',
                   lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email))), r.fixture, l.locale, 'rfq_invite',
                   jsonb_build_object('name', l.company_name, 'category', r.category, 'emirate', r.emirate),
                   'rfq_invite:' || r.id || ':' || l.id, r.id, null, l.id);
          end if;
        end loop;
      end if;
      update public.inquiries
         set routing = coalesce(routing, '{}'::jsonb) || jsonb_build_object('short_sweep', jsonb_build_object(
               'at', now(), 'quotes_then', r.live_quotes, 'invited', v_new, 'trades', to_jsonb(v_codes),
               'by', 'sales_engineer (fn_rfq_short_of_quotes_tick)'))
       where id = r.id;
      v_invited := v_invited + v_new;
    end if;

    -- (b) remind each invited supplier who has not quoted, once. Not one invited in the last 2 hours.
    for l in select ld.* from public.inquiry_matches m join public.leads ld on ld.id = m.supplier_id
              where m.inquiry_id = r.id and m.sent_at < now() - interval '2 hours'
                and not exists (select 1 from public.quotes q where q.inquiry_id = r.id and q.supplier_id = m.supplier_id)
                and public.fn_seat_clock_lead_is_fixture(ld) = r.fixture loop
      v := public.fn_seat_clock_deliver('sales_engineer', 'rfq_quote_reminder', 'supplier',
             lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email))), r.fixture, l.locale, 'rfq_quote_reminder',
             jsonb_build_object('name', l.company_name, 'category', r.category, 'emirate', r.emirate, 'deadline', r.deadline),
             'rfq_quote_reminder:' || r.id || ':' || l.id, r.id, null, l.id);
      if coalesce((v->>'ok')::boolean, false) and not coalesce((v->>'already')::boolean, false) then v_reminded := v_reminded + 1; end if;
    end loop;

    -- (c) at the deadline, tell the customer once.
    if now() >= r.deadline then
      v := public.fn_seat_clock_deliver('sales_engineer', 'rfq_short_of_quotes', 'customer', r.cemail, r.fixture, r.clocale,
             'rfq_short_of_quotes',
             jsonb_build_object('name', r.cname, 'category', r.category, 'emirate', r.emirate, 'quotes', r.live_quotes),
             'rfq_short_of_quotes:' || r.id, r.id);
      if coalesce((v->>'ok')::boolean, false) and not coalesce((v->>'already')::boolean, false) then v_told := v_told + 1;
      elsif not coalesce((v->>'ok')::boolean, false) then
        v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('inquiry_id', r.id, 'reason', v->>'reason'));
      end if;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'swept', v_swept, 'invited', v_invited, 'reminded', v_reminded,
                            'customers_told', v_told, 'not_written', v_skipped,
                            'deadline_hours', v_window, 'sweep_from_hours_before', v_lead);
end
$fn$;
revoke execute on function public.fn_rfq_short_of_quotes_tick(boolean) from public, anon, authenticated;
grant execute on function public.fn_rfq_short_of_quotes_tick(boolean) to service_role;

-- ── 8. trg_quote_quality: category aspects from the reasoned reading, held until read ────────────
-- The quote's text as the reasoning reads it and as the reading is keyed (md5). One definition, so the
-- trigger, the due query and the reading can never disagree about what "the same quote" is.
create or replace function public.fn_quote_aspect_text(p_q public.quotes)
returns text
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select concat_ws(E'\n', p_q.scope, p_q.conditions, p_q.exclusions, p_q.notes, p_q.warranty, p_q.payment_terms,
                   p_q.lead_time, p_q.validity,
                   (select string_agg(concat_ws(' ', qi.description, qi.brand, qi.model, qi.specification), E'\n' order by qi.id)
                      from public.quote_items qi where qi.quote_id = p_q.id::text))
$fn$;
revoke execute on function public.fn_quote_aspect_text(public.quotes) from public, anon, authenticated;
grant execute on function public.fn_quote_aspect_text(public.quotes) to service_role;

create or replace function public.trg_quote_quality()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare cat text; grp text; v_md5 text; v_present text[]; v_cat_status text := null;
  n int; priced int; branded int; spec_n int; laboured int;
  pts int := 0; gmiss text[] := '{}'; cmiss jsonb := '[]'::jsonb; cmand_missing int := 0;
  r record; cat_pass boolean := true;
begin
  select category into cat from public.inquiries where id = NEW.inquiry_id;

  select count(*),
    count(*) filter (where coalesce(unit_price,0)>0 and coalesce(qty,0)>0),
    count(*) filter (where coalesce(brand,'')<>'' and coalesce(model,'')<>''),
    count(*) filter (where coalesce(specification,'')<>''),
    count(*) filter (where coalesce(labour,0)>0 or coalesce(install,0)>0)
    into n, priced, branded, spec_n, laboured
    from public.quote_items where quote_id = NEW.id::text;

  if coalesce(n,0)=0 then gmiss := array_append(gmiss,'an itemised breakdown (not just a lump sum)');
  else pts:=pts+15; if priced=n then pts:=pts+20; else gmiss:=array_append(gmiss,'a unit price on every line'); end if; end if;
  if n>0 and branded=n then pts:=pts+15; else gmiss:=array_append(gmiss,'the brand/model for each item'); end if;
  if n>0 and spec_n>=greatest(1,n/2) then pts:=pts+10; else gmiss:=array_append(gmiss,'the key specifications'); end if;
  if coalesce(laboured,0)>0 then pts:=pts+10; else gmiss:=array_append(gmiss,'the labour / installation cost'); end if;
  if coalesce(btrim(NEW.warranty),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'the warranty period'); end if;
  if coalesce(btrim(NEW.lead_time),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'the lead / delivery time'); end if;
  if coalesce(btrim(NEW.payment_terms),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'the payment terms'); end if;
  if coalesce(btrim(NEW.exclusions),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'what is excluded'); end if;
  if coalesce(btrim(NEW.validity),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'how long the quote is valid'); end if;

  grp := public.fn_quote_spec_group(coalesce(cat,''));
  if grp is not null and exists (select 1 from public.category_quote_specs where spec_group=grp) then
    -- WHICH ASPECTS THE QUOTE STATES IS A REASONED READING of this exact text (quote_aspect_reading),
    -- never a pattern over the text. No reading yet: the category verdict is 'needs_reasoning' and NOT a pass.
    v_md5 := md5(coalesce(public.fn_quote_aspect_text(NEW), ''));
    select a.present into v_present from public.quote_aspect_reading a
     where a.quote_id = NEW.id and a.content_md5 = v_md5 and a.status = 'reasoned';
    if found then
      v_cat_status := 'reasoned';
      for r in select * from public.category_quote_specs where spec_group=grp order by mandatory desc, aspect loop
        if not (r.aspect = any(coalesce(v_present, '{}'::text[]))) then
          cmiss := cmiss || jsonb_build_object('label', r.label, 'mandatory', r.mandatory);
          if r.mandatory then cmand_missing := cmand_missing + 1; end if;
        end if;
      end loop;
      cat_pass := (cmand_missing = 0);
    else
      v_cat_status := 'needs_reasoning';
      cat_pass := false;
    end if;
  end if;

  NEW.quality := jsonb_build_object(
    'score', pts, 'pass', (pts >= 70 and cat_pass), 'submittable', (pts >= 70 and cat_pass),
    'missing', to_jsonb(gmiss),
    'category', case when grp is null then null else jsonb_build_object(
        'group', grp, 'status', v_cat_status, 'content_md5', v_md5, 'pass', cat_pass,
        'mandatory_missing', case when v_cat_status = 'reasoned' then cmand_missing end,
        'missing', case when v_cat_status = 'reasoned' then cmiss end) end,
    'scored_at', now());
  NEW.submittable := (pts >= 70 and cat_pass);
  return NEW;
end $fn$;
revoke execute on function public.trg_quote_quality() from public, anon, authenticated;
grant execute on function public.trg_quote_quality() to service_role;

-- What _shared/reasoned_suppliers.ts has to reason for one quote: its text, md5 and the aspects of its
-- spec group. Null when the quote has no spec group, or a reading (reasoned or queued) of this text exists.
create or replace function public.fn_quote_aspects_due(p_quote_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare q public.quotes; v_grp text; v_text text;
begin
  select * into q from public.quotes where id = p_quote_id;
  if not found then return null; end if;
  v_grp := public.fn_quote_spec_group(coalesce((select category from public.inquiries where id = q.inquiry_id), ''));
  if v_grp is null or not exists (select 1 from public.category_quote_specs where spec_group = v_grp) then return null; end if;
  v_text := coalesce(public.fn_quote_aspect_text(q), '');
  if exists (select 1 from public.quote_aspect_reading a where a.quote_id = p_quote_id and a.content_md5 = md5(v_text)) then return null; end if;
  return jsonb_build_object('quote_id', p_quote_id, 'content_md5', md5(v_text), 'text', left(v_text, 8000), 'spec_group', v_grp,
    'aspects', (select jsonb_agg(jsonb_build_object('aspect', c.aspect, 'label', c.label, 'mandatory', c.mandatory, 'note', c.note)
                                 order by c.mandatory desc, c.aspect)
                  from public.category_quote_specs c where c.spec_group = v_grp));
end $fn$;
revoke execute on function public.fn_quote_aspects_due(uuid) from public, anon, authenticated;
grant execute on function public.fn_quote_aspects_due(uuid) to service_role;

-- p_present null = held (queued as p_held_id). A reading of the CURRENT text re-scores the quote at once.
create or replace function public.fn_quote_aspect_reading_record(p_quote_id uuid, p_content_md5 text, p_present text[], p_held_id bigint default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_status text := case when p_present is null then 'needs_reasoning' else 'reasoned' end; v_bad text[]; q public.quotes; v_rescored boolean := false;
begin
  select * into q from public.quotes where id = p_quote_id;
  if not found then raise exception 'no quote %', p_quote_id using errcode = 'P0002'; end if;
  select array_agg(x) into v_bad from unnest(coalesce(p_present, '{}'::text[])) x
   where not exists (select 1 from public.category_quote_specs c
                      where c.aspect = x and c.spec_group = public.fn_quote_spec_group(coalesce((select category from public.inquiries where id = q.inquiry_id), '')));
  if v_bad is not null then raise exception 'not an aspect of this quote''s group: %', v_bad using errcode = '22023'; end if;
  insert into public.quote_aspect_reading as a (quote_id, content_md5, present, status, held_id, reasoned_at, updated_at)
  values (p_quote_id, p_content_md5, p_present, v_status, p_held_id, case when p_present is null then null else now() end, now())
  on conflict (quote_id) do update set content_md5 = excluded.content_md5, present = excluded.present, status = excluded.status,
    held_id = coalesce(excluded.held_id, a.held_id), reasoned_at = excluded.reasoned_at, updated_at = now()
  where not (excluded.status = 'needs_reasoning' and a.status = 'reasoned' and a.content_md5 = excluded.content_md5);
  if v_status = 'reasoned' and p_content_md5 = md5(coalesce(public.fn_quote_aspect_text(q), '')) then
    update public.quotes set quality = quality where id = p_quote_id;   -- re-fires trg_quote_quality
    v_rescored := true;
  end if;
  return jsonb_build_object('quote_id', p_quote_id, 'status', v_status, 'rescored', v_rescored,
                            'quality', (select quality from public.quotes where id = p_quote_id));
end $fn$;
revoke execute on function public.fn_quote_aspect_reading_record(uuid, text, text[], bigint) from public, anon, authenticated;
grant execute on function public.fn_quote_aspect_reading_record(uuid, text, text[], bigint) to service_role;

-- ── 9. the replay effects (fn_reason_held_resolve calls these when the hold lifts) ──────────────
-- A field counts as stated when the reasoning gave BOTH a value and the words that say so (think()'s field
-- shape, whose evidence it has already checked is copied verbatim). The same rule as reasoned_suppliers.ts.
create or replace function public.fn_reason_field_stated(p_field jsonb)
returns boolean
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(btrim(p_field->>'value'), '') <> '' and coalesce(btrim(p_field->>'evidence'), '') <> ''
$fn$;
revoke execute on function public.fn_reason_field_stated(jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_field_stated(jsonb) to service_role;

create or replace function public.fn_reason_apply_sql__fn_supplier_twin(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; f jsonb := coalesce(p_result->'decision'->'fields', '{}'::jsonb);
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if (r.subject->>'lead_id') is null or (r.subject->>'summary_md5') is null then return jsonb_build_object('skipped', 'no subject'); end if;
  -- A reading of a summary that has since been edited is stale: it must not replace the reading of the current one.
  if not exists (select 1 from public.leads l where l.id = (r.subject->>'lead_id')::bigint
                   and md5(nullif(btrim(coalesce(l.capability_summary, '')), '')) = r.subject->>'summary_md5') then
    return jsonb_build_object('skipped', 'stale');
  end if;
  return public.fn_supplier_capability_reading_record((r.subject->>'lead_id')::bigint, r.subject->>'summary_md5',
    jsonb_build_object('manufacturing', public.fn_reason_field_stated(f->'manufacturing'),
                       'installation',  public.fn_reason_field_stated(f->'installation'),
                       'maintenance',   public.fn_reason_field_stated(f->'maintenance'),
                       'design',        public.fn_reason_field_stated(f->'design')), p_id);
end $fn$;
revoke execute on function public.fn_reason_apply_sql__fn_supplier_twin(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_sql__fn_supplier_twin(bigint, jsonb) to service_role;

create or replace function public.fn_reason_apply_sql__fn_supplier_portfolio_gaps(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice';
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if (r.subject->>'supplier_id') is null or (r.subject->>'word') is null then return jsonb_build_object('skipped', 'no subject'); end if;
  return public.fn_supplier_own_word_reading_record((r.subject->>'supplier_id')::bigint, r.subject->>'word',
    case when v_choice is null or v_choice = 'none' then null else v_choice end, true, p_id);
end $fn$;
revoke execute on function public.fn_reason_apply_sql__fn_supplier_portfolio_gaps(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_sql__fn_supplier_portfolio_gaps(bigint, jsonb) to service_role;

create or replace function public.fn_reason_apply_sql__trg_quote_quality(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_present text[];
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if (r.subject->>'quote_id') is null or (r.subject->>'content_md5') is null then return jsonb_build_object('skipped', 'no subject'); end if;
  if not exists (select 1 from public.quotes where id = (r.subject->>'quote_id')::uuid) then return jsonb_build_object('skipped', 'quote gone'); end if;
  -- A reading of text the supplier has since changed is stale: it must not replace the reading of the current text.
  if (select md5(coalesce(public.fn_quote_aspect_text(q), '')) from public.quotes q where q.id = (r.subject->>'quote_id')::uuid) <> r.subject->>'content_md5' then
    return jsonb_build_object('skipped', 'stale');
  end if;
  select coalesce(array_agg(k order by k), '{}'::text[]) into v_present
    from jsonb_each(coalesce(p_result->'decision'->'fields', '{}'::jsonb)) as e(k, v)
   where public.fn_reason_field_stated(v);
  return public.fn_quote_aspect_reading_record((r.subject->>'quote_id')::uuid, r.subject->>'content_md5', v_present, p_id);
end $fn$;
revoke execute on function public.fn_reason_apply_sql__trg_quote_quality(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_sql__trg_quote_quality(bigint, jsonb) to service_role;

-- ── 10. fn_category_key_from_text: references only, never a name found in the text ──────────────
create or replace function public.fn_category_key_from_text(p_text text)
returns text
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
-- SCALARS, NOT A RECORD: a plpgsql record that was never assigned raises "not assigned yet" on its first
-- field reference, so the run-less path would have thrown instead of falling through (caught in rehearsal).
-- Every step below parses a REFERENCE (a uuid after "inquiry" or "run", a key in its own format) and looks
-- it up; none decides what the text is about. The fourth step (a catalogue name found as a substring of
-- the text, the longest winning) is deleted: a task that names no inquiry, run or key gets no category pack.
declare v_id uuid; v_run uuid; v_slug text; v_key text;
        v_ev_type text; v_ev_entity text; v_ev_payload jsonb; v_ctx jsonb;
begin
  if coalesce(p_text, '') = '' then return null; end if;

  -- 1. an explicit inquiry reference
  begin
    v_id := substring(p_text from '(?i)inquiry[:=# ]\s*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')::uuid;
  exception when others then v_id := null; end;

  -- 2. a workflow run reference: the event that started the run names the inquiry
  if v_id is null then
    begin
      v_run := substring(p_text from '(?i)\mrun[:=#]\s*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')::uuid;
    exception when others then v_run := null; end;
    if v_run is not null then
      select e.entity_type, e.entity_id, e.payload, r.context into v_ev_type, v_ev_entity, v_ev_payload, v_ctx
        from public.workflow_run r
        left join public.company_event e on e.id = r.trigger_event_id
       where r.id = v_run;
      if coalesce(v_ctx, '{}'::jsonb) ? 'inquiry_id' then
        begin v_id := (v_ctx->>'inquiry_id')::uuid; exception when others then v_id := null; end;
      end if;
      if v_id is null and v_ev_type = 'inquiry' then
        begin v_id := v_ev_entity::uuid; exception when others then v_id := null; end;
      end if;
    end if;
  end if;

  if v_id is not null then
    select i.category into v_slug from public.inquiries i where i.id = v_id;
  end if;
  if v_slug is null and v_ev_payload is not null then v_slug := v_ev_payload->>'category'; end if;
  if v_slug is not null then
    v_key := public.fn_category_key_for_slug(v_slug);
    if v_key is not null then return v_key; end if;
  end if;

  -- 3. a category key written in its own format (NNN_slug), accepted only when it exists
  v_key := substring(p_text from '\m([0-9]{3}_[a-z0-9-]+)\M');
  if v_key is not null and exists (select 1 from public.org_category_identity where category_key = v_key) then
    return v_key;
  end if;
  return null;
end $fn$;
revoke execute on function public.fn_category_key_from_text(text) from public, anon, authenticated;
grant execute on function public.fn_category_key_from_text(text) to service_role;

-- ── 11. a held quote-quality verdict is not acceptable (#888 review) ─────────────────────────────
-- supplier_api's accept rule reads this score. A quote whose category aspects are not yet read by the
-- reasoning (quality.category.status = 'needs_reasoning') is NOT submittable, whatever its points: it is
-- held, and released by the replay (reasoned_delivery.ts -> supplier_api reasoned_quote_release).
create or replace function public.fn_quote_structured_score(p_quote text)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare n int; priced int; branded int; laboured int; spec_n int; q record; pts int:=0; miss text[]:='{}'; v_held boolean;
begin
  select count(*), count(*) filter (where unit_price is not null and unit_price>0),
         count(*) filter (where coalesce(brand,'')<>'' and coalesce(model,'')<>''),
         count(*) filter (where labour is not null or install is not null),
         count(*) filter (where coalesce(specification,'')<>'')
    into n, priced, branded, laboured, spec_n from public.quote_items where quote_id=p_quote;
  select * into q from public.quotes where id=p_quote::uuid;
  if n=0 then miss:=array_append(miss,'line_items');
  else pts:=pts+15; if priced=n then pts:=pts+20; else miss:=array_append(miss,'unit_prices_on_all_items'); end if; end if;
  if n>0 and branded=n then pts:=pts+15; else miss:=array_append(miss,'brand_model_per_item'); end if;
  if n>0 and spec_n>=greatest(1,n/2) then pts:=pts+10; else miss:=array_append(miss,'specifications'); end if;
  if laboured>0 then pts:=pts+10; else miss:=array_append(miss,'labour_or_installation'); end if;
  if coalesce(q.warranty,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'warranty'); end if;
  if coalesce(q.lead_time,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'lead_time'); end if;
  if coalesce(q.payment_terms,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'payment_terms'); end if;
  if coalesce(q.exclusions,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'exclusions'); end if;
  if coalesce(q.validity,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'validity'); end if;
  v_held := coalesce(q.quality->'category'->>'status', '') = 'needs_reasoning';
  if v_held then miss := array_append(miss, 'category_reading'); end if;
  return jsonb_build_object('score',pts,'submittable',pts>=70 and not v_held,'held_for_reading',v_held,
                            'items',n,'priced_items',priced,'missing',to_jsonb(miss),'scored_at',now());
end $fn$;
revoke execute on function public.fn_quote_structured_score(text) from public, anon, authenticated;
grant execute on function public.fn_quote_structured_score(text) to service_role;

-- ── 12. fn_os_catalog_test_gate: which aspects a sample states arrives reasoned ──────────────────
-- It tested a sample text against category_quote_specs.match_regex. The aspects a sample states are now
-- reasoned (reasoned_suppliers.ts aspectsStated, the same reading trg_quote_quality uses) and passed in.
-- Measured 23 Sep 2026: nothing in the repository or on production calls it; the old signature is dropped.
drop function if exists public.fn_os_catalog_test_gate(text, text);
create or replace function public.fn_os_catalog_test_gate(p_category text, p_present text[])
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare grp text; res jsonb;
begin
  grp := public.fn_quote_spec_group(p_category);
  with asp as (
    select q.aspect, q.label, q.mandatory, (q.aspect = any(coalesce(p_present, '{}'::text[]))) as matched
      from public.category_quote_specs q where q.spec_group = grp
  )
  select jsonb_build_object(
    'category', p_category, 'spec_group', grp, 'read_by', 'reasoning',
    'aspects', coalesce((select jsonb_agg(jsonb_build_object('aspect',aspect,'label',label,'mandatory',mandatory,'matched',matched) order by mandatory desc, aspect) from asp),'[]'::jsonb),
    'total', (select count(*) from asp),
    'matched_count', (select count(*) from asp where matched),
    'mandatory_missing', coalesce((select jsonb_agg(label order by label) from asp where mandatory and not matched),'[]'::jsonb),
    'passes', (select coalesce(bool_and(matched),true) from asp where mandatory)
  ) into res;
  return res;
end $fn$;
revoke execute on function public.fn_os_catalog_test_gate(text, text[]) from public, anon, authenticated;
grant execute on function public.fn_os_catalog_test_gate(text, text[]) to service_role;

-- ── 13. fn_org_task_consume_tick: the question's price trade and FAQ are a reasoned reading ──────
-- Its knowledge_gap branch matched the question against the price lexicon (through fn_price_guidance's old
-- signature) and against every public FAQ question by shared lexemes (75% both ways). Now the sales
-- engineer's reasoning (reasoned_suppliers.ts reasonOrgTaskQuestions, run by resilience_ping) chooses which
-- published trade price or which approved FAQ answers the question - or neither - and the tick reads that.
create table if not exists public.org_task_question_reading (
  task_id       bigint primary key,
  question_md5  text not null check (question_md5 ~ '^[0-9a-f]{32}$'),
  trade         text,
  faq_id        bigint,
  status        text not null check (status in ('reasoned', 'needs_reasoning')),
  held_id       bigint,
  reasoned_at   timestamptz,
  updated_at    timestamptz not null default now(),
  check (status = 'reasoned' or (trade is null and faq_id is null)),
  check (trade is null or faq_id is null)
);
alter table public.org_task_question_reading enable row level security;
drop policy if exists org_task_question_reading_service_role_only on public.org_task_question_reading;
create policy org_task_question_reading_service_role_only on public.org_task_question_reading
  as permissive for all to public using (false) with check (false);
revoke all on public.org_task_question_reading from anon, authenticated;
comment on table public.org_task_question_reading is
  'Which published trade price or approved public FAQ answers an org task''s QUESTION (or neither), reasoned by think(); fn_org_task_consume_tick reads it instead of lexeme overlap (founder_instruction 886-903).';

-- The knowledge_gap tasks whose question has no reading yet, with the trades we publish prices for.
-- The QUESTION: line is parsed as the task's own format (a labelled line we write), not for meaning.
create or replace function public.fn_org_task_questions_due(p_limit integer default 3)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object(
    'trades', (select coalesce(jsonb_agg(distinct pb.category order by pb.category), '[]'::jsonb) from public.price_benchmark pb),
    'questions', coalesce((select jsonb_agg(jsonb_build_object('task_id', t.id, 'question', t.q, 'question_md5', md5(t.q)) order by t.id)
      from (select u.* from (select o.id, nullif(btrim(coalesce(substring(o.detail from 'QUESTION: ([^\n]+)'), '')), '') q
                               from public.org_tasks o
                              where o.status = 'assigned' and o.action_class = 'knowledge_gap') u
             where u.q is not null
               and not exists (select 1 from public.org_task_question_reading x where x.task_id = u.id and x.question_md5 = md5(u.q))
             order by u.id
             limit greatest(1, least(coalesce(p_limit, 3), 10))) t), '[]'::jsonb))
$fn$;
revoke execute on function public.fn_org_task_questions_due(integer) from public, anon, authenticated;
grant execute on function public.fn_org_task_questions_due(integer) to service_role;

-- The approved public FAQs nearest a question BY MEANING (gte-small), offered to the reasoning as its
-- candidates. A nearest neighbour is always found, so this never answers: the reasoning may choose none.
create or replace function public.fn_org_task_question_candidates(p_embedding vector, p_k integer default 8)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'question', f.question) order by f.d), '[]'::jsonb)
    from (select f.id, f.question, f.embedding_gte <=> p_embedding as d
            from public.company_faq f
           where f.public and f.status = 'approved' and f.embedding_gte is not null
           order by f.embedding_gte <=> p_embedding
           limit greatest(1, least(coalesce(p_k, 8), 20))) f
$fn$;
revoke execute on function public.fn_org_task_question_candidates(vector, integer) from public, anon, authenticated;
grant execute on function public.fn_org_task_question_candidates(vector, integer) to service_role;

-- p_choice is the reasoning's own option id: 'price:<trade>', 'faq:<id>' or 'neither' (parsed as our format).
-- p_reasoned false = held (queued as p_held_id).
create or replace function public.fn_org_task_question_reading_record(p_task_id bigint, p_question_md5 text, p_choice text, p_reasoned boolean, p_held_id bigint default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_trade text; v_faq bigint; v_status text := case when p_reasoned then 'reasoned' else 'needs_reasoning' end;
begin
  if p_reasoned and left(p_choice, 6) = 'price:' then
    v_trade := substr(p_choice, 7);
    if not exists (select 1 from public.price_benchmark where category = v_trade) then
      raise exception 'not a published trade: %', v_trade using errcode = '22023';
    end if;
  elsif p_reasoned and left(p_choice, 4) = 'faq:' then
    v_faq := substr(p_choice, 5)::bigint;
    if not exists (select 1 from public.company_faq where id = v_faq and public and status = 'approved') then
      raise exception 'not an approved public faq: %', v_faq using errcode = '22023';
    end if;
  elsif p_reasoned and coalesce(p_choice, '') <> 'neither' then
    raise exception 'not an option: %', p_choice using errcode = '22023';
  end if;
  insert into public.org_task_question_reading as x (task_id, question_md5, trade, faq_id, status, held_id, reasoned_at, updated_at)
  values (p_task_id, p_question_md5, v_trade, v_faq, v_status, p_held_id, case when p_reasoned then now() end, now())
  on conflict (task_id) do update set question_md5 = excluded.question_md5, trade = excluded.trade, faq_id = excluded.faq_id,
    status = excluded.status, held_id = coalesce(excluded.held_id, x.held_id), reasoned_at = excluded.reasoned_at, updated_at = now()
  where not (excluded.status = 'needs_reasoning' and x.status = 'reasoned' and x.question_md5 = excluded.question_md5);
  return jsonb_build_object('task_id', p_task_id, 'status', v_status, 'trade', v_trade, 'faq_id', v_faq);
end $fn$;
revoke execute on function public.fn_org_task_question_reading_record(bigint, text, text, boolean, bigint) from public, anon, authenticated;
grant execute on function public.fn_org_task_question_reading_record(bigint, text, text, boolean, bigint) to service_role;

create or replace function public.fn_reason_apply_sql__fn_org_task_consume_tick(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if (r.subject->>'task_id') is null or (r.subject->>'question_md5') is null then return jsonb_build_object('skipped', 'no subject'); end if;
  if not exists (select 1 from public.org_tasks o where o.id = (r.subject->>'task_id')::bigint
                   and md5(nullif(btrim(coalesce(substring(o.detail from 'QUESTION: ([^\n]+)'), '')), '')) = r.subject->>'question_md5') then
    return jsonb_build_object('skipped', 'stale');
  end if;
  return public.fn_org_task_question_reading_record((r.subject->>'task_id')::bigint, r.subject->>'question_md5',
    coalesce(p_result->'decision'->>'choice', 'neither'), true, p_id);
end $fn$;
revoke execute on function public.fn_reason_apply_sql__fn_org_task_consume_tick(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_sql__fn_org_task_consume_tick(bigint, jsonb) to service_role;

create or replace function public.fn_org_task_consume_tick(p_limit integer DEFAULT 4, p_task_id bigint DEFAULT NULL::bigint, p_dry_run boolean DEFAULT false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
AS $fn$
declare
  r          record;
  v_q        text;
  v_pg       jsonb;
  v_best     record;
  v_deliv    text;
  v_reason   text;
  v_handler  text;
  v_basis    jsonb;
  v_close    jsonb;
  v_gap_id   bigint;
  v_gap_status text;
  v_exp      record;
  v_inq      uuid;
  v_inq_seen boolean;
  v_matches  int;
  v_vendor   text;
  v_amount   numeric;
  v_ccy      text;
  v_charged  date;
  v_back     interval;
  v_done     jsonb := '[]'::jsonb;
  v_left     jsonb := '[]'::jsonb;
  v_items    jsonb := '[]'::jsonb;
  v_settled  jsonb;
  v_seen     int := 0;
  v_refused  int := 0;
  v_raised   int := 0;
  v_t0       timestamptz := clock_timestamp();
  v_faq_id   bigint;
  v_faq_q    text;
  v_faq_a    text;
  v_lead     record;
  v_rev      record;
  v_agg      record;
  v_lic      text;
  v_decision text;
  v_tracked  boolean;
  v_read     record;
begin
  for r in
    select o.*
      from public.org_tasks o
     where o.status = 'assigned'
       and (p_task_id is null or o.id = p_task_id)
       and (p_task_id is not null
            or o.last_run_at is null
            or o.last_run_at < now() - make_interval(mins => (15 * power(2, least(o.attempts, 6)))::int)
            -- A BACK-OFF EARNED UNDER OTHER HANDLERS DOES NOT BIND THESE. Measured on apply,
            -- 21 Sep 2026: the first v2 tick scanned 0 of 8 assigned rows, because every one was
            -- inside a 4h/16h window earned from a v1 "not_yet" -- a verdict v2 no longer gives.
            -- A row whose last verdict came from an older consumer version is retried at once.
            or coalesce(o.result->'consumer'->>'version', '') <> 'v3')
     order by (o.last_run_at is null) desc, o.priority desc, o.id
     limit greatest(1, least(coalesce(p_limit, 4), 25))
     -- TWO TICKS MUST NOT PICK THE SAME ROW. The 15-minute cron can double-fire or retry, and a
     -- p_task_id replay can be issued by hand while a batch tick is in flight. Without this, both
     -- callers select the row under READ COMMITTED; the loser's fn_org_task_close_as_fact refuses
     -- (it guards on status='done') but its earlier result-merge update still lands on top of the
     -- winner's. skip locked rather than for update: a row another tick is already working is not
     -- this tick's work, and waiting on it would spend the budget queueing.
       for update of o skip locked
  loop
    v_seen   := v_seen + 1;
    v_deliv  := null;
    v_reason := null;
    v_basis  := '{}'::jsonb;
    v_gap_id := null;
    v_gap_status := null;
    v_handler := null;
    v_close  := null;
    v_tracked := false;

    -- ONE BAD ROW MUST NOT TAKE THE BATCH, AND MUST NOT TAKE THE FINDING. Everything from routing
    -- to the close runs inside this block, so a handler that raises -- a ::date cast on a captured
    -- "Date: 2026-13-45", a ::uuid cast on 36 hex characters with the dashes in the wrong places, a
    -- trigger refusing a close -- rolls back to the point this row was picked up instead of
    -- aborting fn_org_task_consume_tick. Without it, one poisoned row would undo every close
    -- already made in the same batch AND skip the per-class census at the end, so the tick would
    -- lose the finding that says the queue is stuck, stamp nothing, and re-select the same poisoned
    -- batch every 15 minutes with no forward progress and no explanation. The row itself is then
    -- stamped and parked on the queued path below, carrying SQLERRM as its reason.
    begin

    -- ── knowledge_gap ─────────────────────────────────────────────────────────────────────────
    if r.action_class = 'knowledge_gap' then
      v_q := nullif(btrim(coalesce(substring(r.detail from 'QUESTION: ([^\n]+)'), '')), '');

      -- THE GAP LEDGER IS THE WRITER'S OWN RECORD, SO READ IT FIRST. Measured 18 Sep 2026:
      -- sales_knowledge_gap #13 ("how much does it cost to charter a helicopter to the moon") has
      -- carried status='not_a_gap' since it was judged, while org_task 578944 stayed 'assigned'
      -- for nine days -- the founder's own rule, a status column is not a delivery record, showing
      -- up inside the very table that records the judgement. A question already judged out of
      -- scope has nothing left to answer, and the judgement is the fact the close cites.
      select g.id, g.status into v_gap_id, v_gap_status
        from public.sales_knowledge_gap g where g.task_id = r.id;

      if v_gap_status = 'not_a_gap' then
        v_handler := 'sales_knowledge_gap';
        v_deliv := 'ALREADY JUDGED. public.sales_knowledge_gap #' || v_gap_id || ', the record this '
          || 'task''s own detail points at, carries status = ''not_a_gap'': the question was reviewed '
          || 'and found not to be a gap in company knowledge.'
          || E'\n\nQUESTION: ' || coalesce(v_q, '(none recorded on the task)')
          || E'\n\nThere is nothing to answer and nothing to add to a corpus. The task stayed open '
          || 'only because the judgement was written to the gap ledger and never carried back to the '
          || 'queue -- which is the defect this consumer exists to end.';
        v_basis := jsonb_build_object('answered_by', 'sales_knowledge_gap',
                                      'sales_knowledge_gap_id', v_gap_id, 'gap_status', v_gap_status);

      elsif v_q is null then
        v_handler := 'none';
        v_reason  := 'the task carries no "QUESTION:" line, so there is nothing to ask again';

      else
        -- WHAT THE QUESTION ASKS IS A REASONED READING (org_task_question_reading, 23 Sep 2026,
        -- founder_instruction 886-903): which published trade's price, or which approved public FAQ,
        -- answers it -- chosen by the sales engineer's reasoning (reasoned_suppliers.ts
        -- reasonOrgTaskQuestions), never by the question's words against a lexicon or FAQ lexemes.
        -- Not read yet (the model hold): the row is parked with that reason and retried; nothing is guessed.
        select q.* into v_read from public.org_task_question_reading q
         where q.task_id = r.id and q.question_md5 = md5(v_q) and q.status = 'reasoned';
        if not found then
          v_handler := 'none';
          v_reason  := 'the question waits for the sales engineer''s reasoning (which published price or approved '
                    || 'FAQ answers it); nothing is matched by its words meanwhile';
        else
        -- 1. the price answerer, for the trade the reasoning chose
        v_pg := case when v_read.trade is not null then public.fn_price_guidance(v_read.trade, 6) end;

        if coalesce((v_pg->>'ok')::boolean, false) then
          v_handler := 'fn_price_guidance';
          v_deliv := 'ANSWERED TODAY by public.fn_price_guidance, the published-price answerer.'
            || E'\n\nQUESTION: ' || v_q
            || E'\n\nTRADE (reasoned by the sales engineer): ' || coalesce(v_pg->>'trade', '?') || ', '
            || coalesce(v_pg->>'band_count', '0') || ' published UAE bands for the trade as a whole.'
            || E'\n\nBANDS: ' || coalesce(v_pg->'bands', '[]'::jsonb)::text
            || E'\n\nThese are published guide ranges in AED, never a quotation: QuotesDone does not '
            || 'price the work, suppliers do.';
          v_basis := jsonb_build_object('answered_by', 'fn_price_guidance', 'price_guidance', v_pg, 'reading', 'org_task_question_reading');

        elsif coalesce(v_pg->>'reason', '') = 'trade_has_a_recorded_gap' then
          v_handler := 'fn_price_guidance';
          v_deliv := 'ANSWERED TODAY by public.fn_price_guidance: the company holds a DELIBERATE '
            || 'recorded gap for this trade, which is an answer and not a silence.'
            || E'\n\nQUESTION: ' || v_q
            || E'\n\nTRADE: ' || coalesce(v_pg->>'trade', '?')
            || E'\nRECORDED GAP: ' || coalesce(v_pg->>'gap_reason', '')
            || E'\n\nTHE ANSWER TO GIVE: QuotesDone publishes no price range for this trade. Say so '
            || 'plainly, never estimate one, and offer to put the job out to suppliers for real '
            || 'quotes. ' || coalesce(v_pg->>'note', '');
          v_basis := jsonb_build_object('answered_by', 'fn_price_guidance', 'price_guidance', v_pg);

        else
          -- 2. the approved public company_faq entry the reasoning chose, if any.
          v_faq_id := null;
          if v_read.faq_id is not null then
            select f.id, f.question, f.answer into v_faq_id, v_faq_q, v_faq_a
              from public.company_faq f where f.id = v_read.faq_id and f.public and f.status = 'approved';
          end if;

          -- 3. the corpus the writer named. Arabic-aware, read-only, public rows only.
          if v_faq_id is null then
            select s.src, s.src_id, s.title, s.content, s.citation, s.rank
              into v_best
              from public.fn_support_corpus_search(v_q, true, 3) s
             order by s.rank desc
             limit 1;
          end if;

          if v_faq_id is not null then
            v_handler := 'company_faq';
            v_deliv := 'ANSWERED TODAY by the approved public company_faq entry the sales engineer''s '
              || 'reasoning chose for this question (org_task_question_reading).'
              || E'\n\nQUESTION: ' || v_q
              || E'\n\nSOURCE: company_faq #' || v_faq_id || ' -- ' || v_faq_q
              || E'\n\nANSWER: ' || left(coalesce(v_faq_a, ''), 4000);
            v_basis := jsonb_build_object('answered_by', 'company_faq', 'company_faq_id', v_faq_id, 'reading', 'org_task_question_reading');

          elsif v_best.rank is not null and v_best.rank >= 1.5 then
            v_handler := 'fn_support_corpus_search';
            v_deliv := 'ANSWERED TODAY by public.fn_support_corpus_search over v_support_corpus '
              || '(company_faq + support_knowledge + ops_knowledge) -- the corpus this task names.'
              || E'\n\nQUESTION: ' || v_q
              || E'\n\nSOURCE: ' || v_best.src || ':' || v_best.src_id
              || ' -- ' || coalesce(v_best.citation, coalesce(v_best.title, ''))
              || ' (rank ' || round(v_best.rank::numeric, 3) || ', floor 1.5)'
              || E'\n\nANSWER: ' || left(coalesce(v_best.content, ''), 4000);
            v_basis := jsonb_build_object(
              'answered_by', 'fn_support_corpus_search',
              'src', v_best.src, 'src_id', v_best.src_id, 'rank', round(v_best.rank::numeric, 4));
          else
            -- 4. NOTHING ANSWERS: CLOSE AS A TRACKED GAP. Re-asking every few hours cannot create
            --    knowledge; it only kept a duplicate of the gap ledger in the queue and paged about
            --    it. The gap row IS the seat's record of the unanswered question (the writers bump
            --    its asks on every repeat and reuse this task), so the task ends by citing it and
            --    the row stays 'open' -- it is NOT marked knowledge_added.
            v_handler := 'sales_knowledge_gap';
            v_tracked := true;
            if v_gap_id is null and not p_dry_run then
              insert into public.sales_knowledge_gap (question_norm, question, refusal, nearest_corpus, task_id)
              values (lower(btrim(v_q)), v_q, 'consumer_tracked_gap', 'support_corpus', r.id)
              on conflict (question_norm) do nothing;
              select g.id, g.status into v_gap_id, v_gap_status
                from public.sales_knowledge_gap g where g.question_norm = lower(btrim(v_q));
            end if;
            v_deliv := 'NOT ANSWERED -- FILED AS A TRACKED KNOWLEDGE GAP. No corpus answers this today: '
              || 'the reasoning found no published trade price (' || coalesce(nullif(v_pg->>'reason', ''), 'no trade')
              || ') and no approved public company_faq entry that answers it, and the best '
              || 'company-knowledge hit ranked ' || coalesce(round(v_best.rank::numeric, 3)::text, 'nothing')
              || ' against a floor of 1.5.'
              || E'\n\nQUESTION: ' || v_q
              || E'\n\nTRACKED AT: public.sales_knowledge_gap #' || coalesce(v_gap_id::text, '(filed on the live run)')
              || ', status ' || coalesce(v_gap_status, 'open') || ', owned by the ' || coalesce(r.assigned_agent, '?')
              || ' seat. It stays open until the answer is written into company_faq or support_knowledge; '
              || 'this task closes because re-running the same search cannot produce that answer.';
            v_basis := jsonb_build_object('answered_by', 'none', 'outcome', 'tracked_gap',
                                          'sales_knowledge_gap_id', v_gap_id,
                                          'best_corpus_rank', round(v_best.rank::numeric, 4));
          end if;
        end if;
        end if;
      end if;

    -- ── routine_operational_decision ──────────────────────────────────────────────────────────
    elsif r.action_class = 'routine_operational_decision'
          and coalesce(r.result->'founder_mail'->>'kind', '') = 'expense_logged' then
      v_handler := 'expense_entries';
      v_vendor := btrim(coalesce(substring(r.title from '^Expense logged: (.+) [0-9.]+ [A-Za-z]{3}$'), ''));
      v_amount := nullif(coalesce(substring(r.title from '([0-9]+\.?[0-9]*) [A-Za-z]{3}$'), ''), '')::numeric;
      v_ccy    := upper(coalesce(substring(r.title from '([A-Za-z]{3})$'), ''));
      -- THE DATE IS PART OF THE IDENTITY, AND LEAVING IT OUT CITED THE WRONG RECEIPT. Measured in
      -- the rolled-back dry run of 18 Sep 2026: matching on vendor + amount + currency alone closed
      -- "Expense logged: GoDaddy 93.8 AED" (announced 10 Sep) on expense_entries #62 charged
      -- 10 AUGUST, and "Resend 20 USD" (15 Sep) on #52 charged 15 August -- because a monthly
      -- subscription bills the same vendor the same amount every month and the oldest row won.
      -- A close that cites the wrong month's receipt is worse than an open task. The announced date
      -- is in the task's own body and matched exactly on all four live rows, so it is required: no
      -- exact match means the row stays queued and says why, rather than closing on a near miss.
      v_charged := nullif(coalesce(substring(r.detail from 'Date: ([0-9]{4}-[0-9]{2}-[0-9]{2})'), ''), '')::date;

      select e.id, e.vendor, e.amount, e.currency, e.charged_on, e.source, e.category, e.doc_path
        into v_exp
        from public.expense_entries e
       where e.vendor = v_vendor and e.amount = v_amount and upper(e.currency) = v_ccy
         and v_charged is not null and e.charged_on = v_charged
       order by e.id
       limit 1;

      if found then
        v_deliv := 'ALREADY DONE BEFORE THIS TASK EXISTED. The expense is booked: '
          || 'public.expense_entries #' || v_exp.id || ' -- ' || v_exp.vendor || ' '
          || v_exp.amount || ' ' || v_exp.currency || ' charged on ' || v_exp.charged_on
          || ', category ' || coalesce(v_exp.category, '(none)') || ', source ' || coalesce(v_exp.source, '?')
          || ', document ' || coalesce(v_exp.doc_path, '(none -- founder-reported)') || '.'
          || E'\n\nsupabase/functions/resend_inbound books the entry and posts it to the general '
          || 'ledger through fn_expense_post_to_gl at intake, and only THEN requests the notification '
          || 'that became this task. The task''s own words are "a booked expense is a record, not a '
          || 'decision": the record exists, so the condition it was raised for is resolved and there '
          || 'was never a decision to take.'
          || case when coalesce((r.result->'founder_mail'->>'seen_count')::int, 1) > 1
                  then E'\n\nThis signal recurred ' || (r.result->'founder_mail'->>'seen_count')
                       || ' times; each recurrence is its own booked entry.'
                  else '' end;
        v_basis := jsonb_build_object('answered_by', 'expense_entries', 'expense_entry_id', v_exp.id,
                                      'vendor', v_exp.vendor, 'amount', v_exp.amount, 'currency', v_exp.currency);
      else
        v_reason := 'no row in public.expense_entries matches ' || coalesce(v_vendor, '?') || ' '
          || coalesce(v_amount::text, '?') || ' ' || coalesce(v_ccy, '?') || ' charged on '
          || coalesce(v_charged::text, '(the task carries no "Date:" line)')
          || '. Either the receipt was announced and never booked -- which is the accountant''s duty '
          || 'failing rather than a task waiting -- or the booked entry carries a different date. Do '
          || 'NOT close this until the exact entry exists: a monthly subscription bills the same '
          || 'vendor the same amount every month, so vendor and amount alone identify nothing.';
      end if;

    elsif r.action_class = 'routine_operational_decision'
          and coalesce(r.result->'founder_mail'->>'kind', '') = 'rfq_no_supplier' then
      v_handler := 'inquiries + inquiry_matches';
      v_inq := nullif(coalesce(substring(r.detail from 'Inquiry: ([0-9a-fA-F-]{36})'), ''), '')::uuid;

      if v_inq is null then
        v_reason := 'the task names no inquiry id, so the claim "the customer is waiting" cannot be checked';
      else
        select true into v_inq_seen from public.inquiries i where i.id = v_inq;
        v_inq_seen := coalesce(v_inq_seen, false);
        select count(*) into v_matches from public.inquiry_matches m where m.inquiry_id = v_inq;

        if not v_inq_seen then
          v_deliv := 'THE CONDITION IS GONE. This task was raised because inquiry ' || v_inq
            || ' matched zero suppliers and a customer was waiting. That inquiry no longer exists in '
            || 'public.inquiries, so there is no customer waiting on it and nothing to route.'
            || E'\n\nThe underlying supply-coverage gap is NOT closed by this and is not claimed to '
            || 'be: it remains recorded in public.agent_actions under kind=''coverage_gap'', which is '
            || 'where a coverage decision belongs. What closes here is this signal, which named a '
            || 'request that is no longer live.';
          v_basis := jsonb_build_object('answered_by', 'inquiries', 'inquiry_id', v_inq, 'inquiry_present', false);
        elsif v_matches > 0 then
          v_deliv := 'THE CONDITION IS GONE. Inquiry ' || v_inq || ' now has ' || v_matches
            || ' row(s) in public.inquiry_matches, so it no longer matches zero suppliers and the '
            || 'signal this task carries is out of date.';
          v_basis := jsonb_build_object('answered_by', 'inquiry_matches', 'inquiry_id', v_inq, 'matches', v_matches);
        else
          v_reason := 'inquiry ' || v_inq || ' is still live and still matches zero suppliers. There is '
            || 'NO handler for this and this tick will not invent one: onboarding or contacting '
            || 'suppliers in a trade and emirate is a commercial act, fn_supply_gap_scan was dropped '
            || 'on 7 Sep 2026, and no live routine owns supply coverage. It stays queued for the ceo '
            || 'seat, and the class carries a finding saying exactly this.';
        end if;
      end if;

    -- ── routine_operational_decision / supplier_registered (fn_founder_mail_route) ─────────────
    -- The task announces a decision already taken ("... No action needed; this is a record."). The
    -- decider checks the record against public.leads and closes on it.
    --
    -- 21 SEP 2026 — THE LICENCE IS NOT PART OF THE ANNOUNCEMENT'S IDENTITY. Measured on
    -- production (the project ref used to be spelled here; it made the schema export unportable, and a
    -- routine body is not the place to name one database — 23 Sep 2026): org_tasks 579041 and 579076
    -- stayed 'assigned' and re-raised
    -- duty:org_task_queue:routine_operational_decision:sales_engineer to the founder because v2
    -- required a "Licence X," line, and supplier_api/index.ts writes that line only when the lead has
    -- a trade_license_no (its licInfo is '' otherwise). Both announcements named ZZ DEMO registration
    -- walks whose leads the walk had already deleted, and 579076 announced 'action_required' (the
    -- terms certificate on its way) -- a record, not a pending decision, which v2 also refused as
    -- "the register disagrees". Now: the name identifies the lead (the licence narrows it when the
    -- announcement carries one); a removed ZZ DEMO fixture is a condition that is gone; only a
    -- 'pending' announcement still waiting on the seat stays queued, because that one IS a decision.
    elsif r.action_class = 'routine_operational_decision'
          and coalesce(r.result->'founder_mail'->>'kind', '') = 'supplier_registered' then
      v_handler  := 'leads';
      v_vendor   := substring(r.detail from 'New supplier "([^"]+)"');
      v_lic      := nullif(btrim(substring(r.detail from 'Licence ([^,]+),')), '');
      v_decision := lower(substring(r.detail from 'Decision: ([A-Za-z_]+)'));

      select count(*)::int into v_matches
        from public.leads l
       where l.company_name = v_vendor and (v_lic is null or l.trade_license_no = v_lic);

      select l.id, l.company_name, l.trade_license_no, l.approval_status, l.approval_decided_by,
             l.approved_at, coalesce(l.banned, false) as banned, l.license_expiry, l.is_demo
        into v_lead
        from public.leads l
       where l.company_name = v_vendor and (v_lic is null or l.trade_license_no = v_lic)
       order by l.id desc limit 1;

      if v_vendor is null or v_decision is null then
        v_reason := 'the task does not carry the supplier name and decision in the form '
          || 'supplier_api writes them ("New supplier \"<name>\" ... Decision: <status>"), so the '
          || 'record cannot be checked';
      elsif v_matches = 0 and v_vendor ~ '^ZZ DEMO' then
        v_deliv := 'THE CONDITION IS GONE. The task announced the ZZ DEMO fixture supplier "' || v_vendor
          || '" as ' || v_decision || '. public.leads no longer holds it: the rehearsal that registered '
          || 'it removed its own fixture, so there is no supplier to welcome and no record to reconcile.';
        v_basis := jsonb_build_object('answered_by', 'leads', 'lead_present', false, 'fixture', true,
                                      'announced', v_decision);
      elsif v_matches = 0 then
        v_reason := 'no public.leads row is named "' || v_vendor || '"'
          || coalesce(' with licence ' || v_lic, '')
          || ': the announcement names a supplier the register does not hold';
      elsif v_matches > 1 then
        v_reason := v_matches || ' public.leads rows are named "' || v_vendor || '" and the announcement '
          || 'carries no licence to tell them apart; the seat identifies which one registered';
      elsif v_lead.banned then
        v_reason := 'leads #' || v_lead.id || ' is BANNED while the task announced "' || v_decision
          || '". That is the seat''s to reconcile.';
      elsif v_decision = 'pending' and coalesce(v_lead.approval_status, 'pending') = 'pending' then
        v_reason := 'leads #' || v_lead.id || ' is still pending: auto-approve is off and the approval '
          || 'is the ' || coalesce(r.assigned_agent, '?') || ' seat''s decision, not a record';
      elsif v_decision = 'approved' and v_lead.approval_status is distinct from 'approved' then
        v_reason := 'the register disagrees with the announcement: leads #' || v_lead.id
          || ' has approval_status ' || coalesce(v_lead.approval_status, 'null')
          || ' while the task announced "approved". That is the seat''s to reconcile.';
      else
        v_deliv := 'RECORD CONFIRMED -- NO DECISION WAS PENDING. The task announced supplier "'
          || v_vendor || '"' || coalesce(' (licence ' || v_lic || ')', '') || ' as ' || v_decision
          || '. public.leads #' || v_lead.id || ' holds it: approval_status '
          || coalesce(v_lead.approval_status, 'null') || coalesce(' by ' || v_lead.approval_decided_by, '')
          || coalesce(' at ' || v_lead.approved_at::text, '')
          || ', licence ' || coalesce(v_lead.trade_license_no, '(none recorded)')
          || coalesce(' expiring ' || v_lead.license_expiry::text, '') || ', not banned.'
          || E'\n\nThe task''s own words are "No action needed; this is a record": the record exists, '
          || 'so it closes on that fact. What the supplier still owes is on its own registration '
          || 'email and portal, not on this seat.';
        v_basis := jsonb_build_object('answered_by', 'leads', 'lead_id', v_lead.id, 'announced', v_decision,
                                      'approval_status', v_lead.approval_status, 'is_demo', v_lead.is_demo);
      end if;

    -- ── routine_operational_decision / sales_rating (the rating trigger's task) ────────────────
    -- The judgement asked: does this rating change the supplier's standing, capability or
    -- eligibility? Deterministic rule: a rating of 3-5 changes none of them (the aggregate already
    -- carries it). A rating of 1-2 is a standing judgement with no written policy, so it stays
    -- queued with that reason rather than having a suspension rule invented here.
    elsif r.action_class = 'routine_operational_decision' and r.result ? 'sales_rating' then
      v_handler := 'reviews + leads';
      select rv.id, rv.rating, rv.supplier_id into v_rev
        from public.reviews rv
       where rv.id = nullif(r.result->'sales_rating'->>'review_id', '')::bigint;

      if not found then
        v_deliv := 'THE CONDITION IS GONE. Review #' || coalesce(r.result->'sales_rating'->>'review_id', '?')
          || ' no longer exists in public.reviews, so there is no rating left to incorporate into the '
          || 'supplier record.';
        v_basis := jsonb_build_object('answered_by', 'reviews', 'review_present', false);
      else
        select round(avg(x.rating)::numeric, 2) as avg_rating, count(*)::int as n
          into v_agg from public.reviews x where x.supplier_id = v_rev.supplier_id;
        select l.id, l.company_name, l.app_rating, l.app_reviews into v_lead
          from public.leads l where l.id = v_rev.supplier_id;

        if not found then
          v_reason := 'review #' || v_rev.id || ' names supplier ' || v_rev.supplier_id
            || ' and public.leads has no such row';
        elsif v_lead.app_rating is distinct from v_agg.avg_rating
              or v_lead.app_reviews is distinct from v_agg.n then
          v_reason := 'the supplier aggregate is stale: leads #' || v_lead.id || ' shows '
            || coalesce(v_lead.app_rating::text, 'null') || ' over ' || coalesce(v_lead.app_reviews::text, 'null')
            || ' review(s) but public.reviews holds ' || coalesce(v_agg.avg_rating::text, 'null') || ' over '
            || v_agg.n || '. recompute_supplier_rating did not run, which is a defect, not a decision.';
        elsif v_rev.rating >= 3 then
          v_deliv := 'DECIDED: NO CHANGE TO STANDING, CAPABILITY OR ELIGIBILITY. Review #' || v_rev.id
            || ' rates ' || v_lead.company_name || ' ' || v_rev.rating || '/5. The supplier aggregate '
            || 'already carries it (' || v_lead.app_rating || ' over ' || v_lead.app_reviews
            || ' review(s), equal to public.reviews). Rule applied: a rating of 3 to 5 does not change a '
            || 'supplier''s standing, declared capability or trade eligibility; only a rating of 1 or 2 '
            || 'is held for the seat''s judgement.';
          v_basis := jsonb_build_object('answered_by', 'reviews', 'review_id', v_rev.id,
                                        'rating', v_rev.rating, 'supplier_id', v_rev.supplier_id,
                                        'app_rating', v_lead.app_rating, 'app_reviews', v_lead.app_reviews,
                                        'rule', 'rating >= 3 => no change to standing');
        else
          v_reason := 'review #' || v_rev.id || ' rates the supplier ' || v_rev.rating || '/5. A rating '
            || 'of 1 or 2 may change the supplier''s standing and no written policy decides that, so it '
            || 'stays with the ' || coalesce(r.assigned_agent, '?') || ' seat.';
        end if;
      end if;

    else
      v_handler := 'none';
      v_reason  := 'no handler is mapped for action_class ' || coalesce(r.action_class, '(null)')
        || ' on seat ' || coalesce(r.assigned_agent, '(unassigned)')
        || '. Mapping one is a deliberate act, not a default.';
    end if;

    ------------------------------------------------------------------------------------------
    -- SETTLE THE ROW
    ------------------------------------------------------------------------------------------
      if v_deliv is not null and not p_dry_run then
        -- z50_task_close_needs_an_act refuses a close on a requires_evidence task whose result
        -- records facts but no act. Flipping the knowledge gap and citing the source IS the act,
        -- and it is written before the close so fn_org_task_close_as_fact merges onto it.
        update public.org_tasks
           set result = coalesce(result, '{}'::jsonb) || jsonb_build_object(
                 'change_made', jsonb_build_object(
                   'what', 'the condition this task was raised for was re-checked against the handler '
                           || 'the writer named, and it is resolved',
                   'handler', v_handler, 'basis', v_basis, 'at', now()))
         where id = r.id;

        v_close := public.fn_org_task_close_as_fact(r.id, 'fn_org_task_consume_tick', v_deliv,
                     v_basis || jsonb_build_object('owner', r.assigned_agent, 'handler', v_handler));

        -- A REFUSAL IS RETURNED, NOT RAISED, AND IT IS NOT A CLOSE. fn_org_task_close_as_fact
        -- answers {ok:false, reason} when the task is already done, the resolver is unnamed or the
        -- deliverable is too short. Flipping the gap ledger on that return would mark a customer's
        -- question knowledge_added while the task never left 'assigned' -- the exact shape of "a
        -- status column is not a delivery record", and worse: the refusal paths return before
        -- stamping last_run_at, so the row would keep sorting first on every tick and re-run the
        -- search forever behind a ledger already claiming success. So the refusal becomes the
        -- reason and the row falls through to the queued path, where it is stamped and backs off.
        if coalesce((v_close->>'ok')::boolean, false) then
          -- what both writers asked for in words, done in one place at last
          -- (a tracked-gap close answered nothing, so its gap row stays 'open')
          if r.action_class = 'knowledge_gap' and not v_tracked then
            update public.sales_knowledge_gap
               set status = 'knowledge_added', closed_at = now()
             where task_id = r.id and status = 'open'
            returning id into v_gap_id;
          end if;
        else
          v_reason := 'fn_org_task_close_as_fact REFUSED this close: '
            || coalesce(nullif(btrim(v_close->>'reason'), ''), '(no reason given)')
            || '. The handler had an answer and the close path rejected it, so nothing is recorded '
            || 'as delivered and the row backs off instead.';
          v_deliv  := null;
          v_refused := v_refused + 1;
        end if;
      end if;

    exception when others then
      v_deliv  := null;
      v_close  := null;
      v_reason := 'the handler RAISED and this row was rolled back to the point it was picked up: '
        || sqlerrm || ' (SQLSTATE ' || sqlstate || '). The rest of this batch and the per-class '
        || 'finding are unaffected; this row is stamped and backs off so the failure is visible '
        || 'rather than repeating every 15 minutes.';
      v_raised := v_raised + 1;
    end;

    v_back := make_interval(mins => (15 * power(2, least(r.attempts + 1, 6)))::int);

    if v_deliv is not null then
      if p_dry_run then
        v_done := v_done || jsonb_build_object('id', r.id, 'class', r.action_class, 'seat', r.assigned_agent,
                    'handler', v_handler, 'would', 'close', 'basis', v_basis, 'deliverable', left(v_deliv, 1200));
      else
        v_done := v_done || jsonb_build_object('id', r.id, 'class', r.action_class, 'seat', r.assigned_agent,
                    'handler', v_handler, 'closed', true,
                    'close', v_close, 'sales_knowledge_gap', v_gap_id);
      end if;

    else
      if p_dry_run then
        v_left := v_left || jsonb_build_object('id', r.id, 'class', r.action_class, 'seat', r.assigned_agent,
                    'handler', v_handler, 'would', 'stay queued', 'reason', v_reason,
                    'attempts_would_be', r.attempts + 1, 'next_attempt_after', now() + v_back);
      else
        update public.org_tasks
           set last_run_at = now(),
               attempts    = coalesce(attempts, 0) + 1,
               updated_at  = now(),
               result      = coalesce(result, '{}'::jsonb) || jsonb_build_object(
                 'consumer', jsonb_build_object(
                   'at', now(), 'version', 'v3', 'handler', v_handler, 'verdict', 'not_yet', 'reason', v_reason,
                   'attempts', coalesce(r.attempts, 0) + 1, 'next_attempt_after', now() + v_back))
         where id = r.id;

        v_left := v_left || jsonb_build_object('id', r.id, 'class', r.action_class, 'seat', r.assigned_agent,
                    'handler', v_handler, 'reason', v_reason, 'attempts', r.attempts + 1,
                    'next_attempt_after', now() + v_back);
      end if;
    end if;
  end loop;

  ------------------------------------------------------------------------------------------------
  -- ONE FINDING PER CLASS, OVER THE WHOLE TABLE. Not one per row, not one per tick.
  ------------------------------------------------------------------------------------------------
  if p_task_id is null and not p_dry_run then
    select coalesce(jsonb_agg(jsonb_build_object(
             'item',  x.action_class || ':' || x.seat,
             'title', x.n || ' org_task(s) of class ' || x.action_class || ' are queued on the '
                      || x.seat || ' seat and the consumer cannot finish them; the oldest has waited '
                      || x.age_days || ' day(s)',
             'owner_seat', x.seat,
             'subject', 'org_tasks',
             'blast',  'agent_facing',
             'affected', x.n,
             -- A STANDING GAP, NOT A FRESH FAILURE EVERY FIFTEEN MINUTES. This is the convention
             -- #744 added on 18 Sep 2026 after duty:renewal:...:date_unknown was re-raised 320
             -- times in four days: fn_it_duty_settle holds an already-open finding carrying
             -- 'config' => true, refreshing its title and evidence to today's reading while
             -- seen_count, last_seen_at and started_at stand still. That is exactly this subject.
             -- Nothing about the running system changes between two ticks over the same queue;
             -- what is missing is knowledge nobody has written or a supplier nobody has onboarded.
             -- Without the flag this finding's seen_count would climb 96 times a day and bury
             -- every finding that did move. A CLOSED one still reopens, because a class that
             -- emptied and came back IS news.
             'config', true,
             'evidence', jsonb_build_object(
               'ids', x.ids, 'oldest_created_at', x.oldest, 'max_attempts', x.max_attempts,
               'last_reason', x.reason,
               'look_at', 'select id, title, result->''consumer'' from public.org_tasks where status = ''assigned'''))), '[]'::jsonb)
      into v_items
      from (
        select o.action_class,
               coalesce(o.assigned_agent, 'unassigned')          as seat,
               count(*)::int                                     as n,
               array_agg(o.id order by o.id)                     as ids,
               min(o.created_at)                                 as oldest,
               (extract(epoch from (now() - min(o.created_at))) / 86400)::int as age_days,
               max(o.attempts)                                   as max_attempts,
               max(o.result->'consumer'->>'reason')              as reason
          from public.org_tasks o
         where o.status = 'assigned'
         group by 1, 2
      ) x;

    v_settled := public.fn_it_duty_settle('org_task_queue', v_items);
  end if;

  -- THE STEP RUNNER ONLY COUNTS {ok:false, error:'<string>'} AS A FAILURE (resilience_ping/steps.ts,
  -- failureOf). A hardcoded ok:true would mean a refused close or a raising handler never reaches
  -- settleFailures and never becomes duty:heartbeat:orgtasks -- a broken consumer reporting health.
  -- So a tick that could not finish what it started says so in the shape the runner reads.
  return jsonb_build_object(
    'ok', (v_refused + v_raised) = 0,
    'error', case when (v_refused + v_raised) > 0
                  then v_refused || ' close(s) refused and ' || v_raised || ' handler(s) raised; '
                       || 'see result->''consumer''->>''reason'' on the rows still at status=''assigned'''
                  else null end,
    'refused', v_refused,
    'raised', v_raised,
    'dry_run', p_dry_run,
    'scanned', v_seen,
    'closed', jsonb_array_length(v_done),
    'still_queued', jsonb_array_length(v_left),
    'done', v_done,
    'queued', v_left,
    'findings', v_settled,
    'ms', round(extract(epoch from (clock_timestamp() - v_t0)) * 1000));
end
$fn$;
revoke execute on function public.fn_org_task_consume_tick(integer, bigint, boolean) from public, anon, authenticated;
grant execute on function public.fn_org_task_consume_tick(integer, bigint, boolean) to service_role;

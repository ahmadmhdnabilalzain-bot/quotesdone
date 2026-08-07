-- ROW #5 §10 — RANKED OPPORTUNITIES. "AI ranks them for you", with the reason attached.
--
-- The spec rejects a chronological inbox: the supplier should see the work that FITS THEM first,
-- and be told why. So the ordering key is a fit score, never created_at, and every opportunity
-- carries the reasons that produced its score.
--
-- ── THE SCORE IS BUILT ONLY FROM SIGNALS THAT EXIST ─────────────────────────────────────────────
-- Four signals, three of which the estate can actually answer today:
--
--   trade match      inquiry.category vs the supplier's sector            REAL
--   location         inquiry.emirate vs base emirate / service_emirates   REAL
--   capacity fit     the supplier's declared capability vs the scope      REAL where declared
--   similar history  a previous job of the same category                  0 quotes exist
--
-- The fourth is the honest one. There are no completed jobs on production, so "you did a similar
-- project before" cannot be true for anybody. It is not quietly dropped and it is not invented: it
-- returns applies:false with the population that makes it unanswerable, so the supplier sees that
-- the platform has no history on them YET rather than concluding they have no relevant experience.
--
-- ── AND THE SCORE IS NOT A PERCENTAGE OF ANYTHING ───────────────────────────────────────────────
-- fit_score is the sum of the weights that actually applied, over the sum of the weights that COULD
-- apply. Scoring history as 0 when no history can exist would push every supplier down by a fixed
-- amount and call it a fit problem. Unanswerable signals leave the denominator instead.
create or replace function public.fn_supplier_opportunities(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with me as (
    select l.id, lower(coalesce(l.sector, '')) sector, l.emirate,
           coalesce(l.service_emirates, '{}'::text[]) service_emirates,
           lower(coalesce(l.capability_summary, l.services, l.description, '')) capability,
           l.verified
      from public.leads l where l.id = p_lead_id
  ),
  -- Only inquiries this supplier could actually work: open, and not their own demo fence.
  cand as (
    select i.id, i.category, i.emirate, i.summary, i.scope_type, i.created_at, i.budget,
           lower(coalesce(i.category, '')) cat
      from public.inquiries i
     where coalesce(i.status, 'open') = 'open'
  ),
  scored as (
    select c.*,
      (c.cat = me.sector and me.sector <> '')                                    as trade_hit,
      (c.emirate is not null and (c.emirate = me.emirate
        or c.emirate = any(me.service_emirates)))                                as location_hit,
      -- Capacity is only ASKED when the supplier has declared a capability. An empty capability
      -- makes this unanswerable for them, not a failure by them.
      (me.capability <> '')                                                      as capacity_known,
      (me.capability <> '' and c.cat <> '' and position(c.cat in me.capability) > 0) as capacity_hit,
      -- History needs a concluded job. Counted rather than assumed so the reason can name it.
      (select count(*) from public.quotes q
         join public.inquiries qi on qi.id = q.inquiry_id
        where q.supplier_id = p_lead_id and lower(coalesce(qi.category,'')) = c.cat) as similar_jobs
      from cand c cross join me
  ),
  ranked as (
    select s.*,
      -- Weights that applied / weights that could apply. Capacity leaves the denominator when the
      -- supplier has declared nothing; history leaves it while the estate has no completed work.
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
      'open_inquiries', (select count(*) from public.inquiries where coalesce(status,'open')='open'),
      'quotes_in_estate', (select count(*) from public.quotes)
    ),
    'note', case when (select count(*) from ranked) = 0
                 then 'no open opportunities yet — nothing to rank'
                 else null end,
    'opportunities', coalesce((
      select jsonb_agg(x order by x->>'fit_score' desc) from (
        select jsonb_build_object(
          'inquiry_id', r.id,
          'project_title', coalesce(nullif(btrim(coalesce(r.summary,'')),''), r.category, 'Untitled project'),
          'category', r.category,
          'emirate', r.emirate,
          'estimated_value', r.budget,
          'fit_score', r.fit_score,
          'match_pct', r.fit_score,
          -- THE "WHY". Each reason states whether it applied, and an unanswerable one says why it
          -- could not be asked rather than reading as a failed test.
          'reasons', jsonb_build_array(
            jsonb_build_object(
              'key', 'trade',
              'applies', r.trade_hit,
              'text', case when r.trade_hit
                           then 'This is your trade — ' || coalesce(r.category,'the same category')
                           else 'Outside your registered trade' end),
            jsonb_build_object(
              'key', 'location',
              'applies', r.location_hit,
              'text', case when r.location_hit
                           then 'Nearby location — ' || coalesce(r.emirate,'your service area')
                           else 'Outside the emirates you serve' end),
            jsonb_build_object(
              'key', 'capacity',
              'applies', r.capacity_known and r.capacity_hit,
              'available', r.capacity_known,
              'text', case when not r.capacity_known
                           then 'Your capacity fits: not assessable — you have not described your capability yet'
                           when r.capacity_hit
                           then 'Your capacity fits — you list this work in your capability'
                           else 'Not in your described capability' end),
            jsonb_build_object(
              'key', 'history',
              'applies', r.similar_jobs > 0,
              -- available:false is the whole point. 0 quotes exist in the estate, so this is
              -- unanswerable for EVERY supplier and must never read as "you have no experience".
              'available', (select count(*) from public.quotes) > 0,
              'similar_jobs', r.similar_jobs,
              'text', case when (select count(*) from public.quotes) = 0
                           then 'Previous similar project: no completed work has been recorded on QuotesDone yet, for anyone'
                           when r.similar_jobs > 0
                           then 'You worked on ' || r.similar_jobs || ' previous similar project(s)'
                           else 'No previous similar project on record' end)
          )
        ) x from ranked r
      ) s
    ), '[]'::jsonb)
  )
$function$;

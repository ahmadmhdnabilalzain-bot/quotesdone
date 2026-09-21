-- THE SUPPLIER RANKING READS THE SUPPLIER'S REAL QUOTES, NOT A CACHE THAT STOPPED IN AUGUST
-- (21 Sep 2026, sales_engineer).
--
-- MEASURED, on production, before anything here was written:
--   * public.supplier_score: 20,465 rows, last computed_at 2026-08-16 03:40 UTC. public.leads: 22,266.
--     1,801 leads have NO score row at all (the refresh has not run since 16 Aug).
--   * public.quotes: 1 supplier has quoted (2 quotes, status 'submitted', a ZZ DEMO fixture). That
--     supplier has no supplier_score row, so fn_supplier_tier returned tier 'unranked', available
--     false, basis "no quote has been submitted yet" — while its two quotes sat in public.quotes.
--   * public.reviews: 0 rows. inquiries.hired_supplier_id set: 0. So nobody is silver yet either.
--
-- WHAT WAS WRONG. fn_supplier_tier took quotes_submitted / quotes_won / quality_rating from
-- public.supplier_score, a table fn_supplier_score_refresh rebuilds on a cron that last ran on
-- 16 Aug 2026. A supplier the refresh never saw reads as a supplier who never quoted, and the panel
-- tells them so in words. The Insights "company ranking" card on every self-registered supplier's
-- portal was therefore a false statement about their own activity.
--
-- WHAT THIS CHANGES. The routine now counts the supplier's quotes from public.quotes directly,
-- counts wins from the same two sources fn_supplier_score_refresh and customer_api use
-- (quotes.status = 'won', or an inquiry the customer completed with hired_supplier_id = this
-- supplier), and takes the quality rating from public.reviews for a verified supplier (founder
-- ruling 2026-08-08: a rating is earned on the platform, never scraped). response_rate still comes
-- from leads.rv_response_rate. No cache sits between a supplier's action and their own panel.
--   Also: every string the panel shows a supplier now has an Arabic twin (basis_ar, needs_ar);
--   SupplierTier.tsx picks by language. The English strings are unchanged.
--
-- WHAT THIS DOES NOT CHANGE. Thresholds (bronze on the first quote; silver 1 win; gold 5 wins and
-- 70; platinum 10 wins and 85) are the same. The tier still never affects matching (founder,
-- 2026-08-08: "a tier shouldnt effect a match"). supplier_score itself and its refresh are not
-- touched — other readers still use it; this routine simply no longer depends on it.
--
-- PROOF is the verdict row at the end: the routine is called for the one quoting supplier and for a
-- lead with no quotes, and the result set states PROBE OK / PROBE FAILED. Nothing is written.

create or replace function public.fn_supplier_tier(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with l as (
    select coalesce(verified, false) verified, rv_response_rate
      from public.leads where id = p_lead_id
  ),
  q as (
    select count(*)::int submitted,
           count(*) filter (where status = 'won')::int won_by_status
      from public.quotes where supplier_id = p_lead_id
  ),
  h as (
    select count(*)::int hired from public.inquiries where hired_supplier_id = p_lead_id
  ),
  s as (
    select (select submitted from q) submitted,
           greatest((select won_by_status from q), (select hired from h)) won,
           (select rv_response_rate from l) response_rate,
           -- NULL until a verified supplier has been reviewed: an unrated supplier is unrated.
           case when (select verified from l)
                then (select round(avg(rating)::numeric * 20, 1) from public.reviews where supplier_id = p_lead_id)
                else null end quality_rating
  ),
  -- ACTIVITY IS THE GATE. A supplier who has never quoted has no performance to measure.
  a as (select coalesce((select submitted from s), 0) > 0 active),
  t as (
    select case
      when not (select active from a) then 'unranked'
      when (select won from s) >= 10 and coalesce((select quality_rating from s), 0) >= 85 then 'platinum'
      when (select won from s) >= 5  and coalesce((select quality_rating from s), 0) >= 70 then 'gold'
      when (select won from s) >= 1                                                        then 'silver'
      else 'bronze'
    end tier
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'tier', (select tier from t),
    -- available:false is the difference between "we ranked you low" and "we cannot rank you yet".
    'available', (select active from a),
    'basis', case when (select active from a)
                  then 'quotes won and quality rating, from your quotes and reviews on QuotesDone'
                  else 'no quote has been submitted yet, so there is nothing to rank — this is not a low score' end,
    'basis_ar', case when (select active from a)
                  then 'الأعمال الفائزة وتقييم الجودة، من عروضك وتقييماتك على QuotesDone'
                  else 'لم يُقدَّم أي عرض سعر بعد، فلا يوجد ما يُصنَّف — هذه ليست درجة منخفضة' end,
    'ladder', jsonb_build_array(
      jsonb_build_object('tier','bronze',  'needs','submit your first quote',                              'needs_ar','قدّم عرض السعر الأول'),
      jsonb_build_object('tier','silver',  'needs','win 1 job',                                            'needs_ar','افز بعمل واحد'),
      jsonb_build_object('tier','gold',    'needs','win 5 jobs and hold a 70% quality rating',             'needs_ar','افز بخمسة أعمال وحافظ على تقييم جودة 70%'),
      jsonb_build_object('tier','platinum','needs','win 10 jobs and hold an 85% quality rating',           'needs_ar','افز بعشرة أعمال وحافظ على تقييم جودة 85%')
    ),
    'progress', jsonb_build_object(
      'quotes_submitted', (select submitted from s),
      'quotes_won', (select won from s),
      'quality_rating', (select quality_rating from s),
      'response_rate', (select response_rate from s)
    ),
    -- THE TIER DOES NOT AFFECT MATCHING. Founder, 2026-08-08: "a tier shouldnt effect a match."
    'benefits_active', false,
    'affects_matching', false,
    'benefits_note', 'Your tier never affects which work you are matched to, how you rank in search, '
      || 'or whether you are shown as preferred. Every supplier is matched on fit alone. '
      || 'This is a record of your track record, not a queue position.',
    'benefits_note_ar', 'تصنيفك لا يؤثر أبدًا على الأعمال التي تُطابَق معها، ولا على ترتيبك في البحث، '
      || 'ولا على عرضك كمورّد مفضّل. كل مورّد يُطابَق على أساس الملاءمة وحدها. '
      || 'هذا سجل لأدائك، لا موقع في طابور.'
  );
$function$;

-- `create or replace` keeps the ACL; the revoke is restated so a drop-and-create later cannot reopen it.
revoke all on function public.fn_supplier_tier(bigint) from public, anon, authenticated;

-- ── PROOF, AS A ROW ────────────────────────────────────────────────────────────────────────────
with quoting as (select supplier_id, count(*) n from public.quotes group by 1 order by 2 desc limit 1),
     idle as (select l.id from public.leads l where not exists (select 1 from public.quotes q where q.supplier_id = l.id) limit 1),
     r1 as (select public.fn_supplier_tier((select supplier_id from quoting)) j),
     r2 as (select public.fn_supplier_tier((select id from idle)) j)
select case
         when (select count(*) from quoting) = 0 then 'PROBE OK (no supplier has quoted yet; idle path: '
              || ((select j->>'tier' from r2) = 'unranked' and (select (j->>'available')::boolean from r2) is false)::text || ')'
         when (select (j->>'available')::boolean from r1)
              and (select (j->'progress'->>'quotes_submitted')::int from r1) = (select n from quoting)
              and (select j->>'tier' from r1) in ('bronze','silver','gold','platinum')
              and (select j->>'tier' from r2) = 'unranked'
              and (select (j->>'available')::boolean from r2) is false
           then 'PROBE OK'
         else 'PROBE FAILED'
       end as verdict,
       (select j->>'tier' from r1) quoting_supplier_tier,
       (select j->'progress'->>'quotes_submitted' from r1) quoting_supplier_submitted,
       (select n from quoting) quotes_in_table,
       (select j->>'tier' from r2) idle_supplier_tier;

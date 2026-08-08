-- ROW #5 §20 — THE QUOTESDONE SUPPLIER TIER. Bronze / Silver / Gold / Platinum.
--
-- ── AND TODAY IT RETURNS 'unranked' FOR EVERY SUPPLIER ON PRODUCTION, ON PURPOSE ────────────────
-- Measured 8 Aug 2026 across all 20,465 supplier_score rows:
--
--     quotes_submitted non-null-and-nonzero : 0
--     quotes_won                            : 0
--     quality_rating                        : 0
--     response_rate  distinct values        : 3   (min 0, max 99)
--     reliability    distinct values        : 3   (min 0, max 54.5)
--
-- Three distinct values across twenty thousand companies is not a distribution, it is a default.
-- Nobody has quoted, won or been rated, so there is nothing yet that could separate one supplier
-- from another. A tier computed from that would sort the whole estate into one bucket and print a
-- badge on it — a ranking that ranks nothing, which is worse than no ranking because it looks like
-- a judgement.
--
-- So the ladder is REAL and the placement is HONEST: a supplier with no activity is `unranked`,
-- and is told exactly what reaches the next rung. That is the gamification the spec is actually
-- after — it exists to tell a supplier what to do next — and it starts working the moment the
-- first quote is submitted, with no change to this routine.
--
-- THRESHOLDS ARE STATED, NOT HIDDEN. A tier a supplier cannot predict is a mood, not a target.
create or replace function public.fn_supplier_tier(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with s as (
    select coalesce(quotes_submitted, 0) submitted, coalesce(quotes_won, 0) won,
           response_rate, quality_rating, reliability
      from public.supplier_score where lead_id = p_lead_id
  ),
  -- ACTIVITY IS THE GATE, and it is checked before the score is consulted. A supplier who has never
  -- quoted has no performance to measure, and averaging nulls into a number would manufacture one.
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
    -- The supplier must never read the first when the second is true.
    'available', (select active from a),
    'basis', case when (select active from a)
                  then 'quotes won and quality rating, from supplier_score'
                  else 'no quote has been submitted yet, so there is nothing to rank — this is not a low score' end,
    'ladder', jsonb_build_array(
      jsonb_build_object('tier','bronze',  'needs','submit your first quote'),
      jsonb_build_object('tier','silver',  'needs','win 1 job'),
      jsonb_build_object('tier','gold',    'needs','win 5 jobs and hold a 70% quality rating'),
      jsonb_build_object('tier','platinum','needs','win 10 jobs and hold an 85% quality rating')
    ),
    'progress', jsonb_build_object(
      'quotes_submitted', (select submitted from s),
      'quotes_won', (select won from s),
      -- NULL, not 0. A rating is earned; nobody has earned one, and 0 would read as "rated badly".
      'quality_rating', (select quality_rating from s),
      'response_rate', (select response_rate from s)
    ),
    -- WHAT THE TIER CONFERS IS NOT WIRED, AND SAYING SO IS THE POINT. §20 asks for a tier that
    -- changes RFQ distribution, preferred status and visibility. Those change WHICH REAL COMPANIES
    -- GET WORK, so they are a founder decision, not an implementation detail — and with every
    -- supplier unranked they would confer nothing today regardless.
    'benefits_active', false,
    'benefits_note', 'The ladder is published; it does not yet change RFQ distribution, preferred status or search visibility.'
  );
$function$;

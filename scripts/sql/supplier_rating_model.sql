-- ROW #5 — THE SUPPLIER RATING MODEL, as the founder specified it on 2026-08-08.
--
-- ── THE DECISION THIS IMPLEMENTS ────────────────────────────────────────────────────────────────
-- "These leads will not have rating. We will have rating for the verified suppliers. So once we
--  start emailing and inviting these leads, once they join in and they are verified, then the score
--  and score rating for the suppliers is active. It's just for the verified ones."
--
-- Three inputs, in the founder's own order of power:
--   1. A reveal the supplier does not respond to  — the only thing that DROPS a rating today.
--   2. Jobs won through the platform              — more work, higher rating.
--   3. The customer's own 1-5 rating with a written reason, solicited after the job — HIGHEST power.
--
-- ── WHAT WAS WRONG BEFORE ───────────────────────────────────────────────────────────────────────
-- fn_supplier_score_refresh wrote `leads.rating` into supplier_score.quality_rating.
-- leads.rating is the GOOGLE MAPS star rating of a scraped business — Google's opinion of a company
-- QuotesDone has never worked with, on 4,477 rows, none of them verified, none of them a customer of
-- ours. Presenting that as "your QuotesDone quality rating" is a claim the platform has not earned
-- and cannot stand behind. It was also on the wrong scale: 0-5 rendered into a 0-100 bar, so a
-- 4.5-star business displayed as "5%".
--
-- The scale bug is now moot, because the Maps number is not the source at all.
--
-- ── AND THE `reviews` TABLE WAS ALREADY THERE, UNREAD ───────────────────────────────────────────
-- public.reviews already carries supplier_id, customer_id, inquiry_id, rating, comment and six
-- sub-scores. Measured before this change: 0 rows, and ZERO routines referencing it. Built and
-- abandoned, exactly like supplier_product was. This is its first reader.

-- ── 1. A RATING WITHOUT A REASON IS NOT ACCEPTED ────────────────────────────────────────────────
-- "he need to specify a reason. he need to write anything. Like, even if it's, like, five words
--  would be enough." A bare star with no words is worth little to the next customer reading it, and
--  the whole point of collecting these is that a future customer can weigh them. Ten characters is
--  about five short words — low enough not to make it hard, high enough to exclude an empty box.
alter table public.reviews
  drop constraint if exists reviews_reason_required;
alter table public.reviews
  add constraint reviews_reason_required
  check (comment is not null and length(btrim(comment)) >= 10) not valid;

alter table public.reviews
  drop constraint if exists reviews_rating_range;
alter table public.reviews
  add constraint reviews_rating_range check (rating between 1 and 5) not valid;

-- One rating per customer per job. Without this a single unhappy customer could file ten reviews and
-- sink a supplier, which would make the whole signal untrustworthy for everyone reading it.
create unique index if not exists reviews_one_per_job
  on public.reviews (supplier_id, inquiry_id, customer_id);

-- ── 2. QUALITY RATING IS EARNED ON THE PLATFORM, BY VERIFIED SUPPLIERS ONLY ─────────────────────
create or replace function public.fn_supplier_quality(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  select jsonb_build_object(
    'lead_id', p_lead_id,
    -- NULL, not 0, when there is nothing to say. An unrated supplier is unrated; a supplier rated
    -- zero is one every customer disliked, and those must never look the same on a screen.
    'stars', (select round(avg(r.rating)::numeric, 2) from public.reviews r where r.supplier_id = p_lead_id),
    'pct', (select round(avg(r.rating)::numeric * 20, 1) from public.reviews r where r.supplier_id = p_lead_id),
    'count', (select count(*) from public.reviews r where r.supplier_id = p_lead_id),
    'eligible', (select coalesce(verified, false) from public.leads where id = p_lead_id),
    'reason', case
      when not (select coalesce(verified, false) from public.leads where id = p_lead_id)
        then 'not_verified'
      when (select count(*) from public.reviews r where r.supplier_id = p_lead_id) = 0
        then 'no_reviews_yet'
      else null end,
    -- The written reasons, which are the point. A star with no words persuades nobody.
    'recent', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'stars', r.rating, 'comment', r.comment, 'at', r.created_at
      ) order by r.created_at desc), '[]'::jsonb)
      from (select * from public.reviews where supplier_id = p_lead_id
            order by created_at desc limit 5) r
    ),
    -- The sub-scores the table already carries, averaged where present.
    'facets', (
      select jsonb_build_object(
        'communication', round(avg(r.r_communication)::numeric, 2),
        'quality', round(avg(r.r_quality)::numeric, 2),
        'punctuality', round(avg(r.r_punctuality)::numeric, 2),
        'documentation', round(avg(r.r_documentation)::numeric, 2),
        'after_sales', round(avg(r.r_after_sales)::numeric, 2),
        'compliance', round(avg(r.r_compliance)::numeric, 2))
      from public.reviews r where r.supplier_id = p_lead_id
    )
  );
$function$;

comment on function public.fn_supplier_quality(bigint) is
  'Row #5. A supplier''s EARNED quality rating: customer reviews only, verified suppliers only, '
  'NULL when unrated. Never the scraped Google Maps star rating.';

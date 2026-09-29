-- THE DISPUTE REVIEW ORIGINATES WITH THE SALES ENGINEER (30 Sep 2026; seat: sales_engineer).
--
-- Senior-hire audit, handoffs: seat_handoff_kind ('deliberation.review', customer_support -> ceo) still meant "the
-- CEO reviews customer support's reasoned finding on a post-reveal dispute". The dispute finding moved to the
-- sales engineer on 24 Sep (scripts/sql/reveal_follow_up_and_dispute_findings_belong_to_the_sales_engineer.sql,
-- which dropped fn_customer_support_disputes_tick and its fault surface).
--
-- WHAT WAS MEASURED (30 Sep 2026, production, read-only):
--   * seat_handoff_kind has deliberation.review customer_support -> ceo with the dispute wording, and
--     sales_engineer -> ceo whose meaning the target file rewrote to "the root cause this seat gave for a metric",
--     so the dispute finding is no longer named on the row that carries it.
--   * The surviving customer_support dispute routines (fn_customer_support_dispute_open, _evidence, _consider)
--     collect evidence; none of their bodies names deliberation or a handoff.
--   * The customer_support -> ceo row is NOT dead: the_ceo_sets_the_target_runs_experiments_and_watches_competitors.sql
--     registers the same pair for the root-cause review (customer support owns reveal_conversion_pct), and
--     fn_seat_deliberation_open raises without it. So the row stays, and only its dispute wording goes.
--
-- WHAT THIS CHANGES: the customer_support -> ceo row means the root-cause review (its owner is the target file);
-- the sales_engineer -> ceo row names both judgements the CEO reviews from that seat. customer_support_activates_
-- wins_back_and_settles_disputes.sql no longer inserts the dispute wording.
--   node scripts/apply_sql.mjs scripts/sql/the_dispute_review_originates_with_the_sales_engineer.sql --apply --ddl

update public.seat_handoff_kind
   set meaning = 'The CEO challenges, on a model of another family, the root cause this seat gave for a metric behind the target path.',
       owner_file = 'scripts/sql/the_ceo_sets_the_target_runs_experiments_and_watches_competitors.sql'
 where type = 'deliberation.review' and from_seat = 'customer_support' and to_seat = 'ceo';

update public.seat_handoff_kind
   set meaning = 'The CEO reviews, on a model of another family, the sales engineer''s reasoned judgements: a post-reveal dispute finding on fault, and the root cause it gave for a metric behind the target path.',
       owner_file = 'scripts/sql/the_dispute_review_originates_with_the_sales_engineer.sql'
 where type = 'deliberation.review' and from_seat = 'sales_engineer' and to_seat = 'ceo';

select case
  when exists (select 1 from public.seat_handoff_kind where type = 'deliberation.review' and from_seat = 'customer_support'
                and meaning ilike '%dispute%')
    then 'PROBE FAILED: customer_support still originates the dispute review'
  when not exists (select 1 from public.seat_handoff_kind where type = 'deliberation.review' and from_seat = 'customer_support'
                    and to_seat = 'ceo')
    then 'PROBE FAILED: the customer_support root-cause review lost its registered pair'
  when not exists (select 1 from public.seat_handoff_kind where type = 'deliberation.review' and from_seat = 'sales_engineer'
                    and to_seat = 'ceo' and meaning ilike '%dispute%')
    then 'PROBE FAILED: the sales_engineer -> ceo review does not name the dispute finding'
  else 'PROBE OK: the dispute review originates with the sales engineer' end as verdict;

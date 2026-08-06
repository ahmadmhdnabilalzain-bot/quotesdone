-- EVERY REVENUE FIGURE THE CEO LAYER HAS EVER PRODUCED WAS A CONSTANT ZERO — AND THE ZERO LOOKED RIGHT.
--
-- company_goals.revenue_annual is "Reach AED 1,000,000 annual revenue", metric "Recognised revenue
-- in trailing 12 months". Its measure_sql was:
--     select count(*)::numeric from inquiries where created_at > now()-interval '30 days'
-- It counts INQUIRIES, not revenue. Over 30 days, not 12 months. Against a table holding 0 rows.
--
-- The reason this survived is the nastiest part: the wrong measure returns 0 and the right measure
-- ALSO returns 0, because production genuinely has no revenue yet. A measure that returns the right
-- number for the wrong reason cannot be caught by looking at its output — only by reading it. The
-- moment one inquiry is created, "revenue" would have read 1.00 AED against a 1,000,000 target.
--
-- customer_satisfaction was wrong in the same way and about to get worse. Its measure was
--     select round(100.0*count(*) filter (where decision='approve')/nullif(count(*),0),2)
--       from review_chain where dept_key='marketing' and created_at > now()-interval '30 days'
-- which is the MARKETING APPROVAL RATE, not customer satisfaction, expressed as a percentage
-- against a target of 4.5 on a 1-5 rating scale. It read 0 only because review_chain was empty —
-- and this session just gave review_chain two new writers, so it would have started returning a
-- confident, meaningless number tomorrow. `reviews.rating` (1-5, CHECK-constrained) is the actual
-- customer rating store.
--
-- SCOPE. The spec names seven company objectives (architecture file, lines 21-27). Those seven are
-- fixed here. The other 56 goals in the table belong to later spec files and are deliberately left
-- alone rather than filled in speculatively: a measure that is merely plausible is how both defects
-- above were created. NULL is an honest answer; a wrong number is not.
--
-- Each statement below was EXECUTED against production before being stored. They return 0 or NULL
-- today because production holds 0 transactions, 0 inquiries, 0 quotes and 0 reviews — that is the
-- correct reading of an unlaunched marketplace, not a broken measure.

-- 1. "Reach AED 1,000,000 annual revenue."
-- coalesce(reveal_fee, app_fee, 0) follows the interpretation already established in fn_challenge:
-- one fee or the other is charged, never summed. refund_confirmed_at is used rather than
-- refund_status because there is no CHECK constraint on refund_status and its vocabulary would be
-- a guess; a confirmed refund is unambiguous.
update public.company_goals set measure_sql =
$m$select coalesce(sum(coalesce(t.reveal_fee, t.app_fee, 0)), 0)::numeric
     from transactions t
    where t.revealed_at > now() - interval '365 days'
      and t.refund_confirmed_at is null$m$
where key = 'revenue_annual';

-- 2. "Increase customer satisfaction." Average rating on the 1-5 scale the target is stated in.
update public.company_goals set measure_sql =
$m$select round(avg(r.rating)::numeric, 2)
     from reviews r
    where r.created_at > now() - interval '90 days'$m$
where key = 'customer_satisfaction';

-- 3. "Increase supplier satisfaction." supplier_perf.rating, restricted to suppliers who actually
-- have reviews — averaging in unrated suppliers as 0 would invent dissatisfaction.
update public.company_goals set measure_sql =
$m$select round(avg(p.rating)::numeric, 2)
     from supplier_perf p
    where coalesce(p.review_count, 0) > 0$m$
where key = 'supplier_satisfaction';

-- 4. "Increase quotation conversion rate." Share of QUOTED inquiries reaching a paid reveal, which
-- is what the metric text says — distinct from rfq_completion_rate, which measures reaching a quote
-- at all.
update public.company_goals set measure_sql =
$m$select round(100.0 * count(distinct t.inquiry_id) / nullif(count(distinct q.inquiry_id), 0), 2)
     from quotes q
     left join transactions t
       on t.inquiry_id = q.inquiry_id and t.revealed_at is not null
    where q.created_at > now() - interval '30 days'$m$
where key = 'quote_conversion_rate';

-- 5. "Reduce operational costs." Platform cost per CLOSED RFQ, per the metric text. nullif keeps it
-- NULL rather than dividing by zero while no RFQ has closed — an honest "not yet measurable"
-- instead of a fabricated infinity.
update public.company_goals set measure_sql =
$m$select round(
       (select coalesce(sum(c.cost_aed), 0) from ai_cost_log c
         where c.occurred_at > now() - interval '30 days')
       / nullif((select count(*) from inquiries i
                  where i.created_at > now() - interval '30 days'
                    and exists (select 1 from transactions t
                                 where t.inquiry_id = i.id and t.revealed_at is not null)), 0)
     , 2)$m$
where key = 'operating_cost';

-- 6 and 7. "Improve RFQ completion rate" and supplier coverage already carry correct measures
-- (verified by reading them, not by their output). Left untouched deliberately.

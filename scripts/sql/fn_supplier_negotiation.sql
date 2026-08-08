-- ROW #5 §12 — THE NEGOTIATION ASSISTANT'S ARITHMETIC.
--
-- The customer has asked for a discount. What can QuotesDone honestly tell the supplier?
--
-- ── THE ONE THING IT MUST NOT DO IS INVENT A FLOOR ──────────────────────────────────────────────
-- "You can go down to X" is the answer a supplier wants and the one thing this platform cannot
-- give: QuotesDone knows the quote, the app fee and the customer price, and it does NOT know what
-- the job costs the supplier to deliver. Without a cost there is no margin in the sense that
-- matters, and no floor. A "recommended discount" computed from the platform's own 3% fee would
-- look exactly like advice about the supplier's profit and would be nothing of the kind — a
-- supplier could accept a cut that loses them money on the strength of it.
--
-- So this returns two clearly separated things:
--   · the PLATFORM margin, which is known exactly and is labelled as the platform's, not theirs;
--   · reduction SCENARIOS — arithmetic, not advice. "At -5% you receive X and the customer pays Y."
-- The supplier applies their own cost, which only they have. supplier_cost_known is false, and the
-- surface says so in words rather than leaving the omission to be noticed.
create or replace function public.fn_supplier_negotiation(p_quote_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with q as (
    select id, inquiry_id, supplier_id, quote_amount, margin_rate, app_fee, customer_price, lead_time, warranty
      from public.quotes where id = p_quote_id
  ),
  -- The inbound side of the conversation only. What the supplier said is not evidence of pressure.
  inbound as (
    select m.id, m.body, m.created_at
      from public.messages m join q on q.inquiry_id = m.inquiry_id and q.supplier_id = m.supplier_id
     where m.sender = 'customer' order by m.created_at desc limit 10
  ),
  scen as (
    select v.pct,
           round((select quote_amount from q) * (1 - v.pct / 100.0), 2) new_quote,
           round((select quote_amount from q) * (1 - v.pct / 100.0)
                 * (1 + coalesce((select margin_rate from q), 0)), 2) new_customer_price,
           round((select quote_amount from q) * (v.pct / 100.0), 2) you_give_up
      from (values (3), (5), (10)) v(pct)
  )
  select jsonb_build_object(
    'quote_id', p_quote_id,
    -- The thread this quote belongs to. Returned because the drafted reply has to be SENDABLE, and
    -- messages_api keys a thread on (inquiry_id, supplier_id) — without both, the draft is a
    -- suggestion the supplier has to retype somewhere else.
    'inquiry_id', (select inquiry_id from q),
    'supplier_id', (select supplier_id from q),
    'quote_amount', (select quote_amount from q),
    'customer_price', (select customer_price from q),
    -- THE PLATFORM'S margin, named as such. app_fee / quote_amount is QuotesDone's cut, and calling
    -- it "your margin" would be a lie by label.
    'margin', jsonb_build_object(
      'whose', 'platform',
      'app_fee', (select app_fee from q),
      'margin_rate', (select margin_rate from q),
      'note', 'This is the QuotesDone fee on the reveal, not your profit.'),
    'supplier_cost_known', false,
    'possible_reduction', jsonb_build_object(
      'available', false,
      'why', 'QuotesDone does not know what this job costs you to deliver, so it cannot tell you how far you can go. The scenarios below are arithmetic, not advice.',
      'scenarios', coalesce((select jsonb_agg(jsonb_build_object(
          'reduction_pct', s.pct, 'you_receive', s.new_quote,
          'customer_pays', s.new_customer_price, 'you_give_up', s.you_give_up)
        order by s.pct) from scen s), '[]'::jsonb)),
    'inbound_messages', coalesce((select jsonb_agg(jsonb_build_object(
        'id', i.id, 'body', i.body, 'created_at', i.created_at) order by i.created_at desc)
      from inbound i), '[]'::jsonb),
    'population', jsonb_build_object(
      'customer_messages', (select count(*) from inbound),
      'note', case when (select count(*) from inbound) = 0
                   then 'the customer has not written anything yet, so there is no discount request to read'
                   else null end),
    'terms', jsonb_build_object('lead_time', (select lead_time from q), 'warranty', (select warranty from q))
  );
$function$;

-- ROW #5 — WHEN DO WE ASK THE CUSTOMER TO RATE THE SUPPLIER?
--
-- Founder, 2026-08-08: "its not fixed 3 months. it depends on the duration mentioned on the quotes
-- received. once the customer reveal a specific quote, the duration will be mentioned there. so if
-- its a week for example, then we ask the customer after 7 working days."
--
-- So the clock is:   transactions.revealed_at  +  the revealed quote's own lead_time
--
-- and it scales with the job. A fixed ninety days would chase a one-week job eleven weeks late and
-- interrupt a nine-month fit-out while it was still running. This is an ESTIMATE of when the work
-- finished — QuotesDone does not observe completion — and everything below is built so that an
-- estimate never masquerades as a fact.
--
-- ── THE PARSER REFUSES WHAT IT CANNOT READ ──────────────────────────────────────────────────────
-- quotes.lead_time is free text and there is not one non-null value in either project, so there is
-- no corpus to tune against. Guessing a default for an unrecognised string would silently schedule
-- a real e-mail and a real WhatsApp to a real customer at a time nobody chose. fn_lead_time_interval
-- returns NULL instead, and a NULL interval is never due — it is reported as unschedulable so the
-- gap is visible and fixable, rather than absorbed into a wrong date.
create or replace function public.fn_lead_time_interval(p_text text)
returns interval
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  with t as (select lower(btrim(coalesce(p_text, ''))) s),
  m as (
    select s,
           nullif((regexp_match(s, '(\d+(?:\.\d+)?)'))[1], '')::numeric  as qty,
           -- "working"/"business" days are 5 per week, so N of them span N*7/5 calendar days.
           -- Reading them as calendar days would ask a week early on a two-week job.
           (s ~ 'working|business')                                       as business
      from t
  )
  select case
    when qty is null then null
    when s ~ '\m(hour|hr|hrs|hours)\M'   then make_interval(hours  => ceil(qty)::int)
    when s ~ '\m(day|days)\M'            then make_interval(days   => ceil(qty * case when business then 7.0/5.0 else 1 end)::int)
    when s ~ '\m(week|weeks|wk|wks)\M'   then make_interval(days   => ceil(qty * 7)::int)
    when s ~ '\m(month|months|mo|mos)\M' then make_interval(months => ceil(qty)::int)
    else null                            -- a number with no unit is not a duration
  end
  from m;
$function$;

-- WHICH RATINGS ARE DUE, AS AT A GIVEN MOMENT.
--
-- p_now is a PARAMETER, not now(), and that is deliberate: it makes the schedule testable without
-- back-dating a single row. Asking "what would be due two hours from now" is a question; editing
-- revealed_at so that something looks due today is falsifying the record, and the standing rule
-- forbids it.
create or replace function public.fn_rating_due(p_now timestamptz default now())
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with rev as (
    select t.id transaction_id, t.quote_id, t.inquiry_id, t.supplier_id, t.customer_id,
           t.revealed_at, q.lead_time,
           public.fn_lead_time_interval(q.lead_time) span
      from public.transactions t
      join public.quotes q on q.id = t.quote_id
     where t.revealed_at is not null
  ),
  judged as (
    select r.*,
           (r.span is not null) schedulable,
           case when r.span is not null then r.revealed_at + r.span end due_at,
           exists (select 1 from public.reviews v
                    where v.transaction_id = r.transaction_id
                       or (v.supplier_id = r.supplier_id and v.inquiry_id = r.inquiry_id)) already_rated
      from rev r
  )
  select jsonb_build_object(
    'as_at', p_now,
    'basis', 'transactions.revealed_at + the revealed quote''s own lead_time — an ESTIMATE of completion, not an observation of it',
    'population', jsonb_build_object(
      'reveals', (select count(*) from rev),
      'schedulable', (select count(*) from judged where schedulable),
      -- The honest counter. A reveal whose lead_time cannot be parsed is not "not due", it is
      -- UNSCHEDULABLE, and it needs a human to look at the string rather than a default.
      'unschedulable', (select count(*) from judged where not schedulable),
      'already_rated', (select count(*) from judged where already_rated)
    ),
    'due', coalesce((select jsonb_agg(jsonb_build_object(
        'transaction_id', j.transaction_id, 'quote_id', j.quote_id, 'inquiry_id', j.inquiry_id,
        'supplier_id', j.supplier_id, 'customer_id', j.customer_id,
        'revealed_at', j.revealed_at, 'lead_time', j.lead_time, 'due_at', j.due_at))
      from judged j where j.schedulable and not j.already_rated and j.due_at <= p_now), '[]'::jsonb),
    'not_yet', coalesce((select jsonb_agg(jsonb_build_object(
        'transaction_id', j.transaction_id, 'lead_time', j.lead_time, 'due_at', j.due_at))
      from judged j where j.schedulable and not j.already_rated and j.due_at > p_now), '[]'::jsonb),
    'unschedulable', coalesce((select jsonb_agg(jsonb_build_object(
        'transaction_id', j.transaction_id, 'lead_time', j.lead_time,
        'why', case when coalesce(btrim(j.lead_time),'') = ''
                    then 'the quote states no lead time'
                    else 'lead time "' || j.lead_time || '" is not a duration this parser recognises' end))
      from judged j where not j.schedulable), '[]'::jsonb)
  );
$function$;

-- The "worked case" on /how-it-works: one real, closed, anonymised deal, or nothing at all.
--
-- WHY. The website audit (14 Sep 2026, "Months" row) asks for one anonymised worked case — brief,
-- quotes, reveal — with real AED numbers "once a real deal closes", and the founder's rule forbids
-- a fixture dressed as one. So this routine returns NULL until a transaction exists that is paid,
-- not refunded or in a refund request, on an inquiry marked completed, whose customer is not an
-- example.invalid demo and whose supplier is not a ZZ DEMO fixture. Measured 14 Sep 2026:
-- transactions = 0, so it returns NULL and the page renders no slot.
--
-- WHAT LEAVES, AND WHY IT CANNOT IDENTIFY ANYONE. Category, emirate, the month it was posted, days
-- from posting to reveal, and per quote: the amount rounded to the nearest AED 100, whether it was
-- the one chosen, and the badge facts the homepage quote-card pattern uses — licence verified,
-- response rate, jobs completed on QuotesDone, app rating — each only when the column holds a real
-- value. No names, ids, emails, phone numbers, notes, scope text or files.
--
-- Called only by the public_site edge function with the service role.

create or replace function public.fn_public_worked_case()
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
with deal as (
  select t.inquiry_id, t.quote_id, t.revealed_at, i.category, i.emirate, i.created_at
    from transactions t
    join inquiries i on i.id = t.inquiry_id
    join leads l on l.id = t.supplier_id
   where t.fee_status = 'paid'
     and t.refund_status is null
     and i.completed_at is not null
     and coalesce(l.company_name, '') not ilike 'ZZ DEMO%'
     and not exists (select 1 from customers c
                      where c.id = i.customer_id and c.email ilike '%example.invalid')
   order by t.revealed_at desc nulls last
   limit 1
)
select case when d.inquiry_id is null then null else jsonb_build_object(
  'category', d.category,
  'emirate', d.emirate,
  'posted_month', to_char(d.created_at at time zone 'Asia/Dubai', 'YYYY-MM'),
  'days_to_reveal', case when d.revealed_at is not null
                         then round(extract(epoch from d.revealed_at - d.created_at) / 86400.0)::int end,
  'quotes', (
    select jsonb_agg(jsonb_build_object(
             'amount', round(q.quote_amount / 100.0) * 100,
             'chosen', q.id = d.quote_id,
             'licence_verified', coalesce(l.verified, false) and l.approval_status = 'approved',
             'response_rate', l.rv_response_rate,
             'jobs_completed', (select count(*) from inquiries x
                                 where x.hired_supplier_id = l.id and x.completed_at is not null),
             'rating', l.app_rating)
           order by q.quote_amount)
      from quotes q join leads l on l.id = q.supplier_id
     where q.inquiry_id = d.inquiry_id and q.quote_amount > 0)
) end
from (select 1) one left join deal d on true;
$fn$;

revoke execute on function public.fn_public_worked_case() from public, anon, authenticated;
grant execute on function public.fn_public_worked_case() to service_role;

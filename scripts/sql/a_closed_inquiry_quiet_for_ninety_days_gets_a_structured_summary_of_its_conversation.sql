-- A CLOSED INQUIRY THAT HAS BEEN QUIET FOR 90 DAYS GETS A STRUCTURED SUMMARY OF ITS CONVERSATION.
-- THE ORIGINAL MESSAGES ARE KEPT: THE SUMMARY IS AN INDEX, NOT A REPLACEMENT.
--
-- Assigned: sales_engineer. 6 Oct 2026. Founder ruling, ledger 1127 item 2 (founder-confirmed task):
-- "when a conversation's inquiry/case closes and it has been inactive for 90 days: summarise it into a
-- structured summary linked to the inquiry/account: parties, inquiry, spec decisions, prices/amounts,
-- dates, commitments, disputes/complaints, outcome ... kept for the full retention window ... the raw
-- conversation is then compressed ... keeping the originals only if the legal basis requires the
-- original correspondence ... If originals must be kept, keep them and say so; the summary is then an
-- index, not a replacement ... deterministic extraction where possible; idempotent."
--
-- THE ORIGINALS MUST BE KEPT. Cabinet Decision No. 74 of 2023, Art. 3(1)(b) (FTA-published text, read
-- 6 Oct 2026): "All accounting records, commercial books and information shall be retained ... (5) five
-- years from the end of the calendar year in which the concerned document was created". The messages of
-- an inquiry are part of that information (they carry the quote, the reveal and the refund trail), and
-- the five years have not run for any of them. The Commercial Transactions Law's correspondence article
-- could not be read (uaelegislation.gov.ae: HTTP 403) and is not relied on. So this job NEVER deletes or
-- rewrites a message. The originals go only when conversation_retention_daily removes them at the end of
-- the duty (a_conversation_is_kept_five_years_after_the_account_goes_quiet_then_its_text_is_removed.sql),
-- and this summary - a business record of the inquiry under ledger 1127 item 1 - stays.
--
-- DETERMINISTIC, NO MODEL CALL. Every field the ruling names is already structured in the database:
--   parties          inquiries.customer_id, the suppliers who quoted (quotes -> leads.company_name)
--   inquiry          inquiries (rfq_no, category, trades, emirate, summary, budget, required_by, status)
--   spec decisions   rfq_clarification question/answer pairs, inquiries.accepted_alternatives
--   prices/amounts   quotes (quote_amount, customer_price, status), transactions (reveal_fee,
--                    total_charged, refund_amount_aed)
--   dates            created, first quote, reveal, completion, first and last message
--   commitments      the revealed quote's lead_time, validity, payment_terms, warranty, scope, exclusions
--   disputes         post_reveal_dispute, refunds, complaint_tickets on the customer's email
--   outcome          inquiries.outcome / lost_reason / status
-- So the cheap route is the free one: no OpenRouter spend. A narrative of free-text nuance (an LLM pass
-- over the message bodies on the matrix-v2 route) is NOT built here; nothing in the ruling's field list
-- needs it.
--
-- CLOSED means: completed_at or outcome or lost_reason is set, or status is a terminal one (closed,
-- completed, cancelled, canceled, lost, expired, won, hired, revealed). QUIET means: no message on the
-- inquiry, and no inquiry change, for 90 days. Idempotent: one row per inquiry, rebuilt only when a newer
-- message or change appears.

create table if not exists public.inquiry_conversation_summary (
  inquiry_id      uuid primary key references public.inquiries(id),
  customer_id     uuid,
  summary         jsonb not null,
  last_activity   timestamptz not null,
  built_at        timestamptz not null default now(),
  method          text not null default 'deterministic',
  originals_kept  boolean not null default true);
comment on table public.inquiry_conversation_summary is
  'The structured summary of a closed, 90-day-quiet inquiry and its conversation (ledger 1127). An index over the kept originals, never a replacement. Kept for the full retention window. Owner: sales_engineer.';
alter table public.inquiry_conversation_summary enable row level security;
revoke all on public.inquiry_conversation_summary from anon, authenticated;
create policy inquiry_conversation_summary_service_only on public.inquiry_conversation_summary
  for all to service_role using (true) with check (true);

create or replace function public.fn_inquiry_conversation_summary_build(p_inquiry uuid)
returns jsonb
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with i as (select * from public.inquiries where id = p_inquiry),
  msg as (select v.source_table, v.source_id, v.channel, v.direction, v.occurred_at
            from public.v_conversation_message v where v.inquiry_id = p_inquiry::text),
  q as (select qu.*, l.company_name from public.quotes qu left join public.leads l on l.id = qu.supplier_id
         where qu.inquiry_id = p_inquiry),
  t as (select * from public.transactions where inquiry_id = p_inquiry),
  rq as (select * from q where q.id in (select quote_id from t))
  select jsonb_build_object(
    'inquiry', (select jsonb_build_object('id', i.id, 'rfq_no', i.rfq_no, 'category', i.category, 'trades', i.trades,
                  'emirate', i.emirate, 'summary', i.summary, 'budget', i.budget, 'required_by', i.required_by,
                  'status', i.status) from i),
    'parties', jsonb_build_object(
       'customer_id', (select customer_id from i),
       'suppliers', (select coalesce(jsonb_agg(distinct jsonb_build_object('supplier_id', q.supplier_id, 'company', q.company_name)), '[]') from q)),
    'spec_decisions', jsonb_build_object(
       'clarifications', (select coalesce(jsonb_agg(jsonb_build_object('asked_at', r.asked_at, 'kind', r.kind,
                            'question', r.question, 'answer', r.answer) order by r.asked_at), '[]')
                            from public.rfq_clarification r where r.inquiry_id = p_inquiry),
       'accepted_alternatives', (select accepted_alternatives from i)),
    'amounts', jsonb_build_object(
       'quotes', (select coalesce(jsonb_agg(jsonb_build_object('supplier_id', q.supplier_id, 'quote_amount', q.quote_amount,
                    'customer_price', q.customer_price, 'status', q.status, 'at', q.created_at) order by q.created_at), '[]') from q),
       'transactions', (select coalesce(jsonb_agg(jsonb_build_object('quote_id', t.quote_id, 'quote_amount', t.quote_amount,
                    'reveal_fee', t.reveal_fee, 'total_charged', t.total_charged, 'revealed_at', t.revealed_at,
                    'refund_status', t.refund_status, 'refund_amount_aed', t.refund_amount_aed)), '[]') from t)),
    'dates', jsonb_build_object(
       'created', (select created_at from i), 'first_quote', (select min(created_at) from q),
       'revealed', (select min(revealed_at) from t), 'completed', (select completed_at from i),
       'first_message', (select min(occurred_at) from msg), 'last_message', (select max(occurred_at) from msg)),
    'commitments', (select coalesce(jsonb_agg(jsonb_build_object('supplier_id', rq.supplier_id, 'lead_time', rq.lead_time,
                      'validity', rq.validity, 'payment_terms', rq.payment_terms, 'warranty', rq.warranty,
                      'scope', rq.scope, 'exclusions', rq.exclusions)), '[]') from rq),
    'disputes', jsonb_build_object(
       'post_reveal', (select coalesce(jsonb_agg(jsonb_build_object('raised_by', d.raised_by, 'stage', d.stage,
                        'outcome', d.outcome, 'decided_at', d.decided_at)), '[]') from public.post_reveal_dispute d where d.inquiry_id = p_inquiry),
       'refunds', (select coalesce(jsonb_agg(jsonb_build_object('status', r.status, 'reason_code', r.reason_code,
                    'amount_fils', r.amount_fils, 'settled_at', r.settled_at)), '[]') from public.refunds r where r.inquiry_id = p_inquiry),
       'complaints', (select coalesce(jsonb_agg(jsonb_build_object('ticket_no', ct.ticket_no, 'status', ct.status,
                       'at', ct.created_at)), '[]')
                       from public.complaint_tickets ct join public.customers c on lower(c.email) = lower(ct.email)
                      where c.id = (select customer_id from i))),
    'outcome', (select jsonb_build_object('outcome', i.outcome, 'lost_reason', i.lost_reason, 'status', i.status,
                  'hired_supplier_id', i.hired_supplier_id) from i),
    'conversation', jsonb_build_object(
       'messages', (select count(*) from msg),
       'by_channel', (select coalesce(jsonb_object_agg(channel, n), '{}') from (select channel, count(*) n from msg group by 1) c),
       'sources', (select coalesce(jsonb_agg(source_table || ':' || source_id order by occurred_at), '[]') from msg)),
    'originals', 'kept: Cabinet Decision 74/2023 Art. 3(1)(b) requires the records for 5 years from the end of the year of creation; this summary is an index');
$fn$;
revoke execute on function public.fn_inquiry_conversation_summary_build(uuid) from public, anon, authenticated;

-- the inquiries that are due: closed, and quiet for 90 days, and with no summary as new as their last activity
create or replace function public.fn_inquiry_conversation_summary_due(p_now timestamptz default now(), p_limit int default 50)
returns table(inquiry_id uuid, last_activity timestamptz)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select i.id, la.at
    from public.inquiries i
    cross join lateral (
      select greatest(i.created_at, i.stage_changed_at, i.completed_at,
                      (select max(v.occurred_at) from public.v_conversation_message v where v.inquiry_id = i.id::text),
                      (select max(t.revealed_at) from public.transactions t where t.inquiry_id = i.id)) as at) la
   where (i.completed_at is not null or i.outcome is not null or i.lost_reason is not null
          or lower(coalesce(i.status, '')) in ('closed', 'completed', 'cancelled', 'canceled', 'lost', 'expired', 'won', 'hired', 'revealed'))
     and la.at < p_now - interval '90 days'
     and not exists (select 1 from public.inquiry_conversation_summary s where s.inquiry_id = i.id and s.last_activity >= la.at)
   order by la.at
   limit greatest(p_limit, 0);
$fn$;
revoke execute on function public.fn_inquiry_conversation_summary_due(timestamptz, int) from public, anon, authenticated;

create or replace function public.fn_inquiry_conversation_summary_run(p_limit int default 50)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; n int := 0;
begin
  for r in select * from public.fn_inquiry_conversation_summary_due(now(), p_limit) loop
    insert into public.inquiry_conversation_summary (inquiry_id, customer_id, summary, last_activity, built_at)
    select r.inquiry_id, i.customer_id, public.fn_inquiry_conversation_summary_build(r.inquiry_id), r.last_activity, now()
      from public.inquiries i where i.id = r.inquiry_id
    on conflict (inquiry_id) do update
       set summary = excluded.summary, last_activity = excluded.last_activity, built_at = excluded.built_at;
    n := n + 1;
  end loop;
  return jsonb_build_object('summarised', n, 'ran_at', now());
end $fn$;
revoke execute on function public.fn_inquiry_conversation_summary_run(int) from public, anon, authenticated;

select cron.schedule('inquiry_conversation_summary_daily', '40 23 * * *',
  $CRON$select public.fn_inquiry_conversation_summary_run(50);$CRON$);
insert into public.cron_registry (jobname, human_name, category, purpose)
values ('inquiry_conversation_summary_daily', 'Summarise closed inquiries quiet for 90 days', 'sales',
        'Ledger 1127 item 2 (sales_engineer): a closed inquiry with no activity for 90 days gets one structured summary '
        || '(parties, inquiry, spec decisions, amounts, dates, commitments, disputes, outcome) built deterministically from '
        || 'the database. The original messages are kept (Cabinet Decision 74/2023 Art. 3); the summary is an index.')
on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

-- PROBE: read-only. The builder on a ZZ DEMO inquiry carries every field the ruling names; nothing is due
-- today that is not closed and 90 days quiet. Returns ONE verdict row.
with d as (select i.id from public.inquiries i join public.customers c on c.id = i.customer_id
            where c.is_demo or c.email ~* 'example\.invalid' limit 1),
s as (select public.fn_inquiry_conversation_summary_build((select id from d)) j),
bad_due as (select count(*) n from public.fn_inquiry_conversation_summary_due(now(), 1000) x
              join public.inquiries i on i.id = x.inquiry_id
             where x.last_activity >= now() - interval '90 days')
select case
  when (select id from d) is null then 'PROBE FAILED: no ZZ DEMO inquiry'
  when not ((select j from s) ?& array['inquiry', 'parties', 'spec_decisions', 'amounts', 'dates', 'commitments', 'disputes', 'outcome', 'conversation', 'originals'])
    then 'PROBE FAILED: a field the ruling names is missing'
  when (select n from bad_due) > 0 then 'PROBE FAILED: an inquiry active in the last 90 days is due'
  else 'PROBE OK: every named field present on a ZZ DEMO inquiry; nothing active is due'
end as verdict;

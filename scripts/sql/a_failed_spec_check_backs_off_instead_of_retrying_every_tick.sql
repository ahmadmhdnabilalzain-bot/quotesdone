-- A FAILED NO-EXACT-SPEC CHECK BACKS OFF INSTEAD OF RETRYING EVERY TICK.
--
-- Assigned: it_engineer (the sweep is sales_engineer's). 22 Sep 2026. Founder instruction 705: repeated work
-- that costs us something must be fixed before the paid routes open.
--
-- MEASURED (22 Sep 2026, origin/main 8497212): resilience_ping calls sales_engineer spec_offer_sweep on every
-- tick (97 ticks/day). For each candidate from fn_spec_offer_candidates it called quote_compare -- the FULL
-- model comparison, up to eight provider calls at 10,000 output tokens -- and read only technical_detail,
-- which quote_compare computes by code. A candidate whose call returned non-200 or no body was never marked
-- (spec_offer_checked_at is set only by fn_spec_offer_open), so the next tick handed it back: one paid
-- comparison per failing inquiry per ~15 minutes, with no limit. 0 candidates today; the path is live.
--
-- WHAT THIS CHANGES
--   1. inquiries.spec_offer_attempts (int, default 0) and inquiries.spec_offer_next_attempt_at.
--   2. decision_policy 'spec_offer_max_attempts' = 5 (a count of retries, not money).
--   3. fn_spec_offer_candidates: the same rule as no_supplier_quoted_the_exact_spec_so_the_customer_is_offered
--      _what_was.sql, plus: skip an inquiry whose next attempt is in the future or whose attempts are spent.
--   4. fn_spec_offer_failed(inquiry, error): counts the attempt, sets the next one 15 minutes out, doubling per
--      attempt (15, 30, 60, 120 min); on the last attempt the inquiry leaves the sweep and the owning seat,
--      sales_engineer, is handed it as a finding (fn_it_engineer_finding_upsert, owner_seat sales_engineer),
--      keyed on the inquiry so a repeat is one finding, not many.
--   The edge side (sales_engineer/index.ts) now asks quote_compare for technical_only -- no model at all --
--   and calls fn_spec_offer_failed on every failure.
--
-- WHAT THIS DOES NOT CHANGE: the candidate rule itself, fn_spec_offer_open (a successful check still marks
-- spec_offer_checked_at exactly as before), reminders, lapses, messages. No money cap.
--
-- Proved by: scripts/checks/a_failed_spec_check_backs_off.test.mjs (demo data, rolled back).

alter table public.inquiries add column if not exists spec_offer_attempts integer not null default 0;
alter table public.inquiries add column if not exists spec_offer_next_attempt_at timestamptz;
comment on column public.inquiries.spec_offer_attempts is
  'Failed no-exact-spec checks on this inquiry. At decision_policy spec_offer_max_attempts it leaves the sweep and sales_engineer is handed a finding (fn_spec_offer_failed).';
comment on column public.inquiries.spec_offer_next_attempt_at is
  'The earliest tick at which the no-exact-spec sweep may try this inquiry again after a failure: 15 minutes, doubling per attempt.';

insert into public.decision_policy (key, value, description, updated_at) values
  ('spec_offer_max_attempts', '5'::jsonb, 'Failed no-exact-spec checks before the inquiry leaves the sweep and sales_engineer is handed it (a retry count, not money). 22 Sep 2026, instruction 705.', now())
on conflict (key) do nothing;

create or replace function public.fn_spec_offer_candidates(p_limit integer default 20)
returns table(inquiry_id uuid, customer_id uuid, why text)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with pol as (select coalesce((select (value #>> '{}')::numeric from public.decision_policy where key = 'spec_offer_quote_window_days'), 7) as days,
                      coalesce((select (value #>> '{}')::int from public.decision_policy where key = 'spec_offer_max_attempts'), 5) as max_attempts),
  inv as (
    select m.inquiry_id, count(distinct m.supplier_id) as invited, min(m.sent_at) as first_sent
      from public.inquiry_matches m group by m.inquiry_id),
  quoted as (
    select q.inquiry_id, count(distinct q.supplier_id) as quoted
      from public.quotes q where coalesce(q.status, '') <> 'draft' group by q.inquiry_id)
  select i.id, i.customer_id,
         case when coalesce(qd.quoted, 0) >= inv.invited then 'every_invited_supplier_quoted' else 'quote_window_closed' end
    from public.inquiries i
    join inv on inv.inquiry_id = i.id
    left join quoted qd on qd.inquiry_id = i.id
   where i.spec_offer_checked_at is null
     -- THE BACKOFF (22 Sep 2026): a failed check waits for its next attempt, and stops after the last one.
     and i.spec_offer_attempts < (select max_attempts from pol)
     and (i.spec_offer_next_attempt_at is null or i.spec_offer_next_attempt_at <= now())
     and coalesce(i.status, '') not in ('closed', 'completed', 'cancelled')
     and i.parent_inquiry_id is null
     -- THE TIMING GUARD (review of #652): at least one live (non-draft) quote.
     and exists (select 1 from public.quotes q1 where q1.inquiry_id = i.id and coalesce(q1.status, '') <> 'draft')
     and not exists (select 1 from public.transactions t join public.quotes q2 on q2.id = t.quote_id where q2.inquiry_id = i.id)
     and (coalesce(qd.quoted, 0) >= inv.invited or now() >= inv.first_sent + make_interval(days => (select days from pol)::int))
   order by i.created_at
   limit greatest(1, least(p_limit, 100));
$fn$;

revoke execute on function public.fn_spec_offer_candidates(integer) from public, anon, authenticated;

create or replace function public.fn_spec_offer_failed(p_inquiry uuid, p_error text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_max int := coalesce((select (value #>> '{}')::int from public.decision_policy where key = 'spec_offer_max_attempts'), 5);
  v_n int; v_next timestamptz;
begin
  update public.inquiries
     set spec_offer_attempts = spec_offer_attempts + 1,
         spec_offer_next_attempt_at = now() + make_interval(mins => (15 * power(2, least(spec_offer_attempts, 10)))::int)
   where id = p_inquiry
  returning spec_offer_attempts, spec_offer_next_attempt_at into v_n, v_next;
  if not found then return jsonb_build_object('ok', false, 'error', 'no_inquiry'); end if;
  if v_n >= v_max then
    perform public.fn_it_engineer_finding_upsert(
      'monitor:spec_offer_check_failed:' || p_inquiry,
      'The no-exact-spec check failed ' || v_n || ' times on inquiry ' || p_inquiry || ' and has stopped retrying',
      'sales_engineer spec_offer_sweep -> quote_compare (technical_only)', 'agent_facing', 1,
      jsonb_build_object('inquiry_id', p_inquiry, 'attempts', v_n, 'last_error', left(coalesce(p_error, ''), 300),
                         'owner_seat', 'sales_engineer',
                         'fix', 'find why quote_compare fails for this inquiry, then reset inquiries.spec_offer_attempts to 0 so the sweep checks it once more'),
      '{}'::text[], array['why quote_compare fails for this inquiry'], 'sales_engineer');
  end if;
  return jsonb_build_object('ok', true, 'attempts', v_n, 'next_attempt_at', v_next, 'handed_to_seat', v_n >= v_max);
end
$fn$;

comment on function public.fn_spec_offer_failed(uuid, text) is
  'A failed no-exact-spec check: count it, back off 15 min doubling, and after spec_offer_max_attempts hand the inquiry to sales_engineer as a finding instead of retrying every tick. 22 Sep 2026, instruction 705.';

revoke execute on function public.fn_spec_offer_failed(uuid, text) from public, anon, authenticated;

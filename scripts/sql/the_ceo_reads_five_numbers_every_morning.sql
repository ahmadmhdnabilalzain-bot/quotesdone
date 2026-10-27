-- THE CEO READS FIVE NUMBERS EVERY MORNING (founder ruling 1209, 13 Oct 2026).
-- Assigned: ceo. Deterministic: no model, no word matching (memory routine-work-is-code-not-llm).
--
-- Once a day the ceo seat counts yesterday (the Dubai calendar day) and hands the count to itself as a
-- 'report.five_numbers' handoff: requests created, quotes received, reveals paid, the supplier response rate
-- (quoted / invited) and disputes. Demo rows are excluded everywhere: an inquiry is demo by fn_inquiry_is_demo
-- (a demo customer, a qd_run provenance or a fixture brief), a supplier by leads.is_demo, a Stripe dispute by
-- livemode = false. It goes to the CEO, never to the founder: the founder's morning mail is fn_ceo_daily_digest,
-- which this does not touch.
--
-- Reuse, not a second report: the handoff ledger (fn_seat_handoff) is the delivery and the dedupe (one row per
-- type + day, a re-run returns the same row), the handler pattern is fn_ceo_reads_marketing_report's, and the
-- schedule is a seat_duty row run by fn_seat_duties_tick. The CEO's read compares each number with the day
-- before from the previous handoff's own evidence, so the numbers live in one place: agent_actions.
--
-- THE RESPONSE RATE'S WINDOW, said out loud: a supplier has 24 hours to quote (sla_quote_hours), so the
-- invitations made on the report day alone have mostly not been answered yet when it is counted. The rate is
-- therefore over the invitations made in the 7 days ending with the report day, each counted as quoted when
-- that supplier has any non-draft quote on that request. The payload names the window.
--
-- prevented by: scripts/checks/the_ceo_reads_five_numbers_every_morning.test.mjs
-- probe: scripts/sql/the_ceo_reads_five_numbers_every_morning_probe.sql (aborted transaction)

create or replace function public.fn_ceo_five_numbers(p_day date)
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with w as (
    select (p_day::timestamp at time zone 'Asia/Dubai') as t0,
           ((p_day + 1)::timestamp at time zone 'Asia/Dubai') as t1,
           ((p_day - 6)::timestamp at time zone 'Asia/Dubai') as r0
  ), inv as (
    select m.inquiry_id, m.supplier_id,
           exists (select 1 from public.quotes q where q.inquiry_id = m.inquiry_id and q.supplier_id = m.supplier_id
                    and coalesce(q.status, '') <> 'draft') as quoted
      from public.inquiry_matches m join public.leads l on l.id = m.supplier_id cross join w
     where m.sent_at >= w.r0 and m.sent_at < w.t1
       and not coalesce(l.is_demo, false) and not public.fn_inquiry_is_demo(m.inquiry_id)
  )
  select jsonb_build_object(
    'day', p_day, 'timezone', 'Asia/Dubai',
    'requests_created', (select count(*) from public.inquiries i, w
                          where i.created_at >= w.t0 and i.created_at < w.t1 and not public.fn_inquiry_is_demo(i.id)),
    'quotes_received', (select count(*) from public.quotes q join public.leads l on l.id = q.supplier_id, w
                         where q.created_at >= w.t0 and q.created_at < w.t1 and coalesce(q.status, '') <> 'draft'
                           and not coalesce(l.is_demo, false) and not public.fn_inquiry_is_demo(q.inquiry_id)),
    'reveals_paid', (select count(*) from public.transactions t, w
                      where t.fee_status = 'paid' and t.revealed_at >= w.t0 and t.revealed_at < w.t1
                        and not public.fn_inquiry_is_demo(t.inquiry_id)),
    'invited_7d', (select count(*) from inv),
    'quoted_7d', (select count(*) from inv where quoted),
    'supplier_response_rate', (select case when count(*) = 0 then null
                                            else round(count(*) filter (where quoted)::numeric / count(*), 3) end from inv),
    'response_rate_window', 'invitations made in the 7 days ending ' || p_day || ' (Dubai); quoted = any non-draft quote',
    'disputes', (select count(*) from public.post_reveal_dispute d, w
                  where d.opened_at >= w.t0 and d.opened_at < w.t1
                    and (d.inquiry_id is null or not public.fn_inquiry_is_demo(d.inquiry_id)))
              + (select count(*) from public.stripe_dispute s, w
                  where s.livemode and s.first_seen_at >= w.t0 and s.first_seen_at < w.t1),
    'demo_excluded', true)
$fn$;
revoke execute on function public.fn_ceo_five_numbers(date) from public, anon, authenticated;

-- THE CEO'S READ: what moved against the day before (from the previous report's own evidence). Informational.
create or replace function public.fn_ceo_reads_five_numbers(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions; v_now jsonb; v_prev jsonb; k text; v_moved jsonb := '{}'::jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' is distinct from 'report.five_numbers' then
    raise exception 'fn_ceo_reads_five_numbers: % is not a report.five_numbers handoff', p_id;
  end if;
  v_now := a.detail->'numbers';
  if v_now is null then raise exception 'report.five_numbers % carries no numbers', p_id; end if;
  select x.detail->'numbers' into v_prev from public.agent_actions x
   where x.kind = 'handoff' and x.agent = 'ceo' and x.target_id = 'report.five_numbers:' || ((a.detail->>'subject_id')::date - 1)
     and x.status <> 'failed' order by x.id desc limit 1;
  foreach k in array array['requests_created', 'quotes_received', 'reveals_paid', 'supplier_response_rate', 'disputes'] loop
    if v_prev is not null and (v_now->k) is distinct from (v_prev->k) then
      v_moved := v_moved || jsonb_build_object(k, jsonb_build_object('from', v_prev->k, 'to', v_now->k));
    end if;
  end loop;
  return jsonb_build_object('read', true, 'day', a.detail->>'subject_id', 'numbers', v_now,
    'moved_since_previous_day', case when v_prev is null then null else v_moved end,
    'note', case when v_prev is null then 'Read by the CEO. No report for the day before to compare with.'
                 else 'Read by the CEO. Informational: nothing was approved or decided.' end);
end $fn$;
revoke execute on function public.fn_ceo_reads_five_numbers(bigint) from public, anon, authenticated;

-- THE DUTY: yesterday's numbers (Dubai), handed to the CEO once. A re-run on the same day returns the same handoff.
create or replace function public.fn_ceo_five_number_report()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_day date := (now() at time zone 'Asia/Dubai')::date - 1; v_n jsonb; v_id bigint; a public.agent_actions;
begin
  v_n := public.fn_ceo_five_numbers(v_day);
  v_id := public.fn_seat_handoff('ceo', 'ceo', 'report.five_numbers', 'five_numbers', v_day::text,
                                 jsonb_build_object('numbers', v_n));
  select * into a from public.agent_actions where id = v_id;
  return jsonb_build_object('handoff_id', v_id, 'status', a.status, 'day', v_day, 'numbers', v_n);
end $fn$;
revoke execute on function public.fn_ceo_five_number_report() from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
values ('report.five_numbers', 'ceo', 'ceo',
        'The ceo''s own morning read of yesterday: requests created, quotes received, reveals paid, supplier response rate (quoted / invited over 7 days) and disputes, demo rows excluded. Informational, and read by the CEO alone.',
        'fn_ceo_reads_five_numbers', interval '1 day', false,
        'scripts/sql/the_ceo_reads_five_numbers_every_morning.sql')
on conflict do nothing;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.five_number_report', 'ceo', interval '1 day', 'fn_ceo_five_number_report',
   'Yesterday''s five numbers (requests, quotes, reveals paid, supplier response rate, disputes; demo excluded) handed to the CEO as report.five_numbers. Ruling 1209.',
   'scripts/sql/the_ceo_reads_five_numbers_every_morning.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- verdict (reads only: this file defines routines, so it must not raise)
select case when exists (select 1 from public.seat_handoff_kind where type = 'report.five_numbers' and to_seat = 'ceo')
             and exists (select 1 from public.seat_duty where duty = 'ceo.five_number_report')
             and (public.fn_ceo_five_numbers(current_date - 1) ?& array['requests_created', 'quotes_received', 'reveals_paid', 'supplier_response_rate', 'disputes'])
            then 'PROBE OK: report.five_numbers registered, ceo.five_number_report scheduled, five numbers computed'
            else 'PROBE FAILED: the kind, the duty or the five keys are missing' end as verdict;

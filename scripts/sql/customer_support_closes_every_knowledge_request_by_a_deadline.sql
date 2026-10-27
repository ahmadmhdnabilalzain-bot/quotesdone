-- CUSTOMER SUPPORT CLOSES EVERY KNOWLEDGE REQUEST BY A DEADLINE (19 Oct 2026). Assigned: customer_support (it routes,
-- chases and closes); the seat that writes the entry is named per request. Founder ledger 1003 stage 2, contribution
-- CS-C03: "Turn every unanswered question into a knowledge request and close it with an entry".
--
-- MEASURED 19 Oct 2026 (production, read-only): sales_knowledge_gap holds 57 open requests (first asked 9 Sep onward,
-- 98 asks between them), 6 knowledge_added, 4 not_a_gap. Filing works (the weekly review filed 19 of 19), but no row
-- carries a deadline or an owner, and nothing chases one. Their nearest corpus: kb_chunks 21, support_corpus 23,
-- sales_knowledge 10, company_faq 1, none 2.
--
-- WHAT THIS ADDS: customer_support.knowledge_request_deadline, daily, fn_customer_support_knowledge_request_tick().
-- Code, no model. For every open request:
--   route   once: the owning seat by the corpus that came nearest (trade and specification knowledge, kb_chunks and
--           sales_knowledge -> sales_engineer; company knowledge, the support corpus and the FAQ -> ceo, which owns
--           the company-knowledge sync), a deadline of decision_policy knowledge_request_days (7) FROM ROUTING (so
--           the 57 already open are not all overdue on the first run), and a knowledge.request handoff in that seat's
--           inbox carrying the question, how often it was asked and the deadline.
--   chase   past the deadline and still open: a report to the CEO (fn_support_report_to_ceo, once per round), the
--           deadline moved one period on, chase_count + 1. A request asked AGAIN after routing is chased at once.
--   close   when the request is no longer open (knowledge_added or not_a_gap, set where the entry is ingested), the
--           knowledge.request handoff is completed with that evidence (the originator closes: customer_support).
-- qd.duty_fixtures = 'on' reads only ZZ DEMO questions.
--
-- Prevented by: scripts/checks/customer_support_senior_contributions_are_working_duties.test.mjs.
-- Apply at merge:  node scripts/apply_sql.mjs scripts/sql/customer_support_closes_every_knowledge_request_by_a_deadline.sql --apply --ddl

insert into public.decision_policy (key, value, description) values
  ('knowledge_request_days', '7'::jsonb,
   'fn_customer_support_knowledge_request_tick: days the owning seat has to land a knowledge entry for a routed knowledge request before customer_support chases it through the CEO.')
on conflict (key) do nothing;

alter table public.sales_knowledge_gap
  add column if not exists owner_seat  text,
  add column if not exists due_at      timestamptz,
  add column if not exists routed_at   timestamptz,
  add column if not exists handoff_id  bigint,
  add column if not exists chase_count integer not null default 0,
  add column if not exists chased_at   timestamptz;
comment on column public.sales_knowledge_gap.owner_seat is 'The seat that lands the knowledge entry (fn_customer_support_knowledge_request_tick routes it).';
comment on column public.sales_knowledge_gap.due_at is 'When the entry is owed; past it customer_support chases through the CEO and moves it one period on.';

create or replace function public.fn_seat_takes_knowledge_request(p_id bigint)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('accepted', true, 'seat', a.agent, 'gap_id', a.detail->'gap_id',
    'waiting', coalesce(a.detail->>'waiting_for', 'a knowledge entry that answers the question'))
    from public.agent_actions a where a.id = p_id
$fn$;
revoke execute on function public.fn_seat_takes_knowledge_request(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
select 'knowledge.request', 'customer_support', s,
       'A question customer_support could not answer from knowledge. The receiving seat lands an entry that answers it by the deadline in the payload; customer_support closes this when the request is marked knowledge_added or not_a_gap.',
       'fn_seat_takes_knowledge_request', interval '7 days', true,
       'scripts/sql/customer_support_closes_every_knowledge_request_by_a_deadline.sql'
  from unnest(array['sales_engineer', 'ceo']) s
on conflict (type, from_seat, to_seat) do update
   set meaning = excluded.meaning, handler = excluded.handler, reply_within = excluded.reply_within,
       originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

create or replace function public.fn_customer_support_knowledge_request_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_days int := greatest(1, public.fn_seat_clock_policy('knowledge_request_days', 7)::int);
  k record; v_seat text; v_h bigint; v_r jsonb; n_routed int := 0; n_chased int := 0; n_closed int := 0;
begin
  -- close: the entry landed (or the question was judged not a gap)
  for k in select g.* from public.sales_knowledge_gap g
            where g.status <> 'open' and g.handoff_id is not null and (g.question like 'ZZ DEMO%') = v_fx
              and exists (select 1 from public.agent_actions a where a.id = g.handoff_id and a.status not in ('done', 'failed')) loop
    perform public.fn_seat_handoff_complete(k.handoff_id, jsonb_build_object('gap_id', k.id, 'status', k.status, 'closed_at', k.closed_at));
    n_closed := n_closed + 1;
  end loop;

  -- route: an owner and a deadline, once
  for k in select g.* from public.sales_knowledge_gap g
            where g.status = 'open' and g.routed_at is null and (g.question like 'ZZ DEMO%') = v_fx
            order by g.asks desc, g.id limit 100 loop
    v_seat := case when k.nearest_corpus in ('kb_chunks', 'sales_knowledge') then 'sales_engineer' else 'ceo' end;
    v_h := public.fn_seat_handoff('customer_support', v_seat, 'knowledge.request', 'sales_knowledge_gap', k.id::text,
      jsonb_build_object('gap_id', k.id, 'question', left(k.question, 1000), 'asks', k.asks, 'first_asked_at', k.first_asked_at,
                         'nearest_corpus', k.nearest_corpus, 'due_at', now() + make_interval(days => v_days),
                         'waiting_for', 'a knowledge entry answering "' || left(k.question, 160) || '" by '
                           || to_char((now() + make_interval(days => v_days)) at time zone 'Asia/Dubai', 'YYYY-MM-DD') || ' Dubai'));
    update public.sales_knowledge_gap set owner_seat = v_seat, routed_at = now(), due_at = now() + make_interval(days => v_days),
           handoff_id = v_h where id = k.id;
    n_routed := n_routed + 1;
  end loop;

  -- chase: past its deadline, or asked again since it was routed
  for k in select g.* from public.sales_knowledge_gap g
            where g.status = 'open' and g.routed_at is not null and (g.question like 'ZZ DEMO%') = v_fx
              and (g.due_at < now() or (g.last_asked_at > coalesce(g.chased_at, g.routed_at) and g.asks > 1))
            order by g.id limit 50 loop
    if not v_fx then
      v_r := public.fn_support_report_to_ceo(
        'knowledge_request_overdue:' || k.id || ':' || (k.chase_count + 1), 'routine',
        'Knowledge request #' || k.id || ' is ' || case when k.due_at < now() then 'past its deadline' else 'being asked again' end
          || ' (' || k.owner_seat || ')',
        jsonb_build_object('gap_id', k.id, 'question', left(k.question, 500), 'asks', k.asks, 'owner_seat', k.owner_seat,
                           'due_at', k.due_at, 'last_asked_at', k.last_asked_at, 'handoff_id', k.handoff_id),
        jsonb_build_array('routed to ' || k.owner_seat || ' on ' || k.routed_at),
        'Have ' || k.owner_seat || ' land the entry (or mark it not_a_gap) so customer_support can answer it.',
        p_source_agent => 'customer_support');
    end if;
    update public.sales_knowledge_gap set chase_count = chase_count + 1, chased_at = now(),
           due_at = greatest(due_at, now()) + make_interval(days => v_days) where id = k.id;
    n_chased := n_chased + 1;
  end loop;

  return jsonb_build_object('ok', true, 'fixture', v_fx, 'routed', n_routed, 'chased', n_chased, 'closed', n_closed,
    'still_open', (select count(*) from public.sales_knowledge_gap g where g.status = 'open' and (g.question like 'ZZ DEMO%') = v_fx));
end $fn$;
revoke execute on function public.fn_customer_support_knowledge_request_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_knowledge_request_tick() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.knowledge_request_deadline', 'customer_support', interval '1 day', 'fn_customer_support_knowledge_request_tick',
   'CS-C03: every open knowledge request routed to the seat that writes the entry with a deadline, chased through the CEO when it lapses or is asked again, and closed when the entry lands',
   'scripts/sql/customer_support_closes_every_knowledge_request_by_a_deadline.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

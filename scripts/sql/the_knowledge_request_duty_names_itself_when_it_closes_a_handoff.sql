-- the_knowledge_request_duty_names_itself_when_it_closes_a_handoff
-- Seat: customer_support (owner of customer_support.knowledge_request_deadline). Found by it_engineer in stage-2 run f0b2de8f
-- (2 Nov 2026, scenario S18, the duty probe): the duty raised P0001 "handoff 310924 (knowledge.request) is closed only by its
-- originator customer_support, after it re-verifies; an unnamed caller tried to close it".
--
-- Measured on production 2 Nov 2026: knowledge_request is an originator_closes handoff kind, and trg_handoff_only_originator_closes
-- refuses a close unless the closer names itself in qd.handoff_closer inside its own transaction. The tick closes a handoff
-- through fn_seat_handoff_complete and never named itself. Gap 240 became not_a_gap at 2026-11-02 02:22 UTC with handoff 310924 still
-- pending; the duty last ran at 2026-11-01 20:05 UTC (failures 0), so the next run (2 Nov 20:05 UTC) raises, the whole tick aborts,
-- and no knowledge request is closed, routed or chased until it is fixed.
--
-- The one change: the close step names customer_support for the duration of the loop and clears the name after, the way
-- a_finding_chase_supersedes_the_chase_before_it.sql does for it_engineer. "After it re-verifies" is the loop's own condition: the
-- gap is no longer open (status <> 'open'), which is what the evidence records. The body below is the live body (read from
-- production 2 Nov 2026) plus those two lines. CREATE OR REPLACE keeps the ACL, so no new revoke is needed.
-- Proved by the_knowledge_request_duty_names_itself_when_it_closes_a_handoff_probe.sql (rolled back).
-- Applied at merge (release operator), never before.

create or replace function public.fn_customer_support_knowledge_request_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_days int := greatest(1, public.fn_seat_clock_policy('knowledge_request_days', 7)::int);
  k record; v_seat text; v_h bigint; v_r jsonb; n_routed int := 0; n_chased int := 0; n_closed int := 0;
begin
  -- close: the entry landed (or the question was judged not a gap). The originator closes its own handoff and says so.
  perform set_config('qd.handoff_closer', 'customer_support', true);
  for k in select g.* from public.sales_knowledge_gap g
            where g.status <> 'open' and g.handoff_id is not null and (g.question like 'ZZ DEMO%') = v_fx
              and exists (select 1 from public.agent_actions a where a.id = g.handoff_id and a.status not in ('done', 'failed')) loop
    perform public.fn_seat_handoff_complete(k.handoff_id, jsonb_build_object('gap_id', k.id, 'status', k.status, 'closed_at', k.closed_at));
    n_closed := n_closed + 1;
  end loop;
  perform set_config('qd.handoff_closer', '', true);

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

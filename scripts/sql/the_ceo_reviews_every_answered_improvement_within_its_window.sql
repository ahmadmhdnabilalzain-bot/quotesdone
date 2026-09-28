-- THE CEO REVIEWS EVERY ANSWERED IMPROVEMENT WITHIN ITS WINDOW (ceo, 28 Sep 2026).
--
-- MEASURED (production, 28 Sep 2026):
--   * IT daily email (notification 68583): duty:handoff_sla:ceo.improvement:marketing:unclosed, handoff #99507
--     (improvement 4412, marketing_plan_late for October), answered 24 Sep 17:15 UTC, never closed by the CEO.
--   * It is not alone: 113 ceo.improvement handoffs are pending with replied_at set and evidence.accepted = true
--     (97 it_engineer, 7 sales_engineer, 6 customer_support, 2 accountant, 1 marketing), five open SLA findings.
--   * seat_handoff_kind gives ceo.improvement a 1-day window. The ONLY routine that closes these handoffs is
--     fn_ceo_improvement_close, called from fn_ceo_improvement_sweep, whose seat_duty runs every 7 DAYS
--     (last ok 24 Sep 03:45, before any of them were answered), and which closes only when the SOURCE recovers
--     (7 days on path, the finding closed, 30 days without a repeat). binding_constraint and seat_audit sources
--     have no recovery branch at all. So the close step could never land inside a 1-day window.
--
-- ROOT CAUSE: the handoff (the conversation: "take this on") and the improvement (the work: "until the source
-- recovers") were closed by one event. The seat's answer to the handoff is its acceptance; the CEO never had a
-- step that reviews that answer.
--
-- WHAT THIS CHANGES:
--   fn_ceo_reviews_answered_improvements()  hourly seat_duty 'ceo.improvement_review'. For every answered,
--     still-pending ceo.improvement handoff the CEO reviews the answer:
--       - accepted by the seat that was asked, improvement still tracked (open/assigned with its ceo_task)  ->
--         close the handoff with a receipt naming the improvement and task that carry it to recovery;
--       - improvement already done or dropped -> close with that receipt;
--       - anything else (not accepted, wrong seat, no improvement) -> RETURN it: replied_at removed, the reason
--         recorded in detail.returned, so the seat's handler answers it again.
--   The improvement itself is unchanged: it stays assigned and fn_ceo_improvement_sweep closes it on recovery.
--
-- Prevented by: scripts/checks/the_ceo_reviews_every_answered_improvement.test.mjs (mirror: the routine exists,
-- is on an hourly seat_duty no longer than the ceo.improvement window) and an aborted-transaction ZZ DEMO
-- probe run against production before the apply (it raises, so it writes nothing).
--
--   node scripts/apply_sql.mjs scripts/sql/the_ceo_reviews_every_answered_improvement_within_its_window.sql --apply --ddl

begin;

create or replace function public.fn_ceo_reviews_answered_improvements()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare h record; n_closed int := 0; n_returned int := 0; v_why text;
begin
  for h in select a.id, a.agent, a.evidence, i.id imp_id, i.status imp_status, i.seat imp_seat, i.task_id, i.done_evidence
             from public.agent_actions a
             left join public.ceo_improvement i on i.handoff_id = a.id
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.improvement'
              and a.detail ? 'replied_at'
            order by a.id for update of a loop
    v_why := case
      when h.imp_id is null then 'no ceo_improvement carries this handoff'
      when h.imp_status in ('done', 'dropped') then null
      when coalesce(h.evidence->>'accepted', '') <> 'true' then 'the answer does not accept the improvement'
      when h.evidence->>'seat' is distinct from h.agent or h.imp_seat is distinct from h.agent then 'answered by a seat other than the one asked'
      end;
    if v_why is null then
      perform set_config('qd.handoff_closer', 'ceo', true);
      perform public.fn_seat_handoff_complete(h.id, h.evidence || jsonb_build_object(
        'verified_by', 'ceo', 'reviewed_at', now(), 'improvement_id', h.imp_id,
        'receipt', case when h.imp_status in ('done', 'dropped')
                        then format('Improvement #%s is %s: %s', h.imp_id, h.imp_status, coalesce(h.done_evidence, 'no evidence recorded'))
                        else format('Reviewed by the CEO: %s accepted improvement #%s. The work is tracked on ceo_task #%s and closed by the CEO sweep when its source recovers.',
                                    h.agent, h.imp_id, coalesce(h.task_id::text, 'none')) end));
      perform set_config('qd.handoff_closer', '', true);
      n_closed := n_closed + 1;
    else
      update public.agent_actions
         set detail = (detail - 'replied_at') || jsonb_build_object('returned', jsonb_build_object('at', now(), 'by', 'ceo', 'reason', v_why))
       where id = h.id;
      perform public.fn_seat_handoff_event(h.id, 'returned');
      n_returned := n_returned + 1;
    end if;
  end loop;
  return jsonb_build_object('closed', n_closed, 'returned', n_returned);
end $fn$;
revoke execute on function public.fn_ceo_reviews_answered_improvements() from public, anon, authenticated;
grant execute on function public.fn_ceo_reviews_answered_improvements() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.improvement_review', 'ceo', interval '1 hour', 'fn_ceo_reviews_answered_improvements',
   'Every hour the CEO reviews each answered ceo.improvement handoff: an accepted one is closed with a receipt naming the improvement that carries it to recovery; any other answer is returned to the seat with the reason.',
   'scripts/sql/the_ceo_reviews_every_answered_improvement_within_its_window.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

commit;

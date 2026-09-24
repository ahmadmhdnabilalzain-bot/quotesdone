-- A HANDOFF WAITING MORE THAN A DAY IS A FINDING, EVEN WHEN ITS PROBLEM IS STILL OPEN.
--
-- Assigned: it_engineer (the handoff_sla duty). Readiness audit, 23 Sep 2026: "25 handoffs are pending at the CEO".
--
-- MEASURED (23 Sep 2026 ~19:40 UTC, production htdblwldjkcgjvmqkbeh), agent_actions kind='handoff' status='pending'
-- addressed to ceo: 24, every one it.finding from it_engineer, and EVERY one already has replied_at. The CEO is
-- not the seat that closes them: the originator closes (fn_it_loop_reverify, "nothing is one-way"). They wait on:
--   22  the finding is still open, so the loop correctly keeps waiting for the fix (smoke failures after
--       c30dcfe, the unsigned revisions, the WhatsApp template watch ...);
--    2  the finding closed but the handoff did not: #49772 (watch:refusal_rate:login_otp) waits on the
--       learning gate (it_incident 288 has no cause/fix/regression_check; the playbook has no class for it),
--       and #85635 closed seconds before the read.
-- fn_it_handoff_sla_items already reported the learning-gate case ("unclosed", 4 h). It said NOTHING about the
-- 22: a replied it.finding whose finding is still open matched no state at all, whatever its age. So a remedy
-- the CEO answered and nobody delivered could sit for ever with no service-level finding. The 22 are each
-- visible as their own finding; what was invisible is that the answer given to them has not worked for a day.
--
-- WHAT THIS CHANGES: fn_it_handoff_sla_items only. One new state, 'open_over_24h': a replied it.finding handoff
-- whose finding is still open and which was handed over more than 24 hours ago. Owner: ceo (the remedy is the
-- CEO's to re-decide). Every existing state, owner and title is unchanged; delivery.request stays the delivery
-- duty's. The body is otherwise byte-for-byte the canonical one in
-- the_company_gets_a_marketing_seat_that_reports_the_picture_to_the_ceo.sql.
--
-- Prevented by: scripts/checks/a_handoff_waiting_more_than_a_day_is_a_finding.test.mjs (runs the routine in an
-- aborted transaction against an invented handoff) and the verdict-row probe below.

create or replace function public.fn_it_handoff_sla_items(p_include_demo boolean default false)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with h as (
    select a.id, a.agent, a.created_at, a.detail->>'type' t, a.detail ? 'replied_at' replied,
           coalesce(k.reply_within, interval '1 hour') w,
           f.closed_at f_closed,
           (f.issue_key is null or f.closed_at is not null
            or f.started_at > (a.detail->>'occurrence_started_at')::timestamptz) cleared
      from public.agent_actions a
      left join public.seat_handoff_kind k
        on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
      left join public.it_engineer_finding f
        on a.detail->>'type' = 'it.finding' and f.issue_key = a.detail->>'issue_key'
     where a.kind = 'handoff' and a.status in ('pending', 'failed')
       and a.detail->>'type' <> 'delivery.request'
       and (p_include_demo or (a.title not ilike '%ZZ DEMO%' and coalesce(a.detail->>'demo', 'false') <> 'true'))
  ), late as (
    select h.*, case
        when not h.replied and now() > h.created_at + h.w then 'unanswered'
        when h.replied and h.t = 'it.finding' and h.cleared
             and now() > greatest(h.created_at, coalesce(h.f_closed, h.created_at)) + h.w then 'unclosed'
        -- ponytail: other originator-closed types get a flat 24 h past their window, because
        -- fn_originators_reverify_handoffs escalates them to the CEO at the window first. Per-type
        -- rules belong in seat_handoff_kind if one of them ever needs a different allowance.
        when h.replied and h.t <> 'it.finding' and now() > h.created_at + h.w + interval '24 hours' then 'unclosed'
        -- 23 Sep 2026: answered, the problem is still there, and a day has gone by.
        when h.replied and h.t = 'it.finding' and not h.cleared and now() > h.created_at + interval '24 hours' then 'open_over_24h'
      end state
      from h)
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', g.t || ':' || g.agent || ':' || g.state,
           'owner_seat', case when g.state = 'unanswered' and g.agent in ('ceo', 'customer_support', 'sales_engineer', 'accountant', 'marketing')
                              then g.agent else 'ceo' end,
           'subject', 'agent_actions',
           'title', g.n || ' ' || g.t || ' handoff(s) to ' || g.agent
                    || case g.state when 'unanswered' then ' have had no reply'
                                    when 'open_over_24h' then ' were answered more than 24 hours ago and the problem is still open'
                       else ' were answered but never closed by the seat that sent them' end
                    || case when g.state = 'open_over_24h' then '' else ' past the ' || g.w || ' window' end
                    || '; the oldest is #' || g.oldest_id || ' from '
                    || to_char(g.oldest_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai',
           'blast', 'agent_facing', 'affected', g.n,
           'evidence', jsonb_build_object('state', g.state, 'type', g.t, 'seat', g.agent, 'reply_within', g.w::text,
                                          'handoff_ids', g.ids, 'oldest_at', g.oldest_at,
                                          'look_at', 'select id, detail, evidence from public.agent_actions where id in (<handoff_ids>)'))
           order by g.t, g.agent, g.state), '[]'::jsonb)
    from (select t, agent, state, min(w) w, count(*) n, min(id) oldest_id, min(created_at) oldest_at,
                 jsonb_agg(id order by id) ids
            from late where state is not null group by t, agent, state) g;
$fn$;
-- CREATE OR REPLACE keeps the ACL; stated again so the file is safe on a database that never had it.
revoke execute on function public.fn_it_handoff_sla_items(boolean) from public, anon, authenticated;

-- PROBE (this file defines a routine, so no raise: it reads, writes nothing, and returns a verdict row).
select case
  when (select count(*) from jsonb_array_elements(public.fn_it_handoff_sla_items()) e
         where e->'evidence'->>'state' = 'open_over_24h'
           and e->>'title' like '%still open%') <> (
        select count(distinct a.agent) from public.agent_actions a
          join public.it_engineer_finding f on f.issue_key = a.detail->>'issue_key'
         where a.kind = 'handoff' and a.status in ('pending', 'failed') and a.detail->>'type' = 'it.finding'
           and a.detail ? 'replied_at' and f.closed_at is null
           and not (f.started_at > (a.detail->>'occurrence_started_at')::timestamptz)
           and a.created_at < now() - interval '24 hours'
           and a.title not ilike '%ZZ DEMO%' and coalesce(a.detail->>'demo', 'false') <> 'true')
    then 'PROBE FAILED: open_over_24h does not name exactly the seats holding a day-old answered, still-open handoff'
  when has_function_privilege('anon', 'public.fn_it_handoff_sla_items(boolean)', 'execute')
    then 'PROBE FAILED: anon can execute fn_it_handoff_sla_items'
  else 'PROBE OK' end as verdict;

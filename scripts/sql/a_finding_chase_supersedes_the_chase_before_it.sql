-- A FINDING CHASE SUPERSEDES THE CHASE BEFORE IT — one live chase per finding occurrence.
--
-- Assigned: it_engineer — the finding chase (seat_duty it_engineer.finding_chase) is its duty.
-- Founder gate, ledger 1162: "no issue in the company wiring" — no duplicate, no orphan handoff.
--
-- MEASURED 7 Oct 2026 01:00 UTC on production (wiring audit, PR body has the full table):
--   387 it.finding handoffs pending; 358 of them on 81 still-open findings, i.e. ~4.4 per finding.
--   Every one of those findings has ONE occurrence (count(distinct occurrence_started_at) = 1), yet
--   e.g. support_reply_sla:email carried 10 pending handoffs to customer_support: the original and
--   @chase4 .. @chase12, one opened per day and none ever closed.
-- CAUSE: fn_it_engineer_finding_chase opens '<issue>@<epoch>@chase<day>' each day. fn_seat_handoff
--   dedupes on the exact target_id, and the day number makes every chase a new target, so each day
--   ADDS a pending handoff for the same unresolved fault. Nothing closes an older chase: the
--   re-verification loop (fn_it_loop_reverify) closes them only when the finding clears.
-- CHANGE: when the chase opens today's handoff it closes, as the originator (it_engineer), every
--   OLDER pending chase for the same finding occurrence, with the verdict 'superseded by chase N'.
--   The original (non-chase) handoff is never touched: it carries the incident, the CEO report and
--   the learning gate. The one-off block below supersedes the backlog the same way.
-- NOT CHANGED: the findings themselves are still open (81 of them) — that is real work for the
--   owning seats, not wiring. The 29 handoffs whose finding cleared but whose incident still lacks
--   cause/fix/regression_check stay waiting at the learning gate (trigger z62); filling that gate
--   with invented text would be fabricating evidence.
-- prevented by: scripts/checks/a_finding_has_one_live_chase.test.mjs

create or replace function public.fn_it_engineer_finding_chase()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare f public.it_engineer_finding; o public.agent_actions; n_chased int := 0; n_opened int := 0; v_day int; v_id bigint;
        v_seats jsonb := '{}'::jsonb; v_old bigint; n_superseded int := 0;
begin
  for f in
    select * from public.it_engineer_finding
     where closed_at is null and started_at < now() - interval '24 hours'
       and issue_key not like 'duty:handoff_sla:%'
       and title not ilike '%ZZ DEMO%' and not coalesce((evidence->>'demo')::boolean, false)
     order by started_at limit 40
  loop
    select * into o from public.agent_actions
     where kind = 'handoff' and detail->>'type' = 'it.finding' and detail->>'from' = 'it_engineer'
       and detail->>'issue_key' = f.issue_key and not coalesce((detail->>'chase')::boolean, false)
     order by id desc limit 1;
    if not found then
      perform public.fn_it_loop_open(f.issue_key);   -- no loop yet: open the ordinary one, owner resolved there
      n_opened := n_opened + 1;
      continue;
    end if;
    v_day := floor(extract(epoch from now() - f.started_at) / 86400)::int;
    v_id := public.fn_seat_handoff('it_engineer', o.agent, 'it.finding', 'it_engineer_finding',
      f.issue_key || '@' || floor(extract(epoch from f.started_at))::bigint || '@chase' || v_day,
      jsonb_build_object(
        'issue_key', f.issue_key, 'occurrence_started_at', f.started_at, 'duty', coalesce(o.detail->>'duty', 'fault'),
        'subject', o.detail->>'subject', 'title', 'Open ' || v_day || ' day(s): ' || f.title, 'where_it_is', f.where_it_is,
        'chase', true, 'age_hours', round(extract(epoch from now() - f.started_at) / 3600),
        'original_handoff_id', o.id, 'finding_severity', public.fn_it_engineer_severity(f.blast, f.affected, f.started_at),
        'escalated_report_id', o.detail->'escalated_report_id'));
    -- ONE LIVE CHASE: the originator closes every older chase of this occurrence (see header).
    perform set_config('qd.handoff_closer', 'it_engineer', true);
    for v_old in
      select a.id from public.agent_actions a
       where a.kind = 'handoff' and a.status = 'pending' and a.id <> v_id
         and a.detail->>'type' = 'it.finding' and a.detail->>'from' = 'it_engineer'
         and coalesce((a.detail->>'chase')::boolean, false)
         and a.detail->>'issue_key' = f.issue_key
         and (a.detail->>'occurrence_started_at')::timestamptz = f.started_at
    loop
      perform public.fn_seat_handoff_complete(v_old, jsonb_build_object(
        'verified_by', 'it_engineer', 'verified_at', now(),
        'verdict', 'superseded by chase day ' || v_day || ' (handoff ' || v_id || '); the finding is still open',
        'superseded_by', v_id));
      n_superseded := n_superseded + 1;
    end loop;
    perform set_config('qd.handoff_closer', '', true);
    n_chased := n_chased + 1;
    v_seats := jsonb_set(v_seats, array[o.agent], to_jsonb(coalesce((v_seats->>o.agent)::int, 0) + 1));
  end loop;
  return jsonb_build_object('chased', n_chased, 'loops_opened', n_opened, 'superseded', n_superseded, 'by_seat', v_seats);
end $fn$;

update public.seat_duty
   set owner_file = 'scripts/sql/a_finding_chase_supersedes_the_chase_before_it.sql'
 where duty = 'it_engineer.finding_chase';

-- ── THE BACKLOG: keep the newest pending chase per occurrence, supersede the rest ────────────────
do $backlog$
declare r record;
begin
  perform set_config('qd.handoff_closer', 'it_engineer', true);
  for r in
    select a.id, k.newest from public.agent_actions a
      join lateral (select max(b.id) newest from public.agent_actions b
                     where b.kind = 'handoff' and b.status = 'pending' and b.detail->>'type' = 'it.finding'
                       and coalesce((b.detail->>'chase')::boolean, false)
                       and b.detail->>'issue_key' = a.detail->>'issue_key'
                       and b.detail->>'occurrence_started_at' = a.detail->>'occurrence_started_at') k on true
     where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'it.finding'
       and a.detail->>'from' = 'it_engineer' and coalesce((a.detail->>'chase')::boolean, false)
       and a.id < k.newest
  loop
    perform public.fn_seat_handoff_complete(r.id, jsonb_build_object(
      'verified_by', 'it_engineer', 'verified_at', now(),
      'verdict', 'superseded by the newer chase (handoff ' || r.newest || '); the finding is still open',
      'superseded_by', r.newest));
  end loop;
  perform set_config('qd.handoff_closer', '', true);
end $backlog$;

-- ── VERDICT ─────────────────────────────────────────────────────────────────────────────────────
select case
  when to_regprocedure('public.fn_it_engineer_finding_chase()') is null then 'PROBE FAILED: the chase routine is missing'
  when has_function_privilege('anon', 'public.fn_it_engineer_finding_chase()', 'execute')
    or has_function_privilege('authenticated', 'public.fn_it_engineer_finding_chase()', 'execute') then 'PROBE FAILED: the chase routine is callable by anon/authenticated'
  when exists (select 1 from public.agent_actions a
                where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'it.finding'
                  and coalesce((a.detail->>'chase')::boolean, false)
                group by a.detail->>'issue_key', a.detail->>'occurrence_started_at' having count(*) > 1)
    then 'PROBE FAILED: a finding occurrence still has more than one pending chase'
  else 'PROBE OK' end as verdict;

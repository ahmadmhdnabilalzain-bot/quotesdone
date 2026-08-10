-- fn_action_queue_sweep has run hourly since it was written and has never resolved one incident.
-- Two defects, both measured on production 10 Aug 2026.
--
-- DEFECT 1 — THE CLEARED-CONDITION GUARD IS GLOBAL, NOT PER-INCIDENT.
--
--     and not exists (select 1 from agent_runs r
--                      where r.status in ('error','failed')
--                        and r.started_at > now() - interval '48 hours')
--
-- That asks "has ANYTHING in the entire company failed in the last 48 hours?" In an estate with
-- 66 employees and ~90 cron jobs something always has — right now six, from resilience_watch and
-- match_eval, both already closed causes. So the branch is unreachable and the auto-resolve has
-- never fired once. Nine incidents older than 48 hours, every one matching the regex, sit open
-- with the oldest from 4 August.
--
-- DEFECT 2 — DEDUPE PARTITIONS ON A TITLE THAT CARRIES A CHANGING COUNT.
-- The keep-newest rule partitions by (agent, kind, title), and these titles are
--   "4 agent run(s) failed in last 24h" · "6 agent run(s) failed in last 24h" · "10 agent run(s)…"
-- Every day's count makes a NEW unique title, so no two are ever duplicates and `it` accumulates
-- one per day for ever. Same shape in autonomy_stall: "1 department loop(s) have stalled".
--
-- THE FIX. Dedupe on a title with a LEADING COUNT normalised away, which is exactly the pattern
-- that varies, and nothing else — "4 agent run(s) failed…" and "10 agent run(s) failed…" collapse,
-- while "Supplier 12 failed audit" and "Supplier 45 failed audit" stay distinct because their
-- digits are not leading. Then judge staleness on the window the incident ITSELF names (24h)
-- rather than on whether the whole company is quiet, because a point-in-time observation from
-- 4 August is not kept true or false by what fails today — and if the condition is still live,
-- a newer incident exists and survives dedupe to carry it.
create or replace function public.fn_action_queue_sweep()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_catalog'
as $function$
declare v_dupes int := 0; v_cleared int := 0;
begin
  -- 1. DUPLICATES. Keep the newest of each (agent, kind, normalised title); supersede the rest.
  --    A leading integer is a COUNT, not an identity: "4 agent run(s) failed in last 24h" and
  --    "10 agent run(s) failed in last 24h" are the same recurring incident reported twice.
  with ranked as (
    select id, agent, kind,
           regexp_replace(title, '^[0-9]+\s+', 'N ') as norm_title,
           first_value(id) over (partition by agent, kind, regexp_replace(title, '^[0-9]+\s+', 'N ')
                                 order by created_at desc) keep_id,
           row_number() over (partition by agent, kind, regexp_replace(title, '^[0-9]+\s+', 'N ')
                              order by created_at desc) rn
      from public.agent_actions
     where status in ('pending','needs_review')
  ), dupes as (select id, keep_id from ranked where rn > 1)
  update public.agent_actions a
     set status = 'superseded',
         decided_by = 'action_queue_sweep',
         decided_at = now(),
         detail = coalesce(a.detail, '{}'::jsonb)
                  || jsonb_build_object('superseded_by', d.keep_id, 'swept_at', now(),
                                        'reason', 'same agent/kind and same title once a leading count is normalised')
    from dupes d where a.id = d.id;
  get diagnostics v_dupes = row_count;

  -- 2. STALE INCIDENTS whose condition has cleared. An incident naming failed runs is a
  --    POINT-IN-TIME observation over its own 24-hour window. Older than 48 hours it is either
  --    already superseded by a newer one above, or nothing has failed in the window it names.
  --    The old global "has anything failed anywhere in 48h" guard is gone: it made this branch
  --    unreachable in any estate that is actually running.
  update public.agent_actions a
     set status = 'auto_resolved',
         decided_by = 'action_queue_sweep',
         decided_at = now(),
         detail = coalesce(a.detail, '{}'::jsonb)
                  || jsonb_build_object('auto_resolved_at', now(),
                                        'reason', 'point-in-time run-failure incident older than 48h; '
                                               || 'any still-live failure is carried by a newer incident')
   where a.status in ('pending','needs_review')
     and a.kind = 'incident'
     and a.created_at < now() - interval '48 hours'
     and a.title ~* 'run\(s\) failed';
  get diagnostics v_cleared = row_count;

  if v_dupes + v_cleared > 0 then
    insert into public.founder_alerts(level, event, detail, channel)
      values ('info', 'Action queue swept',
              v_dupes || ' duplicate(s) superseded and ' || v_cleared
              || ' stale incident(s) auto-resolved. Handoffs, legal flags, customer escalations and '
              || 'recommendations were left untouched — those need you.', 'os');
  end if;

  return jsonb_build_object('superseded', v_dupes, 'auto_resolved', v_cleared,
    'still_open', (select count(*) from public.agent_actions where status in ('pending','needs_review')),
    'ran_at', now());
end $function$;

-- CREATE OR REPLACE preserves the ACL; revoked explicitly so the intent lives in the migration.
revoke execute on function public.fn_action_queue_sweep() from public, anon, authenticated;

-- AN OPEN PULL REQUEST NOBODY HAS TOUCHED FOR TWO DAYS IS A FINDING, AND THE FOUNDER HEARS OF IT AFTER A WEEK.
-- Seat: it_engineer (IT duty 25, daily). 10 Nov 2026, task from the founder's session after the audit below.
--
-- MEASURED 10 Nov 2026: 15 pull requests opened by Claude sessions between about 20 Oct and 9 Nov were left open and
--   unmerged, and nobody noticed for days. Some carried SQL that was never applied, and founder rulings of 5-9 Nov were
--   never written to public.founder_instruction. They were found by hand. Nothing watched the open pull requests.
--   (Today GitHub lists 10 open, 7 of them dependabot's; see the report that came with this file.)
--
-- WHAT THIS CHANGES, reusing the machinery that exists (no parallel one):
--   1. it_duty_schedule 'open_pull_requests', once a day, owner it_engineer. The heartbeat step of the same name
--      (resilience_ping ticks/it_engineer/later_duties.ts) is due-gated by fn_it_scheduled_due like the other duties.
--   2. The READ is the GitHub path fn_it_change_watch already uses: edge function code with app_secrets.github_token,
--      takeOpenPullRequests in _shared/it_duty_readings.ts. The DECISION (dependabot excluded, more than 48 hours idle,
--      does the diff touch scripts/sql) is the pure _shared/stale_pull_requests.ts with Deno tests. Postgres cannot reach
--      GitHub, so this file only records what the reading decided.
--   3. fn_it_open_pull_requests_record(p) settles the duty through fn_it_duty_settle, the same call every IT duty makes:
--      ONE finding per stale pull request, 'duty:open_pull_requests:pr:<number>', owner it_engineer, naming its number,
--      title, age and idle time and whether SQL is waiting. It closes by itself the next run after the pull request is
--      merged or closed (it is no longer in the reading), or gets a commit (it is no longer idle). A reading that could
--      not be taken in full (no token, GitHub down, a page missing) is NOT settled: open findings stay as they were and
--      the duty is asked again on the next tick, so "could not look" never reads as "all clear".
--   4. fn_it_session_fix_list (the founder's one daily list, the_founder_gets_one_daily_list_of_what_a_session_must_fix.sql)
--      gains ONE line: how many pull requests have been open more than 7 days (it_threshold 'pr_founder_days'), by number,
--      and how many carry SQL. Younger ones stay on the IT engineer's own board; the founder is told only after a week.
--      The rest of that function is copied from its canonical body unchanged. CREATE OR REPLACE keeps its ACL.
--
-- AGE. "Idle" is 48 hours with no commit or update, read from GitHub's updated_at (it moves on a push, a comment, a review
--   and a label). "Older than 7 days" is the pull request's own age since it was opened (created_at). A draft counts.
--
-- NOT CHANGED, ON PURPOSE: this raises and closes findings; it never merges, closes, comments on or rebases a pull
--   request, and applies no SQL. It cannot know whether a stale pull request is abandoned or waiting, only that nobody has
--   looked at it. The founder rulings of 5-9 Nov missing from founder_instruction are a separate gap (a conduct rule,
--   quotesdone-organised-like-an-auditor-will-read-it section 1), not something this duty can read.
--
-- PAUSE: insert into public.duty_pause (duty, reason, paused_by) values ('resilience_ping.open_pull_requests', '<why>', '<seat>');
-- Pending: scripts/sql/pending/an_open_pull_request_nobody_touched_for_two_days_is_a_finding.txt
-- Proved by: scripts/sql/an_open_pull_request_nobody_touched_for_two_days_is_a_finding_probe.sql (ZZ DEMO pull requests,
--   numbers 900001 and up; a pure probe that ends in raise exception, so the whole replay rolls back).
-- Prevented by: scripts/checks/an_open_pull_request_nobody_touched_for_two_days_is_a_finding.test.mjs (schedule, thresholds,
--   what is raised and closed, the founder's seven days) and supabase/functions/_shared/stale_pull_requests.test.ts.
-- Idempotent, no begin/commit.
--   node scripts/apply_sql.mjs scripts/sql/an_open_pull_request_nobody_touched_for_two_days_is_a_finding.sql --apply --ddl --seat it_engineer

-- 1. THE SCHEDULE AND THE ONE THRESHOLD POSTGRES OWNS
-- (the 48 hours belong to the pure decision in stale_pull_requests.ts, STALE_PR_HOURS; this is the founder's seven days)
insert into public.it_duty_schedule (duty, every, note, owner_seat) values
  ('open_pull_requests', interval '1 day',
   'open pull requests (not dependabot) idle more than 48 hours: one finding each, closed when merged or closed; the founder''s list names those open more than 7 days (fn_it_open_pull_requests_record)', 'it_engineer')
on conflict (duty) do update set every = excluded.every, note = excluded.note, owner_seat = excluded.owner_seat;

insert into public.it_threshold (key, value, unit, basis) values
  ('pr_founder_days', 7, 'days', 'An open pull request this old (since it was opened) is named on the founder''s daily list of what a session must fix. 10 Nov 2026: 15 session pull requests sat open up to three weeks unnoticed.')
on conflict (key) do update set value = excluded.value, unit = excluded.unit, basis = excluded.basis;

-- 2. THE RECORD: ONE FINDING PER STALE PULL REQUEST
-- p: what takeOpenPullRequests returns: {basis: 'measured', taken_at, open_count, stale: [{number, title, url, author, draft,
--    created_at, updated_at, age_hours, idle_hours, touches_sql (true/false/null), sql_files}]} or {basis: 'unavailable', reason}.
create or replace function public.fn_it_open_pull_requests_record(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  x jsonb; v_items jsonb := '[]'::jsonb; v_res jsonb; v_idle numeric; v_age numeric; v_sql text; v_n int := 0;
begin
  if jsonb_typeof(p) is distinct from 'object' then
    raise exception 'fn_it_open_pull_requests_record takes the object takeOpenPullRequests returns';
  end if;
  -- "could not look" is not "all clear": nothing is settled, nothing closes, and the duty stays due.
  if p->>'basis' is distinct from 'measured' or jsonb_typeof(p->'stale') is distinct from 'array' then
    return jsonb_build_object('recorded', false, 'reason', coalesce(p->>'reason', 'no measured reading'));
  end if;

  for x in select e from jsonb_array_elements(p->'stale') e loop
    continue when (x->>'number') is null or (x->>'number') !~ '^[0-9]+$';
    v_idle := coalesce((x->>'idle_hours')::numeric, 0);
    v_age  := coalesce((x->>'age_hours')::numeric, 0);
    v_sql  := x->>'touches_sql';
    v_n := v_n + 1;
    v_items := v_items || jsonb_build_object(
      'item', 'pr:' || (x->>'number'), 'owner_seat', 'it_engineer', 'subject', 'pull request #' || (x->>'number'),
      'blast', 'internal', 'affected', 1,
      'title', 'Pull request #' || (x->>'number') || ' "' || public.fn_trim_at_word(coalesce(x->>'title', ''), 120) || '" has had no commit or update for '
               || case when v_idle >= 48 then trim_scale(round(v_idle / 24, 1)) || ' days' else round(v_idle) || ' hours' end
               || ' (open ' || case when v_age >= 48 then trim_scale(round(v_age / 24, 1)) || ' days' else round(v_age) || ' hours' end || ')'
               || case v_sql when 'true' then '; its diff touches scripts/sql, so SQL is waiting to be applied'
                             when 'false' then '; its diff does not touch scripts/sql'
                             else '; its files could not be read, so whether SQL is waiting is unknown' end,
      'evidence', jsonb_build_object('number', (x->>'number')::int, 'title', x->>'title', 'url', x->>'url', 'author', x->>'author',
        'draft', coalesce((x->>'draft')::boolean, false), 'created_at', x->>'created_at', 'updated_at', x->>'updated_at',
        'age_hours', v_age, 'idle_hours', v_idle, 'touches_sql', case v_sql when 'true' then true when 'false' then false else null end,
        'sql_files', coalesce(x->'sql_files', '[]'::jsonb), 'open_count', p->'open_count', 'read_at', p->>'taken_at',
        'close', 'Merge it, close it, or push to it: this finding closes by itself on the next daily run. Never apply its SQL from the branch (an_apply_from_an_open_pull_request_waits_for_its_merge.sql).'));
  end loop;

  v_res := jsonb_build_object('stale', v_n, 'open', p->'open_count', 'settle', public.fn_it_duty_settle('open_pull_requests', v_items));
  perform public.fn_it_duty_ran('open_pull_requests', v_res);
  return v_res || jsonb_build_object('closed', v_res->'settle'->'closed');
end $fn$;
revoke execute on function public.fn_it_open_pull_requests_record(jsonb) from public, anon, authenticated;
grant execute on function public.fn_it_open_pull_requests_record(jsonb) to service_role;

-- 3. THE FOUNDER'S DAILY LIST GAINS ONE LINE (branch 5); every other branch is the canonical body of 10 Nov 2026
create or replace function public.fn_it_session_fix_list()
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb := '[]'::jsonb;
begin
  with words as (
    -- 1. a duty failing run after run is a defect a session fixes
    select 1 as rank, d.failures::int as n,
           'The ' || replace(split_part(d.duty, '.', 2), '_', ' ') || ' duty of the ' || replace(d.owner_seat, '_', ' ') || ' seat has failed '
             || d.failures || ' runs in a row: ' || public.fn_trim_at_word(replace(regexp_replace(coalesce(d.last_error, 'no error recorded'), '\s+', ' ', 'g'), '_', ' '), 140) as line
      from public.seat_duty d where d.enabled and coalesce(d.failures, 0) >= 3
    union all
    -- 2. a safe-fix playbook that stopped after two failed runs
    select 2, 1, 'The ' || replace(f.family, '_', ' ') || ' playbook stopped itself: ' || public.fn_trim_at_word(replace(coalesce(f.parked_reason, 'two failed runs'), '_', ' '), 140)
      from public.it_safe_fix_family f where not f.active and f.parked_at is not null
    union all
    -- 3. what a playbook refused to touch in the last day, by family
    select 3, count(*)::int, 'The ' || replace(r.family, '_', ' ') || ' playbook could not act on ' || count(*) || ' item(s): '
             || public.fn_trim_at_word(replace(coalesce(max(coalesce(r.result->>'why', r.result->'refused'->0->>'why')), 'its guardrail refused'), '_', ' '), 140)
      from public.it_safe_fix_run r where r.outcome = 'refused_by_guardrail' and r.ran_at > now() - interval '26 hours'
     group by r.family
    union all
    -- 5. pull requests open more than 7 days (10 Nov 2026, duty open_pull_requests): ONE line, numbers only (no title, so
    --    no internal word reaches him). Age is the pull request's own, from the finding's evidence; the threshold is
    --    it_threshold 'pr_founder_days'. Each one's finding closes by itself the day it is merged or closed.
    select 1, count(*)::int,
           count(*) || ' pull request(s) have been open for more than ' || public.fn_it_threshold('pr_founder_days')::int
             || ' days without a merge: ' || string_agg('#' || (f.evidence->>'number'), ', ' order by (f.evidence->>'created_at')::timestamptz)
             || case when count(*) filter (where f.evidence->>'touches_sql' = 'true') > 0
                     then ' (' || count(*) filter (where f.evidence->>'touches_sql' = 'true') || ' carry SQL that was never applied)' else '' end
      from public.it_engineer_finding f
     where f.closed_at is null and f.issue_key like 'duty:open\_pull\_requests:pr:%'
       and (f.evidence->>'created_at')::timestamptz < now() - make_interval(days => public.fn_it_threshold('pr_founder_days')::int)
    having count(*) > 0
    union all
    -- 4. questions the model could not answer by their deadline, a person-facing one first
    select case when public.fn_held_question_is_person_facing(q.surface) then 0 else 4 end, count(*)::int,
           count(*) || ' question(s) for the ' || replace(a.agent, '_', ' ') || ' seat on ' || replace(replace(coalesce(q.surface, 'an unknown surface'), '_', ' '), '.', ': ')
             || ' were not answered by their deadline'
             || case when public.fn_held_question_is_person_facing(q.surface) then ' (a person is waiting for the answer)' else '' end
      from public.agent_actions a left join public.reasoning_held_question q on q.id = (a.detail->>'held_id')::bigint
     where a.kind = 'held_question' and a.status = 'pending' and a.detail ? 'overdue_at'
     group by a.agent, q.surface, public.fn_held_question_is_person_facing(q.surface))
  select coalesce(jsonb_agg(jsonb_build_object('rank', rn, 'line', line, 'count', n) order by rn), '[]'::jsonb) into v
    from (select line, n, row_number() over (order by rank, n desc, line) rn from words) z where rn <= 12;
  return v;
end $fn$;
revoke execute on function public.fn_it_session_fix_list() from public, anon, authenticated;

-- ── VERDICT (read-only) ─────────────────────────────────────────────────────────────────────────────────────────
select case when problems is null then 'PROBE OK' else 'PROBE FAILED: ' || problems end as verdict from (
  select string_agg(p, '; ') problems from (
    select 'a routine is open or unpinned: ' || p.oid::regprocedure::text p from pg_proc p
     where p.oid in ('public.fn_it_open_pull_requests_record(jsonb)'::regprocedure, 'public.fn_it_session_fix_list()'::regprocedure)
       and (not p.prosecdef or not coalesce(p.proconfig @> array['search_path=public, pg_temp'], false)
            or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
    union all select 'the schedule is not daily for it_engineer' where not exists (
      select 1 from public.it_duty_schedule where duty = 'open_pull_requests' and every = interval '1 day' and owner_seat = 'it_engineer')
    union all select 'the founder threshold is not 7 days' where coalesce((select value from public.it_threshold where key = 'pr_founder_days'), 0) <> 7
    union all select 'the list lost a branch: ' || m from unnest(array['fn_held_question_is_person_facing', 'it_safe_fix_family', 'seat_duty d']) m
     where position(m in (select prosrc from pg_proc where oid = 'public.fn_it_session_fix_list()'::regprocedure)) = 0
    union all select 'the list has a line with an internal key: ' || (x->>'line') from jsonb_array_elements(public.fn_it_session_fix_list()) x
     where x->>'line' ~ 'duty:|[a-z]+_[a-z]+_[a-z]+'
  ) z) y;

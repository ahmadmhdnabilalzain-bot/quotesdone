-- ROW #3, LAYER 5 — the weekly executive meeting runs, and produces almost none of what a meeting is.
-- 
-- ── MEASURED ON PRODUCTION, 9 AUG 2026, BEFORE A LINE OF THIS WAS WRITTEN ───────────────────────
--   exec-meeting-weekly-autostart    MET      exec_meeting_weekly (0 5 * * 1), last ok 2026-08-03
--   exec-meeting-ten-participants    MET      10 of 10 operating systems contributed
--   exec-meeting-agenda-six          MISSING  0 of 6 sections on all 12 contributions
--   exec-meeting-debate              MISSING  fn_exec_meeting invokes fn_challenge: false; 0 recorded
--   exec-meeting-priorities-agreed   MISSING  0 of 4 meetings end with a ranked/owned list
--   exec-meeting-replayable          MISSING  0 reachable routines emit the findings body
-- 
-- The contributions carry item/owner/health/finding/drivers and nothing else, the recommendations
-- are an array of two prose STRINGS, and no challenge is recorded anywhere near the meeting.
-- 
-- ── WHAT THIS CHANGES, AND WHERE EVERY VALUE COMES FROM ─────────────────────────────────────────
-- Six sections on every contribution, each one a count over live rows plus the top three by name.
-- Nothing here is invented and nothing is a placeholder: a section with no rows says so, with the
-- count, because "0 open risks on the register" is a finding a meeting is entitled to hear.
-- 
--   wins           org_tasks closed in the last 7 days for the owner's department
--   problems       the os_review findings for that OS this period
--   kpis           the live per-OS figures already gathered for `drivers`
--   risks          risk_register rows for the department that are not closed
--   opportunities  opportunity rows detected by someone in that department, + the company total
--   requests       org_tasks needing a founder decision in that department
-- 
-- The three company-level items (Revenue, Supplier coverage, Platform availability) get the same
-- six scoped to the company, merged in afterwards rather than typed into each of the three — so
-- any item added later inherits them instead of silently arriving with four sections.
-- 
-- ── ALL TEN PARTICIPATE, NOT ONLY THE ONES IN TROUBLE ───────────────────────────────────────────
-- The loop was `where r2.health <> 'green'`. ten-participants passes today only because all ten
-- happen to be amber this week — the first OS to go green would have dropped out of its own
-- meeting and taken a passing check with it. A green OS reporting green IS participation, so the
-- filter moves off the agenda and onto the two things that genuinely only concern trouble: the
-- org_tasks that get raised, and the priority list.
-- 
-- ── THE DEBATE IS THE PRIORITY ORDER, PUT TO ANOTHER OFFICER ────────────────────────────────────
-- fn_challenge is the company's existing adversary: it matches the proposal against
-- challenge_heuristic, reads institutional_memory for a prior outcome, and returns support /
-- concern / recommend_against with its reasoning. The top three priorities are put to the first
-- officer in the list who is not the one proposing — that is the "each other" the spec asks for,
-- and three per week is a debate rather than thirteen rows of boilerplate.
-- 
-- It is wrapped in its own exception block. A challenge that throws must not fail the meeting: the
-- meeting's own cron success is what exec-meeting-weekly-autostart measures, and this change must
-- not be able to take a passing check down with it. The count of challenges that actually landed
-- goes into the agent_runs note, so a swallowed failure is visible instead of silent.
-- 
-- ── PRIORITIES BECOME OBJECTS, RANKED AND OWNED ─────────────────────────────────────────────────
-- `recs` was ['<sentence>', '<sentence>']. It becomes one object per non-green contribution with
-- rank, owner, priority and title, ordered red before amber and then by OS number. `title` is
-- deliberate: fn_report_recommendation_approve already reads `v_rec ->> 'title'` and falls back to
-- the raw text, so the founder's approve button gets a real title instead of 160 characters of JSON.
-- 
-- THIS DOES NOT MAKE priorities-agreed FLIP TODAY. That check is a universal over every ceo
-- exec_report in 60 days, and three of the four in the window were written on 28 Jul and 3 Aug with
-- string recommendations. Rewriting those rows would be editing the record to turn a gate green,
-- so they are left alone; the check flips when they age out of the window.
-- 
-- ── HOW IT IS APPLIED ───────────────────────────────────────────────────────────────────────────
-- fn_exec_meeting is 6,523 characters. It is read from the live database and patched at anchors
-- that are each asserted to appear EXACTLY ONCE, so every line this change does not touch stays
-- byte-identical to what is running. Same discipline as gen_os_health_reaches_the_exec_meeting.mjs.

-- ROUTINE REMOVED 7 September 2026. public.fn_exec_meeting was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


CREATE OR REPLACE FUNCTION public.fn_ws_reports()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', (select to_jsonb(k) from public.report_kpis k),
    -- THE LATEST EXECUTIVE MEETING, IN SEQUENCE. exec_reports.findings is the ordered transcript of
    -- what each of the ten officers said; report_registry projects only title/period/id, so until
    -- now the body reached nothing the browser could run. `contributions` keeps the array order
    -- the meeting wrote it in — that order IS the replay.
    'meeting', (select jsonb_build_object(
        'id', r.id, 'period', r.period, 'officer', r.officer, 'summary', r.summary,
        'at', to_char(r.created_at,'YYYY-MM-DD HH24:MI'),
        'contributions', coalesce(r.findings, '[]'::jsonb),
        'priorities', coalesce(r.recommendations, '[]'::jsonb),
        'challenges', (select coalesce(jsonb_agg(jsonb_build_object(
              'proposal', c.proposal, 'by', c.challenged_by, 'of', c.proposed_by,
              'stance', c.stance, 'confidence', c.confidence, 'reasoning', c.reasoning,
              'alternatives', c.alternatives) order by c.id), '[]'::jsonb)
            from public.challenge_record c
           where c.created_at between r.created_at - interval '30 minutes'
                                  and r.created_at + interval '6 hours'))
      from public.exec_reports r where r.officer='ceo' order by r.created_at desc limit 1),
    'freshness', (select jsonb_build_object(
        'daily', daily_fresh, 'weekly', weekly_fresh, 'monthly', monthly_fresh, 'quarterly', quarterly_fresh,
        'department', department_fresh, 'supplier', supplier_fresh, 'customer', customer_fresh, 'ai', ai_fresh
      ) from public.report_kpis),
    'recent', (select coalesce(jsonb_agg(r), '[]'::jsonb) from (
        select id, source, report_type, title, period,
               case source when 'exec' then 'exec' when 'narrative' then 'board' else source end as src,
               to_char(created_at,'YYYY-MM-DD HH24:MI') as created
        from public.report_registry order by created_at desc limit 25) r),
    'by_type', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
        select report_type, id, title,
               case source when 'exec' then 'exec' when 'narrative' then 'board' else source end as src,
               to_char(created_at,'YYYY-MM-DD HH24:MI') as created
        from (
          select distinct on (report_type) report_type, id, source, title, created_at
          from public.report_registry order by report_type, created_at desc
        ) x order by report_type) t),
    'flags', (select coalesce(jsonb_agg(f), '[]'::jsonb) from (
        select title, risk, status, to_char(created_at,'YYYY-MM-DD') as created
        from public.agent_actions
        where agent='reporting_ai' and kind='report_task' and status in ('pending','needs_review')
        order by created_at desc) f)
  );
$function$
;

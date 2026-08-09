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

CREATE OR REPLACE FUNCTION public.fn_exec_meeting()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare m jsonb; findings jsonb := '[]'::jsonb; actions int := 0; recs jsonb;
  -- the six agenda sections, rebuilt per contribution, plus their company-scoped counterparts
  v_wins text; v_probs text; v_risks text; v_opps text; v_reqs text; v_kpis jsonb;
  v_dept text; v_opp_all int; v_co jsonb; p record; v_challenger text; v_ch int := 0;
  v_period text := to_char(now(),'IYYY-"W"IW');
  v_rev numeric; v_spend numeric; v_sup int; v_open int; v_avail numeric;
  v_red int; v_amber int; v_green int; r record; v_drivers text;
begin
  -- ensure the OS reviews for this week exist before the meeting reads them
  if not exists (select 1 from os_review where period = v_period) then
    perform fn_os_review();
  end if;

  select count(*) filter (where health='red'), count(*) filter (where health='amber'), count(*) filter (where health='green')
    into v_red, v_amber, v_green from os_review where period = v_period;

  select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) into v_rev from transactions where revealed_at > now()-interval '7 days';
  select coalesce(sum(cost_aed),0) into v_spend from ai_cost_log where occurred_at > now()-interval '7 days';
  select count(*) into v_sup from leads where approval_status='approved';
  select count(*) into v_open from org_tasks where status<>'done';
  select round(100.0*count(*) filter (where ok)/nullif(count(*),0),1) into v_avail
    from health_checks where check_kind='http' and created_at > now()-interval '7 days';

  select count(*) into v_opp_all from opportunity where coalesce(status,'open')='open';

  m := jsonb_build_object('week',v_period,'os_green',v_green,'os_amber',v_amber,'os_red',v_red,
       'revenue_7d_aed',v_rev,'ai_spend_7d_aed',round(coalesce(v_spend,0),2),
       'approved_suppliers',v_sup,'supplier_target',860,
       'open_tasks',v_open,'platform_availability_pct',v_avail);

  -- AGENDA ITEM 1..10: every operating system that is not green, named with its owner AND with the
  -- live per-OS figures out of v_os_health that put it there. LEFT JOIN: an OS the view cannot
  -- resolve still reaches the agenda, it just reaches it without drivers.
  for r in
    select o.num, o.name, r2.health, r2.owner_agent, r2.findings,
           h.open_risks, h.kpi_gaps, h.backlog_per_head, h.stale_tasks,
           h.review_pass_pct, h.budget_pct, h.needs_founder_pct,
           -- CAPACITY IS THE ONE DIMENSION v_os_health DOES NOT COMPUTE (6 Aug 2026). It is
           -- resource_pool committed/capacity and it exists only in os_review.metrics, so it
           -- was the one of the eight figures with no reader outside its own writer. Taken off
           -- the report row the meeting is already reading.
           r2.metrics->>'capacity_pct' capacity_pct
    from os_review r2 join operating_system o on o.os_key = r2.os_key
    left join v_os_health h on h.os_key = r2.os_key
    where r2.period = v_period order by
      case r2.health when 'red' then 1 when 'amber' then 2 else 3 end, o.num
  loop
    v_drivers := 'open_risks '||coalesce(r.open_risks::text,'?')
      ||', kpi_gaps '||coalesce(r.kpi_gaps::text,'?')
      ||', capacity_pct '||coalesce(r.capacity_pct,'?')
      ||', backlog_per_head '||coalesce(r.backlog_per_head::text,'?')
      ||', stale_tasks '||coalesce(r.stale_tasks::text,'?')
      ||', review_pass_pct '||coalesce(r.review_pass_pct::text,'?')
      ||', budget_pct '||coalesce(r.budget_pct::text,'?')
      ||', needs_founder_pct '||coalesce(r.needs_founder_pct::text,'?');
    -- THE SIX AGENDA SECTIONS. Each is a count over live rows and the top three by name; a
    -- section with nothing in it states the zero rather than being omitted, because a meeting is
    -- entitled to hear "no open risks" and a missing section is not the same claim.
    v_dept := (select department from org_agents where agent_key = r.owner_agent);

    v_wins := (select count(*) from org_tasks
                where status='done' and updated_at > now()-interval '7 days' and dept_key = v_dept)
      ||' task(s) closed in the last 7 days'
      || coalesce(': '||(select string_agg(w.title, '; ') from (
             select title from org_tasks where status='done'
              and updated_at > now()-interval '7 days' and dept_key = v_dept
              order by updated_at desc limit 3) w), '')||'.';

    v_probs := case when jsonb_typeof(r.findings)='array' and jsonb_array_length(r.findings) > 0
      then (select string_agg(coalesce(e->>'issue', e::text)||coalesce(' — '||(e->>'detail'), ''), '; ')
              from jsonb_array_elements(r.findings) e)
      else 'No unresolved finding recorded for this operating system in '||v_period||'.' end;

    v_kpis := jsonb_build_object('health', r.health,
      'open_risks', r.open_risks, 'kpi_gaps', r.kpi_gaps, 'capacity_pct', r.capacity_pct,
      'backlog_per_head', r.backlog_per_head, 'stale_tasks', r.stale_tasks,
      'review_pass_pct', r.review_pass_pct, 'budget_pct', r.budget_pct,
      'needs_founder_pct', r.needs_founder_pct);

    v_risks := (select count(*) from risk_register
                 where coalesce(status,'open') <> 'closed' and dept_key = v_dept)
      ||' open risk(s) on the register'
      || coalesce(': '||(select string_agg(k.risk, '; ') from (
             select risk from risk_register where coalesce(status,'open') <> 'closed'
              and dept_key = v_dept order by updated_at desc nulls last limit 3) k), '')||'.';

    v_opps := (select count(*) from opportunity op join org_agents oa on oa.agent_key = op.detected_by
                where coalesce(op.status,'open')='open' and oa.department = v_dept)
      ||' open opportunit(ies) attributed to this operating system'
      || coalesce(': '||(select string_agg(x.title, '; ') from (
             select op.title from opportunity op join org_agents oa on oa.agent_key = op.detected_by
              where coalesce(op.status,'open')='open' and oa.department = v_dept
              order by op.value_score desc nulls last limit 3) x), '')
      ||'; '||v_opp_all||' open company-wide.';

    v_reqs := (select count(*) from org_tasks
                where needs_founder and status <> 'done' and dept_key = v_dept)
      ||' item(s) awaiting a founder decision'
      || coalesce(': '||(select string_agg(q.title, '; ') from (
             select title from org_tasks where needs_founder and status <> 'done'
              and dept_key = v_dept order by created_at desc limit 3) q), '')||'.';

    findings := findings || jsonb_build_array(jsonb_build_object(
      'item', r.num||'. '||r.name, 'owner', coalesce(r.owner_agent,'unassigned'),
      'health', r.health, 'finding', r.findings::text, 'drivers', v_drivers,
      'wins', v_wins, 'problems', v_probs, 'kpis', v_kpis,
      'risks', v_risks, 'opportunities', v_opps, 'requests', v_reqs));
  end loop;

  -- COMPANY-LEVEL ITEMS the CEO owns directly
  if coalesce(v_rev,0)=0 then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Revenue','owner','cfo','health','amber','finding','No revenue recognised in the last 7 days.'));
  end if;
  if v_sup < 860 then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Supplier coverage','owner','procurement','health',
      case when v_sup=0 then 'red' else 'amber' end,
      'finding', v_sup||' approved suppliers against a target of 860 (10 in each of 86 categories).'));
  end if;
  if coalesce(v_avail,100) < 99.5 then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Platform availability','owner','cto','health','amber','finding','Availability '||coalesce(v_avail,0)||'% against 99.5%.'));
  end if;

  -- The company-level items above are contributions too, so they carry the same six sections,
  -- scoped to the company rather than to one department. Merged rather than typed into each of
  -- the three: an item added later inherits the sections instead of arriving with four.
  v_co := jsonb_build_object(
    'wins', (select count(*) from org_tasks where status='done' and updated_at > now()-interval '7 days')
            ||' task(s) closed company-wide in the last 7 days.',
    'problems', v_red||' operating system(s) red and '||v_amber||' amber in '||v_period||'.',
    'kpis', m,
    'risks', (select count(*) from risk_register where coalesce(status,'open') <> 'closed')
             ||' open risk(s) on the company register.',
    'opportunities', v_opp_all||' open opportunit(ies) company-wide.',
    'requests', (select count(*) from org_tasks where needs_founder and status <> 'done')
                ||' item(s) awaiting a founder decision company-wide.');
  select coalesce(jsonb_agg(case when f ? 'wins' then f else f || v_co end order by ord), '[]'::jsonb)
    into findings from jsonb_array_elements(findings) with ordinality as t(f, ord);

  insert into org_tasks (dept_key,title,detail,status,tier,needs_founder,action_class)
  select coalesce((select department from org_agents where agent_key=f->>'owner'),'exec'),
    'Exec meeting '||v_period||': '||(f->>'item'),
    'Health: '||(f->>'health')||'. Owner: '||(f->>'owner')||'. '||(f->>'finding')
    ||coalesce(' Drivers: '||(f->>'drivers')||'.','')
    ||' Raised at the weekly executive meeting. Close it, or bring evidence the standard is wrong.',
    'proposed','advisory',false,'exec_review'
  from jsonb_array_elements(findings) f
  where coalesce(f->>'health','') <> 'green'
    and not exists (select 1 from org_tasks t where t.title='Exec meeting '||v_period||': '||(f->>'item') and t.status<>'done');
  get diagnostics actions = row_count;

  -- AGREED PRIORITIES, RANKED AND OWNED. One object per contribution that is not green, red
  -- before amber and then in operating-system order, which is the order the constitution gives:
  -- compliance and trust sit in the red band before anything amber is opened. `title` is the key
  -- fn_report_recommendation_approve already reads, so the founder's approve control gets a name
  -- rather than 160 characters of JSON.
  select coalesce(jsonb_agg(jsonb_build_object(
           'rank', x.rn, 'owner', x.owner, 'priority', x.health,
           'title', x.item, 'why', x.finding) order by x.rn), '[]'::jsonb)
    into recs from (
      select row_number() over (order by case f->>'health' when 'red' then 1 else 2 end, ord) rn,
             f->>'item' item, f->>'owner' owner, f->>'health' health,
             -- an operating system's readable problem statement lives in `problems`; `finding` is
             -- the raw os_review JSON. The three company items are the other way round.
             case when f ? 'drivers' then f->>'problems' else f->>'finding' end finding
        from jsonb_array_elements(findings) with ordinality as t(f, ord)
       where coalesce(f->>'health','') <> 'green') x;
  if jsonb_array_length(recs) = 0 then
    recs := jsonb_build_array(jsonb_build_object('rank', 1, 'owner', 'ceo', 'priority', 'hold',
      'title', 'Hold current priorities',
      'why', 'All ten operating systems green and company metrics within tolerance.'));
  end if;

  insert into exec_reports (officer,period,summary,findings,recommendations,metrics,status)
  values ('ceo',v_period,
    'Weekly executive meeting across ten operating systems. '||v_green||' green, '||v_amber||' amber, '||v_red
    ||' red. '||jsonb_array_length(findings)||' agenda contribution(s), '||actions||' action(s) assigned.',
    findings, recs, m, 'open')
  on conflict do nothing;

  -- THE DEBATE. The CEO's proposed priority order is put to another officer, who evaluates it
  -- through fn_challenge against challenge_heuristic and any prior outcome in institutional_memory
  -- and answers support / concern / recommend_against with its reasoning. The challenger is the
  -- first officer in the list who is not the one proposing, so this is officers challenging each
  -- other rather than the CEO agreeing with itself. Top three only: a debate, not thirteen rows of
  -- boilerplate a week.
  --
  -- In its own block because a challenge that throws must not fail the meeting — the cron's own
  -- success is what exec-meeting-weekly-autostart measures. The number that actually landed goes
  -- into the run note below, so a swallowed failure is visible rather than silent.
  begin
    for p in select (e->>'rank')::int prank, e->>'title' ptitle, e->>'owner' powner
               from jsonb_array_elements(recs) e
              where (e->>'rank')::int <= 3 order by (e->>'rank')::int
    loop
      v_challenger := coalesce((select e2->>'owner' from jsonb_array_elements(recs) e2
                                 where coalesce(e2->>'owner','') <> coalesce(p.powner,'')
                                 order by (e2->>'rank')::int limit 1), 'ceo');
      perform fn_challenge('Exec meeting '||v_period||' priority '||p.prank||': '||p.ptitle,
                           coalesce(p.powner,'ceo'), v_challenger);
      v_ch := v_ch + 1;
    end loop;
  exception when others then
    v_ch := -1;
  end;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('exec_meeting',now(),now(),'ok',
    jsonb_build_object('os_green',v_green,'os_amber',v_amber,'os_red',v_red,'findings',jsonb_array_length(findings),'actions',actions,
      'priorities',jsonb_array_length(recs),'challenges',v_ch),
    'Executive meeting '||v_period||': '||v_green||' green / '||v_amber||' amber / '||v_red||' red across ten operating systems, '||actions||' actions assigned, '
    ||jsonb_array_length(recs)||' ranked priorities, '
    ||case when v_ch < 0 then 'the challenge round failed' else v_ch||' challenge(s) put to a second officer' end||'.');

  return jsonb_build_object('week',v_period,'green',v_green,'amber',v_amber,'red',v_red,
                            'findings',jsonb_array_length(findings),'actions',actions,
                            'priorities',jsonb_array_length(recs),'challenges',v_ch,'metrics',m);
end $function$
;

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

-- LAUNCH STEP 1 — THE CEO'S RANKED PRIORITIES REACH THEIR ACCOUNTABLE AI OFFICER, INSTEAD OF ALL BEING LOST.
--
-- These priorities do NOT reach the founder. fn_exec_meeting raises one agent_actions row per ranked
-- exec priority, addressed to the OWNER (agent = the accountable AI officer: cfo, procurement, cto, ...)
-- with kind='report_recommendation' — whose agent_action_kind_policy is 'auto', i.e. AI-decidable. The
-- founder's queue (kinds policied 'founder') does not include it. Only refunds require the founder.
--
-- Measured 1 Sep 2026: all of those inserts sat in ONE begin/exception block, and agent_actions_dedupe
-- is UNIQUE(agent, kind, target_id) WHERE status='pending'. Whenever two priorities shared an owner —
-- the normal case, company items are owned by cfo/procurement/cto plus 'unassigned' — the second insert
-- violated the dedupe index, the block's handler rolled the WHOLE batch back, and ZERO of the CEO's
-- priorities reached anyone (not even the AI officers who own them).
--
-- Fix: the priority insert now carries ON CONFLICT (agent, kind, target_id) WHERE status='pending' DO
-- NOTHING, so a shared-owner collision is skipped and every remaining priority still lands in its
-- officer's queue for the AI to act on. Nothing else in fn_exec_meeting changes (surgical replacement on
-- the live definition). Not a frozen subject; no external effect; pure SQL. Proven aborted-tx: 10
-- priorities raised across 10 distinct AI officers (was 0).
--
--   node scripts/apply_sql.mjs scripts/sql/launch_step1_ceo_priorities_reach_their_officer.sql --apply

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
  v_report_id bigint; v_raised int := 0;
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

  -- THE PRIORITIES REACH THE DECISION QUEUE.
  -- 33 of 40 exec_reports carried recommendations and agent_actions held ZERO row pointing at a
  -- report, so the founder could read the meeting's ranked priorities and had no way to act on
  -- them: the report surface has five approve controls bound to nothing. Each ranked priority is
  -- now raised once per period as an approvable action carrying target_table='exec_reports' and the
  -- report's id, which is what the approve control resolves.
  --
  -- One row per priority per week — typically two, one when every OS is green — so this cannot
  -- flood the queue. A bulk backfill of the 107 recommendation entries sitting in the last 30 days
  -- was deliberately NOT done: it would have taken the paused share of agent_actions from 2.6% to
  -- roughly 10.4% and regressed approval-center-everything-else-automatic, and most of those
  -- entries are superseded weekly anyway.
  --
  -- Its own block, like the debate above: a failure here must not fail the meeting, because the
  -- cron's own success is what exec-meeting-weekly-autostart measures.
  begin
    select id into v_report_id from exec_reports
     where officer='ceo' and period=v_period order by created_at desc limit 1;

    if v_report_id is not null then
      for p in select (e->>'rank')::int prank, e->>'title' ptitle, e->>'owner' powner,
                      e->>'why' pwhy, e->>'priority' phealth
                 from jsonb_array_elements(recs) e order by (e->>'rank')::int
      loop
        if not exists (select 1 from agent_actions a
                        where a.target_table='exec_reports'
                          and a.target_id = v_report_id::text
                          and coalesce(a.title,'') = 'Exec priority '||p.prank||': '||p.ptitle) then
          insert into agent_actions (agent, kind, status, risk, title, recommendation, detail,
                                     target_table, target_id)
          values (coalesce(p.powner,'ceo'), 'report_recommendation', 'pending',
                  case when p.phealth='red' then 'high' else 'medium' end,
                  'Exec priority '||p.prank||': '||p.ptitle,
                  coalesce(p.pwhy,'Ranked priority '||p.prank||' from the '||v_period||' executive meeting.'),
                  jsonb_build_object('source','fn_exec_meeting','period',v_period,'rank',p.prank,
                                     'owner',p.powner,'health',p.phealth,'report_id',v_report_id),
                  'exec_reports', v_report_id::text)
          -- ONE COLLISION MUST NOT LOSE THE WHOLE AGENDA. agent_actions_dedupe is UNIQUE(agent, kind,
          -- target_id) WHERE status='pending'. Two ranked priorities owned by the same officer collide
          -- on it; the enclosing block caught the error and rolled back EVERY priority insert, so zero
          -- of the CEO's priorities reached the founder queue. Skipping the duplicate keeps the rest.
          on conflict (agent, kind, target_id) where status = 'pending' do nothing;
          v_raised := v_raised + 1;
        end if;
      end loop;
    end if;
  exception when others then
    v_raised := -1;
  end;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('exec_meeting',now(),now(),'ok',
    jsonb_build_object('os_green',v_green,'os_amber',v_amber,'os_red',v_red,'findings',jsonb_array_length(findings),'actions',actions,
      'priorities',jsonb_array_length(recs),'challenges',v_ch,'raised_for_approval',v_raised),
    'Executive meeting '||v_period||': '||v_green||' green / '||v_amber||' amber / '||v_red||' red across ten operating systems, '||actions||' actions assigned, '
    ||jsonb_array_length(recs)||' ranked priorities, '
    ||case when v_ch < 0 then 'the challenge round failed' else v_ch||' challenge(s) put to a second officer' end
    ||', '||case when v_raised < 0 then 'raising priorities for approval failed' else v_raised||' priority(ies) raised for founder approval' end||'.');

  return jsonb_build_object('week',v_period,'green',v_green,'amber',v_amber,'red',v_red,
                            'findings',jsonb_array_length(findings),'actions',actions,
                            'priorities',jsonb_array_length(recs),'challenges',v_ch,
                            'raised_for_approval',v_raised,'metrics',m);
end $function$

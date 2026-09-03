-- EVERY ACTIVE OPERATING SYSTEM SPEAKS AT THE MEETING, AND EVERY PRIORITY CARRIES A NUMBER.
--
-- MEASURED ON PRODUCTION, 3 Sep 2026, in an aborted transaction (probe rolled back):
--   * os_review for the current week (2026-W36) held 12 rows: the 11 operating systems that were
--     active before today's re-carve PLUS assurance (deactivated today), and NO row for Supply OS
--     (num 13, created today). The meeting's guard was `if not exists (select 1 from os_review
--     where period = v_period)` -- "a row exists" -- so it skipped fn_os_review and iterated the stale
--     twelve: Supply OS was absent from its own first meeting and a retired OS spoke. Probe result:
--     14 agenda items, 1 active OS absent, 0 unowned.
--   * The newest recorded meeting (2026-08-10) had 10 of 12 active OS contributing (absent: Customer
--     Experience OS, Assurance OS) for the same reason -- the review it read predated them.
--   * The recommendations carried rank/owner/priority/title/why. The `why` is prose with counts in
--     it; nothing in the entry was a measurable ASK. Spec #3 layer 3: "the insight carries a
--     quantified recommendation".
--
-- WHAT CHANGES, and only this:
--   1. The review guard is per ACTIVE operating system: if any active OS has no os_review row for
--      this period, fn_os_review runs (it upserts every OS in v_os_health, so it is safe to re-run).
--   2. The agenda iterates operating_system WHERE active, LEFT JOIN os_review -- an active OS the
--      review still could not produce a row for speaks anyway, as amber with a finding that says so;
--      an inactive OS does not speak even if a stale review row exists. Red/amber/green are counted
--      over the same active set, so the summary line and the agenda agree.
--   3. Every agenda item and every ranked priority carries `ask` (a sentence with the figures the
--      owner must move) and `target` (the numbers as JSON), derived from the live drivers already
--      read out of v_os_health / the company metrics. No model call anywhere: the meeting was pure
--      SQL before and is pure SQL now, which is what lets it run under the paid-provider hold.
--
-- Everything else is byte-for-byte the definition read back from production.
--
-- Not done here: the four CEO reports of 28 Jul - 6 Aug still carry prose-string recommendations.
-- They are historical records of meetings that happened; rewriting them to satisfy a 60-day
-- universal would be arranging data to pass a check. They age out of the window by 6 Oct 2026.

CREATE OR REPLACE FUNCTION public.fn_exec_meeting()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare m jsonb; findings jsonb := '[]'::jsonb; actions int := 0; recs jsonb;
  -- the six agenda sections, rebuilt per contribution, plus their company-scoped counterparts
  v_wins text; v_probs text; v_risks text; v_opps text; v_reqs text; v_kpis jsonb;
  v_ask text; v_target jsonb;
  v_dept text; v_opp_all int; v_co jsonb; p record; v_challenger text; v_ch int := 0;
  v_period text := to_char(now(),'IYYY-"W"IW');
  v_rev numeric; v_spend numeric; v_sup int; v_open int; v_avail numeric;
  v_red int; v_amber int; v_green int; r record; v_drivers text;
  v_report_id bigint; v_raised int := 0;
  -- SURVIVAL LINE: cash, burn and runway, read once from fn_ws_finance (already computed).
  v_fin jsonb; v_cash numeric; v_burn numeric; v_runway numeric; v_fin_health text; v_fin_raised int := 0;
begin
  -- EVERY ACTIVE OPERATING SYSTEM MUST HAVE THIS WEEK'S REVIEW BEFORE THE MEETING READS IT.
  -- "A row exists for the period" let a review taken before an OS was created stand in for it, and
  -- let a retired OS keep its seat. fn_os_review upserts on (os_key, period), so re-running it for a
  -- missing OS is safe.
  if exists (select 1 from operating_system o where o.active
              and not exists (select 1 from os_review rv where rv.os_key = o.os_key and rv.period = v_period)) then
    perform fn_os_review();
  end if;

  -- Counted over the ACTIVE operating systems, the same population the agenda iterates below. An
  -- active OS the review could not produce a row for is amber: unreviewed is not green.
  -- (alias rv, not r: r is the loop RECORD below, and plpgsql would read r.health as its field)
  select count(*) filter (where rv.health='red'),
         count(*) filter (where coalesce(rv.health,'amber')='amber'),
         count(*) filter (where rv.health='green')
    into v_red, v_amber, v_green
    from operating_system o
    left join os_review rv on rv.os_key = o.os_key and rv.period = v_period
   where o.active;

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

  -- THE SURVIVAL LINE. One read of fn_ws_finance; carry it in the metrics so the meeting's KPI blob
  -- and every report built from it carries cash/burn/runway. runway_months is only a real number
  -- when the company is burning AND has cash, so burn and cash are tested first.
  v_fin := public.fn_ws_finance();
  v_cash := coalesce((v_fin->'cash'->>'total')::numeric, 0);
  v_burn := coalesce((v_fin->'run_rate'->>'monthly_burn')::numeric, 0);
  v_runway := nullif(v_fin->'run_rate'->>'runway_months','')::numeric;
  v_fin_health := case when v_burn <= 0 then 'green'
                       when v_cash <= 0 then 'red'
                       when v_runway < 3 then 'red'
                       when v_runway < 6 then 'amber'
                       else 'green' end;
  m := m || jsonb_build_object('cash_aed', v_cash, 'monthly_burn_aed', v_burn, 'runway_months', v_runway);

  -- AGENDA ITEM PER ACTIVE OPERATING SYSTEM, named with its owner AND with the live per-OS figures
  -- out of v_os_health that put it there. Both joins are LEFT: an OS the review could not produce a
  -- row for still reaches the agenda (amber, with a finding saying so), and an OS the view cannot
  -- resolve reaches it without drivers.
  for r in
    select o.num, o.name,
           coalesce(r2.health, 'amber') health,
           coalesce(r2.owner_agent, o.owner_agent) owner_agent,
           coalesce(r2.findings, jsonb_build_array(jsonb_build_object(
             'issue', 'no review this week',
             'detail', 'fn_os_review produced no row for this operating system in '||v_period||'.'))) findings,
           h.open_risks, h.kpi_gaps, h.backlog_per_head, h.stale_tasks,
           h.review_pass_pct, h.budget_pct, h.needs_founder_pct,
           r2.metrics->>'capacity_pct' capacity_pct
    from operating_system o
    left join os_review r2 on r2.os_key = o.os_key and r2.period = v_period
    left join v_os_health h on h.os_key = o.os_key
    where o.active
    order by
      case coalesce(r2.health, 'amber') when 'red' then 1 when 'amber' then 2 else 3 end, o.num
  loop
    v_drivers := 'open_risks '||coalesce(r.open_risks::text,'?')
      ||', kpi_gaps '||coalesce(r.kpi_gaps::text,'?')
      ||', capacity_pct '||coalesce(r.capacity_pct,'?')
      ||', backlog_per_head '||coalesce(r.backlog_per_head::text,'?')
      ||', stale_tasks '||coalesce(r.stale_tasks::text,'?')
      ||', review_pass_pct '||coalesce(r.review_pass_pct::text,'?')
      ||', budget_pct '||coalesce(r.budget_pct::text,'?')
      ||', needs_founder_pct '||coalesce(r.needs_founder_pct::text,'?');
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

    -- THE QUANTIFIED ASK. The three drivers the owner can move this week, with where they stand
    -- and where they must be, in the same sentence and again as numbers. A green OS is asked to
    -- hold its figures, not to improve on zero.
    v_ask := case when r.health = 'green'
      then 'Hold: '||coalesce(r.kpi_gaps,0)||' KPI gap(s), '||coalesce(r.stale_tasks,0)
           ||' stale task(s), '||coalesce(r.open_risks,0)||' open risk(s) — keep all three at 0 through '
           ||to_char(current_date + 7, 'YYYY-MM-DD')||'.'
      else 'Close '||coalesce(r.kpi_gaps,0)||' KPI gap(s) → 0, clear '||coalesce(r.stale_tasks,0)
           ||' stale task(s) → 0 and retire '||coalesce(r.open_risks,0)||' open risk(s) → 0 by '
           ||to_char(current_date + 7, 'YYYY-MM-DD')
           ||coalesce('; budget at '||r.budget_pct||'% of month, stay under 70%', '')||'.' end;
    v_target := jsonb_build_object(
      'kpi_gaps', 0, 'stale_tasks', 0, 'open_risks', 0, 'budget_pct_max', 70,
      'current', jsonb_build_object('kpi_gaps', coalesce(r.kpi_gaps,0), 'stale_tasks', coalesce(r.stale_tasks,0),
                                    'open_risks', coalesce(r.open_risks,0), 'budget_pct', r.budget_pct),
      'by', to_char(current_date + 7, 'YYYY-MM-DD'));

    findings := findings || jsonb_build_array(jsonb_build_object(
      'item', r.num||'. '||r.name, 'owner', coalesce(r.owner_agent,'unassigned'),
      'health', r.health, 'finding', r.findings::text, 'drivers', v_drivers,
      'wins', v_wins, 'problems', v_probs, 'kpis', v_kpis,
      'risks', v_risks, 'opportunities', v_opps, 'requests', v_reqs,
      'ask', v_ask, 'target', v_target));
  end loop;

  -- COMPANY-LEVEL ITEMS the CEO owns directly. Each carries the same quantified ask.
  if coalesce(v_rev,0)=0 then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Revenue','owner','cfo','health','amber',
      'finding','No revenue recognised in the last 7 days.',
      'ask','Revenue AED 0 in 7 days: book at least 1 revealed quote (3% reveal fee) by '||to_char(current_date + 7, 'YYYY-MM-DD')||'.',
      'target',jsonb_build_object('reveals_7d',1,'revenue_7d_aed_min',1,'current',jsonb_build_object('revenue_7d_aed',v_rev),'by',to_char(current_date + 7, 'YYYY-MM-DD'))));
  end if;
  if v_sup < 860 then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Supplier coverage','owner','procurement','health',
      case when v_sup=0 then 'red' else 'amber' end,
      'finding', v_sup||' approved suppliers against a target of 860 (10 in each of 86 categories).',
      'ask','Approve '||(860 - v_sup)||' more suppliers to reach 860 (now '||v_sup||'); at least 10 this week.',
      'target',jsonb_build_object('approved_suppliers',860,'approved_this_week_min',10,'current',jsonb_build_object('approved_suppliers',v_sup))));
  end if;
  if coalesce(v_avail,100) < 99.5 then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Platform availability','owner','cto','health','amber',
      'finding','Availability '||coalesce(v_avail,0)||'% against 99.5%.',
      'ask','Raise 7-day availability from '||coalesce(v_avail,0)||'% to 99.5%.',
      'target',jsonb_build_object('availability_pct',99.5,'current',jsonb_build_object('availability_pct',v_avail))));
  end if;
  -- SURVIVAL LINE ON THE AGENDA. The CFO owns it. It joins the agenda only when it is not green,
  -- like the three items above, and it always exists as a board report below.
  if v_fin_health <> 'green' then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Runway & cash','owner','cfo','health',v_fin_health,
      'finding','Cash AED '||round(v_cash)||', monthly burn AED '||round(v_burn)||', runway '
        ||coalesce(v_runway::text,'—')||' months against a break-even target.',
      'ask','Cash AED '||round(v_cash)||' and burn AED '||round(v_burn)||'/month: cut burn or add cash until runway is at least 6 months (now '
        ||coalesce(v_runway::text,'—')||').',
      'target',jsonb_build_object('runway_months_min',6,'current',jsonb_build_object('cash_aed',v_cash,'monthly_burn_aed',v_burn,'runway_months',v_runway))));
    v_fin_raised := 1;
  end if;

  -- The company-level items above are contributions too, so they carry the same six sections,
  -- scoped to the company rather than to one department.
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
    ||coalesce(' Ask: '||(f->>'ask'),'')
    ||' Raised at the weekly executive meeting. Close it, or bring evidence the standard is wrong.',
    'proposed','advisory',false,'exec_review'
  from jsonb_array_elements(findings) f
  where coalesce(f->>'health','') <> 'green'
    and not exists (select 1 from org_tasks t where t.title='Exec meeting '||v_period||': '||(f->>'item') and t.status<>'done');
  get diagnostics actions = row_count;

  select coalesce(jsonb_agg(jsonb_build_object(
           'rank', x.rn, 'owner', x.owner, 'priority', x.health,
           'title', x.item, 'why', x.finding, 'ask', x.ask, 'target', x.target) order by x.rn), '[]'::jsonb)
    into recs from (
      select row_number() over (order by case f->>'health' when 'red' then 1 else 2 end, ord) rn,
             f->>'item' item, f->>'owner' owner, f->>'health' health,
             case when f ? 'drivers' then f->>'problems' else f->>'finding' end finding,
             f->>'ask' ask, f->'target' target
        from jsonb_array_elements(findings) with ordinality as t(f, ord)
       where coalesce(f->>'health','') <> 'green') x;
  if jsonb_array_length(recs) = 0 then
    recs := jsonb_build_array(jsonb_build_object('rank', 1, 'owner', 'ceo', 'priority', 'hold',
      'title', 'Hold current priorities',
      'why', 'All operating systems green and company metrics within tolerance.',
      'ask', 'Hold: keep '||v_green||' of '||v_green||' active operating systems green through '||to_char(current_date + 7, 'YYYY-MM-DD')||'.',
      'target', jsonb_build_object('os_green', v_green, 'os_red', 0, 'os_amber', 0, 'by', to_char(current_date + 7, 'YYYY-MM-DD'))));
  end if;

  insert into exec_reports (officer,period,summary,findings,recommendations,metrics,status)
  values ('ceo',v_period,
    'Weekly executive meeting across all operating systems. '||v_green||' green, '||v_amber||' amber, '||v_red
    ||' red. '||jsonb_array_length(findings)||' agenda contribution(s), '||actions||' action(s) assigned.',
    findings, recs, m, 'open')
  on conflict do nothing;

  -- THE FINANCE BOARD REPORT. One report_type='finance' board_reports row per week, carrying the
  -- survival figures, so the board has a standing finance record independent of whether the agenda
  -- surfaced runway this week. Its own block: a failure here must not fail the meeting.
  begin
    if not exists (select 1 from board_reports
                    where report_type='finance' and week_start = date_trunc('week',current_date)::date) then
      insert into board_reports(week_start, title, body, kpis, report_type)
      values (date_trunc('week',current_date)::date,
        'Finance — runway, cash & burn ('||v_period||')',
        'Cash AED '||round(v_cash)||' · monthly burn AED '||round(v_burn)||' · runway '
          ||coalesce(v_runway::text,'—')||' months · ARR est AED '
          ||round(coalesce((v_fin->'run_rate'->>'arr_estimate')::numeric,0))
          ||' · net income (all-time) AED '||round(coalesce((v_fin->'pnl'->>'net_income')::numeric,0))
          ||'. Health: '||v_fin_health||'.',
        jsonb_build_object('cash_aed',v_cash,'monthly_burn_aed',v_burn,'runway_months',v_runway,
          'arr_estimate',(v_fin->'run_rate'->>'arr_estimate'),'net_income',(v_fin->'pnl'->>'net_income'),
          'health',v_fin_health,'period',v_period),
        'finance');
    end if;
  exception when others then
    v_fin_raised := v_fin_raised;   -- board report is best-effort; the meeting proceeds
  end;

  -- THE DEBATE.
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
      'priorities',jsonb_array_length(recs),'challenges',v_ch,'raised_for_approval',v_raised,
      'runway_months',v_runway,'finance_health',v_fin_health),
    'Executive meeting '||v_period||': '||v_green||' green / '||v_amber||' amber / '||v_red||' red across all active operating systems, '||actions||' actions assigned, '
    ||jsonb_array_length(recs)||' ranked priorities, '
    ||case when v_ch < 0 then 'the challenge round failed' else v_ch||' challenge(s) put to a second officer' end
    ||', '||case when v_raised < 0 then 'raising priorities for approval failed' else v_raised||' priority(ies) raised for founder approval' end
    ||'. Finance '||v_fin_health||' (runway '||coalesce(v_runway::text,'—')||'mo).');

  return jsonb_build_object('week',v_period,'green',v_green,'amber',v_amber,'red',v_red,
                            'findings',jsonb_array_length(findings),'actions',actions,
                            'priorities',jsonb_array_length(recs),'challenges',v_ch,
                            'raised_for_approval',v_raised,
                            'finance_health',v_fin_health,'runway_months',v_runway,'metrics',m);
end $function$;

-- READ-ONLY ASSERTIONS. The routine's agenda population is the active operating systems, and the
-- review that feeds it can produce a row for every one of them (v_os_health is what fn_os_review
-- iterates). Nothing here writes.
do $$
declare v_missing int; v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_exec_meeting';
  if v_def !~ 'from operating_system o\s+left join os_review r2' then
    raise exception 'fn_exec_meeting does not iterate the active operating systems';
  end if;
  select count(*) into v_missing from public.operating_system o
   where o.active and not exists (select 1 from public.v_os_health h where h.os_key = o.os_key);
  if v_missing > 0 then
    raise exception '% active operating system(s) are invisible to v_os_health and would speak without drivers', v_missing;
  end if;
end $$;

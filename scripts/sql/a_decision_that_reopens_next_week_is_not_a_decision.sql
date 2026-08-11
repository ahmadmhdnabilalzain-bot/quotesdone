-- A DECISION THAT REOPENS THE NEXT TIME THE ROUTINE RUNS IS NOT A DECISION, IT IS A NAG.
--
-- fn_delete_proposer reopened three of the five proposals within seconds of them being answered,
-- because it only looks for an OPEN row of that category and finds none once one is closed. The
-- three it reopened are standing facts the company has deliberately decided to live with - the
-- pack's 96-role target org chart, two unwatchable agent_expectations rows, one inactive employee.
-- Asking again every Monday does not make the answer better; it teaches whoever reads the queue
-- that these rows are noise, which is how the real one gets missed.
--
-- A decision now HOLDS until the fact changes. Reopening requires the count to have GROWN past what
-- was decided: 1 inactive employee was accepted, 5 is a different question and gets asked again.
-- The two categories answered "keep_with_reason" need no special case at all - their counts already
-- exclude rows carrying a reason, so writing the reason is what closed them and removing it is what
-- would reopen them.

CREATE OR REPLACE FUNCTION public.fn_delete_proposer()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_out jsonb := '[]'::jsonb; c record; v_n int; v_id bigint; v_prev record;
  v_specs jsonb := jsonb_build_array(
    jsonb_build_object('category','model_policy_by_identity_target_employee','agent','ai_director','risk','low',
      'title_suffix','imported model-policy rows that name no employee',
      'sql', $s$select count(*) from model_policy_by_identity where scope='target_employee'$s$,
      'why','96 rows scoped target_employee, 0 matching an org_agents.agent_key. DECIDED 11 Aug 2026: KEEP. They are the pack''s TARGET ORG CHART - department, title, manager and authority_tier for 96 roles - not dead routing config. routing_tier superseded their MODEL choice, not their org design. fn_ai_route reads only scope=''current_agent'', so they route nothing.'),
    jsonb_build_object('category','decorative_company_goals','agent','analytics_director','risk','medium',
      'title_suffix','Company goals that cannot be missed and cannot pull anything down',
      'sql', $s$select count(*) from company_goals g where g.active and coalesce(g.measure_sql,'')='' and coalesce(g.no_measure_reason,'')='' and not exists (select 1 from department_objective d where d.goal_key=g.key and d.active)$s$,
      'why','Active, no measure_sql, no department objective, AND no recorded reason why. A goal that cannot be measured cannot be missed. Giving it a measure or a written reason both count; leaving it silent does not.'),
    jsonb_build_object('category','orphan_agent_expectations','agent','it','risk','low',
      'title_suffix','agent_expectations rows watching something that does not exist',
      'sql', $s$select count(*) from agent_expectations e where public.fn_org_agent_resolve(e.agent) is null and coalesce(e.kind,'') <> 'code' and not exists (select 1 from cron.job j where j.jobname ilike '%'||e.agent||'%' or j.command ilike '%'||e.agent||'%')$s$,
      'why','Resolves to no employee through key OR alias, is not a code/job name, and matches no cron job. Each one can raise a silence alarm about a thing that cannot run, which is how an employee gets dispatched to diagnose nothing.'),
    jsonb_build_object('category','unmeasurable_employee_kpis','agent','analytics_director','risk','medium',
      'title_suffix','Employee KPIs with a target and no way to measure it',
      'sql', $s$select count(*) from employee_kpi k where k.active and coalesce(k.measure_sql,'')='' and coalesce(k.no_measure_reason,'')=''$s$,
      'why','An employee is told it is judged on something nobody can score, and nobody has written down why. Most need an instrument or demand that does not exist yet rather than deletion - a recorded reason closes this, a silent row does not.'),
    jsonb_build_object('category','inactive_org_agents','agent','hr_director','risk','low',
      'title_suffix','Employees marked inactive and still on the books',
      'sql', $s$select count(*) from org_agents where not coalesce(active,true)$s$,
      'why','An inactive employee still resolves in manager chains and still appears in joins that do not filter on active. Either reactivate it or remove it deliberately.')
  );
begin
  for c in select * from jsonb_array_elements(v_specs) as t(spec)
  loop
    execute (c.spec->>'sql') into v_n;
    if coalesce(v_n,0) = 0 then continue; end if;

    select id into v_id from public.agent_actions
     where kind = 'delete_proposal' and detail->>'category' = c.spec->>'category'
       and status = 'needs_review' limit 1;
    if v_id is not null then
      update public.agent_actions
         set title = v_n || ' — ' || (c.spec->>'title_suffix'),
             detail = coalesce(detail,'{}'::jsonb) || jsonb_build_object(
               'count', v_n, 'why', c.spec->>'why', 'counted_by', c.spec->>'sql',
               'counted_at', now())
       where id = v_id;
      continue;
    end if;

    -- THE DECISION HOLDS UNTIL THE FACT CHANGES. A category answered 'keep' is not asked again at
    -- the same size or smaller. It IS asked again if the count grows past what was accepted, which
    -- is a different question about a different number.
    select (detail->>'count')::int as n, detail->>'decision' as decision
      into v_prev
      from public.agent_actions
     where kind = 'delete_proposal' and detail->>'category' = c.spec->>'category'
       and detail ? 'decision'
     order by id desc limit 1;
    if found and v_prev.decision in ('keep','keep_with_reason','retire')
       and v_n <= coalesce(v_prev.n, 0) then
      continue;
    end if;

    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail)
    values (c.spec->>'agent', 'delete_proposal', 'needs_review', c.spec->>'risk',
            v_n || ' — ' || (c.spec->>'title_suffix'),
            'Decide deliberately: remove, retire (active=false), or keep with a stated reason. Do not close this without one of the three.',
            jsonb_build_object('category', c.spec->>'category', 'count', v_n,
              'why', c.spec->>'why', 'counted_by', c.spec->>'sql', 'counted_at', now(),
              'reopened_over', case when v_prev.n is null then null else v_prev.n end,
              'proposes','review for removal — this routine never deletes anything'));
    v_out := v_out || jsonb_build_array(jsonb_build_object('category', c.spec->>'category', 'count', v_n));
  end loop;

  insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('delete_proposer','ok', jsonb_build_object('opened', jsonb_array_length(v_out)),
          'delete proposals refreshed; ' || jsonb_array_length(v_out) || ' newly opened', now(), now());
  return v_out;
end
$function$;
REVOKE ALL ON FUNCTION public.fn_delete_proposer() FROM PUBLIC;

-- Close the three the un-guarded version reopened seconds after they were answered, carrying the
-- same decision forward rather than re-deciding it.
update public.agent_actions a
   set status = 'done', decided_at = now(), decided_by = 'session:2026-08-11',
       detail = coalesce(a.detail,'{}'::jsonb) || jsonb_build_object(
         'decision', prev.decision,
         'decided_note', 'Carried forward from action ' || prev.id
                         || '; the count has not grown since that decision.')
  from (select distinct on (detail->>'category')
               id, detail->>'category' as category, detail->>'decision' as decision,
               (detail->>'count')::int as n
          from public.agent_actions
         where kind='delete_proposal' and status='done' and detail ? 'decision'
         order by detail->>'category', id desc) prev
 where a.kind = 'delete_proposal'
   and a.status = 'needs_review'
   and a.detail->>'category' = prev.category
   and (a.detail->>'count')::int <= prev.n;

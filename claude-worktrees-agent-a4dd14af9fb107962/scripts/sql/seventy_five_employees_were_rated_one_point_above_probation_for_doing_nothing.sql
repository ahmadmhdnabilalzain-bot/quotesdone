-- Seventy-five employees were rated one point above probation for doing nothing
-- =============================================================================
--
-- Went looking for why employee-performance and employee-current-thoughts are MISSING on Row #3.
-- Neither is a UI defect. Both fail on coverage, and the coverage number is the finding:
--
--     93 active employees
--     75 have never written an agent_runs row      -- ever
--     76 have never appeared in ai_cost_log        -- never cost one fils
--     68 have no agent_memory row in 30 days
--     13 appear in agent_actions, 12 in decision_log
--
-- and yet:
--
--     93 have an employee_kpi row
--     93 have an agent_reputation row
--
-- The company scores and rates a workforce of 93. Eighteen of them work.
--
-- WHAT THE SCORE ACTUALLY SAYS. fn_reputation_recompute computes
--     score = coalesce(corr,50)*0.30 + coalesce(rel,50)*0.30 + coalesce(cost,50)*0.15
--           + coalesce(learn,50)*0.15 + coalesce(collab,50)*0.10
-- so an employee with NO evidence on any dimension scores exactly 50, and the tiers are
--     >= 85 senior_trusted · >= 70 trusted · >= 50 standard · else probation.
--
-- Measured on production:
--     trusted    11 employees   avg 76.2   0 never ran   0 never spent
--     standard   82 employees   avg 51.0  75 never ran  76 never spent
--
-- 50 is not a neutral placeholder. It is the exact boundary of 'standard', so an employee with
-- zero evidence lands one point above probation and is indistinguishable on the founder's screen
-- from one that genuinely performed at 50. It is least(100, NULL) again, at organisational scale.
--
-- IT ALSO MAKES THE DEMOTION UNREACHABLE. The probation branch gates an employee's authority when
-- tier = 'probation'. An idle employee can never reach it, because absence of evidence scores 50,
-- not 0. So the one consequence the reputation system has cannot fire for the 75 employees most
-- likely to deserve review. Guarded by a condition that cannot occur.
--
-- AND IT LOOSENS AUTHORITY. The recovery branch restores 'autonomous' to any advisory-safe grant
-- whose holder is `tier <> 'probation'`. An employee that has never executed anything qualifies
-- today.
--
-- THE FIX: absence of evidence gets its own name. An employee with no reading on ANY of the five
-- dimensions is 'unmeasured' with score NULL — not 50, not standard, not a number at all. NULL is
-- the honest value: we have not measured this employee, and a score is a measurement.
--
-- Deliberately NOT done here: demoting the 75. 'unmeasured' does not trigger the probation gate,
-- so the new tier revokes no authority. It only stops the RESTORE path from treating "never
-- worked" as "recovered", which is a narrowing, never a loosening. Whether 75 idle employees
-- should hold authority at all is an organisational decision with real consequences, and it
-- belongs in a task, not in a scoring function.
--
-- THE FIRST RUN DOES GATE ONE GRANT, and it is not the unmeasured tier that does it. Probed in an
-- aborted transaction before applying: autonomous grants 143 -> 142, and the three employees that
-- land on probation carry genuinely poor READINGS, not absent ones:
--     analytics_director  reliability 0.0  cost 0.0            score 27.5
--     comms_manager       reliability 33.3 cost 0.0 collab 100 score 42.5
--     forecast_analyst    cost 0.0                             score 42.5
-- reliability 0.0 means every run this employee made errored. Those three would have reached
-- probation on the next scheduled run with or without this change - today's outcome grading is
-- what made their correctness and reliability computable at all. The demotion is the probation
-- branch working as designed, on real numbers, for the first time.
--
-- This makes the numbers worse. 82 'standard' becomes 22 standard + 57 unmeasured + 3 probation,
-- and Row #3's employee-performance stays MISSING because it is measuring something true. That is
-- correct: the old pass was 50 points of nothing.

alter table public.agent_reputation drop constraint if exists agent_reputation_tier_check;
alter table public.agent_reputation add constraint agent_reputation_tier_check
  check (tier = any (array['probation','standard','trusted','senior_trusted','unmeasured']));

create or replace function public.fn_reputation_recompute()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; n int := 0; v_score numeric; v_tier text;
  v_corr numeric; v_rel numeric; v_cost numeric; v_learn numeric; v_collab numeric;
  v_gated int := 0; v_restored int := 0; v_unmeasured int := 0;
begin
  for r in select agent_key from org_agents where active loop
    -- correctness: graded improvements that moved the metric the right way
    select coalesce(round(100.0*count(*) filter (where verdict='improved')
             /nullif(count(*) filter (where verdict in ('improved','no_change','worse')),0),1), null)
      into v_corr from outcome_record where actor = r.agent_key;
    -- reliability: runs that did not error.
    -- NOTE (10 Aug 2026): for EMPLOYEES this is the wrong table - agent_runs is the cron log and
    -- only nine of its 111 agent values are org_agents keys. Left alone deliberately: every value
    -- present is >= 93, so it only ever raises a score. Do not "fix" it into something that starts
    -- lowering scores without first deciding what employee reliability means.
    select coalesce(round(100.0*count(*) filter (where status<>'error')/nullif(count(*),0),1), null)
      into v_rel from agent_runs where agent = r.agent_key and started_at > now()-interval '30 days';
    -- cost efficiency: share of calls a cheaper model could NOT have served
    select coalesce(round(100.0*count(*) filter (where not coalesce(could_be_cheaper,false))/nullif(count(*),0),1), null)
      into v_cost from ai_cost_log where agent_key = r.agent_key and occurred_at > now()-interval '30 days';

    -- learning speed: UNMEASURABLE, so NULL for everyone. See the header of the 10 Aug change.
    v_learn := null;

    -- collaboration: reviews it took part in that reached approval, over DECIDED VERDICTS ONLY.
    select coalesce(round(100.0*count(*) filter (where decision='approve')/nullif(count(*),0),1), null)
      into v_collab from review_chain
     where (author_agent = r.agent_key or reviewer_agent = r.agent_key)
       and decision in ('approve','reject','request_revision');

    -- ABSENCE OF EVIDENCE IS NOT A SCORE OF 50 (12 Aug 2026). See the header: coalesce(...,50) put
    -- 75 employees who have never executed anything at 51.0, one point above probation and
    -- indistinguishable from a real 50. An employee with no reading on any dimension is now
    -- 'unmeasured' with score NULL, because a score is a measurement and we have not made one.
    if v_corr is null and v_rel is null and v_cost is null and v_learn is null and v_collab is null then
      v_score := null;
      v_tier  := 'unmeasured';
      v_unmeasured := v_unmeasured + 1;
    else
      v_score := round((coalesce(v_corr,50)*0.30 + coalesce(v_rel,50)*0.30 + coalesce(v_cost,50)*0.15
                      + coalesce(v_learn,50)*0.15 + coalesce(v_collab,50)*0.10), 1);
      v_tier := case when v_score >= 85 then 'senior_trusted'
                     when v_score >= 70 then 'trusted'
                     when v_score >= 50 then 'standard' else 'probation' end;
    end if;

    insert into agent_reputation (agent_key,correctness,reliability,cost_efficiency,learning_speed,collaboration,score,tier,computed_at)
    values (r.agent_key,v_corr,v_rel,v_cost,v_learn,v_collab,v_score,v_tier,now())
    on conflict (agent_key) do update set correctness=excluded.correctness, reliability=excluded.reliability,
      cost_efficiency=excluded.cost_efficiency, learning_speed=excluded.learning_speed,
      collaboration=excluded.collaboration, score=excluded.score, tier=excluded.tier, computed_at=now();
    n := n + 1;
  end loop;

  -- probation is a real consequence: any agent below the floor loses autonomous authority.
  -- 'unmeasured' deliberately does NOT trigger this - see the header. No authority is revoked by
  -- introducing the tier.
  with demoted as (
    update employee_authority a set max_tier='gated'
      from agent_reputation p
     where p.agent_key=a.agent_key and p.tier='probation' and a.max_tier='autonomous'
    returning a.agent_key, a.action_class)
  insert into autonomy_control_audit (object, op, direction, old_value, new_value, reason)
  select 'employee_authority:'||agent_key||'/'||action_class, 'reputation_demote', 'tighten',
         'autonomous', 'gated', 'reputation tier fell to probation'
    from demoted;
  get diagnostics v_gated = row_count;

  -- ...and recovery is a real consequence too. NARROWED 12 Aug 2026: this read `tier <> 'probation'`,
  -- which an employee that has never executed anything satisfied - so "never worked" was being
  -- treated as "recovered" and handed back autonomous authority. Recovery now requires a tier that
  -- was actually earned from a reading.
  with restored as (
    update employee_authority a set max_tier='autonomous'
      from agent_reputation p
     where p.agent_key=a.agent_key
       and a.max_tier='gated'
       and p.tier in ('standard','trusted','senior_trusted')
       and a.note = 'Advisory-safe action, may run autonomously'
    returning a.agent_key, a.action_class)
  insert into autonomy_control_audit (object, op, direction, old_value, new_value, reason)
  select 'employee_authority:'||agent_key||'/'||action_class, 'reputation_restore', 'loosen',
         'gated', 'autonomous',
         'reputation recovered above probation and the grant note records the action as advisory-safe'
    from restored;
  get diagnostics v_restored = row_count;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('reputation',now(),now(),'ok',
    jsonb_build_object('scored',n,'gated',v_gated,'restored',v_restored,'unmeasured',v_unmeasured),
    'Reputation recomputed for '||n||' employee(s), of which '||v_unmeasured||' have no reading on '
    ||'any dimension and are recorded as unmeasured with a NULL score rather than a default 50. '
    ||'Probation demotes autonomous authority to gated ('||v_gated||' this run); recovery restores '
    ||'advisory-safe grants ('||v_restored||' this run) and no longer counts unmeasured as recovered.');
  return jsonb_build_object('scored',n,'gated',v_gated,'restored',v_restored,'unmeasured',v_unmeasured);
end
$function$;

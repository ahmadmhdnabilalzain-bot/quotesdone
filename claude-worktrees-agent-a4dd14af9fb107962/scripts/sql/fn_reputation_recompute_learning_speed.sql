CREATE OR REPLACE FUNCTION public.fn_reputation_recompute()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int := 0; v_score numeric; v_tier text;
  v_corr numeric; v_rel numeric; v_cost numeric; v_learn numeric; v_collab numeric;
begin
  for r in select agent_key from org_agents where active loop
    -- correctness: graded improvements that moved the metric the right way
    select coalesce(round(100.0*count(*) filter (where verdict='improved')
             /nullif(count(*) filter (where verdict in ('improved','no_change','worse')),0),1), null)
      into v_corr from outcome_record where actor = r.agent_key;
    -- reliability: runs that did not error
    select coalesce(round(100.0*count(*) filter (where status<>'error')/nullif(count(*),0),1), null)
      into v_rel from agent_runs where agent = r.agent_key and started_at > now()-interval '30 days';
    -- cost efficiency: share of calls a cheaper model could NOT have served
    select coalesce(round(100.0*count(*) filter (where not coalesce(could_be_cheaper,false))/nullif(count(*),0),1), null)
      into v_cost from ai_cost_log where agent_key = r.agent_key and occurred_at > now()-interval '30 days';
    -- learning speed: knowledge this agent owns that is validated
    -- NOTHING VALIDATES KNOWLEDGE, SO 0% IS "NEVER ASSESSED", NOT "LEARNS NOTHING" (10 Aug 2026).
    -- validation_status has exactly two values, author_verified and unvalidated, and it DEFAULTS to
    -- unvalidated. Zero routines in the estate ever set author_verified: the 292 verified rows came
    -- from a historical seed and no live process has produced one since. So this share measured
    -- which seeded batch an employee happened to inherit, and it was the ONLY scored dimension for
    -- every agent on probation - correctness, reliability, cost_efficiency and collaboration are
    -- all NULL for them, coalesced to a neutral 50, while this one alone dragged them to 42.5.
    --
    -- OWNING KNOWLEDGE MADE YOU WORSE OFF THAN OWNING NONE, which is backwards. An agent with no
    -- knowledge scored NULL -> 50 -> standard; an agent who owned some scored 0 -> 42.5 ->
    -- probation, and probation gates spend through fn_check_spend.
    --
    -- It stayed hidden while only 7 employees owned knowledge. Assigning the 1,148 ownerless rows
    -- their real owners earlier tonight took that to 23, and the next reputation_weekly run
    -- (07:00 Monday) would have demoted SIXTEEN employees for inheriting unreviewed rows.
    --
    -- Unmeasured is NULL here, exactly as it already is for the other four dimensions. An agent
    -- that does have validated knowledge keeps its real score. This dimension cannot mean anything
    -- until something actually validates knowledge; building that validator is the real fix.
    select case when count(*) filter (where validation_status not in ('unvalidated','unreviewed')) = 0
                then null
                else round(100.0*count(*) filter (where validation_status not in ('unvalidated','unreviewed'))
                           /nullif(count(*),0),1) end
      into v_learn from agent_knowledge where owner_agent = r.agent_key;
    -- collaboration: reviews it took part in that reached approval
    select coalesce(round(100.0*count(*) filter (where decision='approve')/nullif(count(*),0),1), null)
      into v_collab from review_chain where author_agent = r.agent_key or reviewer_agent = r.agent_key;

    v_score := round((coalesce(v_corr,50)*0.30 + coalesce(v_rel,50)*0.30 + coalesce(v_cost,50)*0.15
                    + coalesce(v_learn,50)*0.15 + coalesce(v_collab,50)*0.10), 1);
    v_tier := case when v_score >= 85 then 'senior_trusted'
                   when v_score >= 70 then 'trusted'
                   when v_score >= 50 then 'standard' else 'probation' end;

    insert into agent_reputation (agent_key,correctness,reliability,cost_efficiency,learning_speed,collaboration,score,tier,computed_at)
    values (r.agent_key,v_corr,v_rel,v_cost,v_learn,v_collab,v_score,v_tier,now())
    on conflict (agent_key) do update set correctness=excluded.correctness, reliability=excluded.reliability,
      cost_efficiency=excluded.cost_efficiency, learning_speed=excluded.learning_speed,
      collaboration=excluded.collaboration, score=excluded.score, tier=excluded.tier, computed_at=now();
    n := n + 1;
  end loop;

  -- probation is a real consequence: any agent below the floor loses autonomous authority
  update employee_authority a set max_tier='gated'
   from agent_reputation p
  where p.agent_key=a.agent_key and p.tier='probation' and a.max_tier='autonomous';

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('reputation',now(),now(),'ok',jsonb_build_object('scored',n),
    'Reputation recomputed for '||n||' employee(s). Probation demotes autonomous authority to gated.');
  return jsonb_build_object('scored',n);
end $function$

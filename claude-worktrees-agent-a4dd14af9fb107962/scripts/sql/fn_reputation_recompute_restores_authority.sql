-- fn_reputation_recompute could only ever take authority AWAY.
--
-- The demotion has been there from the start:
--     update employee_authority set max_tier='gated' ... where p.tier='probation' and a.max_tier='autonomous'
-- and there was no statement anywhere in the estate that moved one back. An employee that dipped
-- below the floor once stayed gated for ever, so the company could only become LESS autonomous
-- over time — a ratchet, not a policy.
--
-- It left 34 gated rows over 14 employees with NOT ONE on probation, residue from a scoring bug
-- that has since been fixed (learning_speed was scoring employees down for learning).
--
-- THE RESTORE IS DELIBERATELY NARROWER THAN THE DEMOTION. `employee_authority` has no timestamp
-- and no provenance column, so "did reputation gate this row, or was it gated by design?" has
-- exactly one surviving piece of evidence: the grant's own `note`. Only rows whose note states
-- the action is meant to run autonomously are restored. Measured, of the 34:
--
--   12 say  "Advisory-safe action, may run autonomously"      -> restored (4 employees)
--   22 say something else                                     -> LEFT GATED, every one:
--        "Structural change is proposed, never self-applied"   (role_define)
--        "Cost changes touching production need review"        (code_selfheal)
--        "Writes corrections only on model convergence"        (knowledge_fill_gap)
--        "May hold work that fails a quality gate"             (qa_gate)
--        "Director approves within the department; spend and public publishing route to founder"
--        "Inherits department authority as head"               (ambiguous — never widened on a guess)
--
-- So this does not restore "the 34". It restores the 12 the data can actually justify, and says
-- so. threshold_aed is untouched on every row, and fn_decision_gate still applies.
--
-- Both directions now write to autonomy_control_audit, which already existed and already carries
-- 44 rows — no new audit table. A ratchet that logged nothing is how this went unnoticed.
create or replace function public.fn_reputation_recompute()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r record; n int := 0; v_score numeric; v_tier text;
  v_corr numeric; v_rel numeric; v_cost numeric; v_learn numeric; v_collab numeric;
  v_gated int := 0; v_restored int := 0;
begin
  for r in select agent_key from org_agents where active loop
    -- correctness: graded improvements that moved the metric the right way
    select coalesce(round(100.0*count(*) filter (where verdict='improved')
             /nullif(count(*) filter (where verdict in ('improved','no_change','worse')),0),1), null)
      into v_corr from outcome_record where actor = r.agent_key;
    -- reliability: runs that did not error.
    -- NOTE (10 Aug 2026): for EMPLOYEES this is the wrong table — agent_runs is the cron log and
    -- only nine of its 111 agent values are org_agents keys. Left alone deliberately: every value
    -- present is >= 93, so it only ever raises a score. Do not "fix" it into something that starts
    -- lowering scores without first deciding what employee reliability means.
    select coalesce(round(100.0*count(*) filter (where status<>'error')/nullif(count(*),0),1), null)
      into v_rel from agent_runs where agent = r.agent_key and started_at > now()-interval '30 days';
    -- cost efficiency: share of calls a cheaper model could NOT have served
    select coalesce(round(100.0*count(*) filter (where not coalesce(could_be_cheaper,false))/nullif(count(*),0),1), null)
      into v_cost from ai_cost_log where agent_key = r.agent_key and occurred_at > now()-interval '30 days';

    -- learning speed: UNMEASURABLE, so NULL for everyone. See the header. author_verified has not
    -- been written since 28 July and no routine in the estate produces one; unvalidated grows daily.
    -- Scoring the ratio punishes employees for learning. Revive this the day a validator exists,
    -- by scoring over knowledge that has actually been through review.
    v_learn := null;

    -- collaboration: reviews it took part in that reached approval, over DECIDED VERDICTS ONLY.
    -- 'drafted' rows are undecided (reviewer_agent is null on all 208) and 'owned'/'hold'/'required'
    -- are states, not verdicts. Counting them as non-approvals scored cpo 0% for owning eight items.
    select coalesce(round(100.0*count(*) filter (where decision='approve')/nullif(count(*),0),1), null)
      into v_collab from review_chain
     where (author_agent = r.agent_key or reviewer_agent = r.agent_key)
       and decision in ('approve','reject','request_revision');

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

  -- ...and recovery is a real consequence too. Without this the line above is a one-way ratchet:
  -- an employee that recovers stays gated for ever. Narrower than the demotion on purpose — only
  -- grants whose own note records the action as advisory-safe, and only once the employee is off
  -- probation. Rows gated by DESIGN keep their gate. See the header for the full 12 / 22 split.
  with restored as (
    update employee_authority a set max_tier='autonomous'
      from agent_reputation p
     where p.agent_key=a.agent_key
       and a.max_tier='gated'
       and p.tier <> 'probation'
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
    jsonb_build_object('scored',n,'gated',v_gated,'restored',v_restored),
    'Reputation recomputed for '||n||' employee(s). Probation demotes autonomous authority to gated ('
    ||v_gated||' this run); recovery restores advisory-safe grants ('||v_restored||' this run).');
  return jsonb_build_object('scored',n,'gated',v_gated,'restored',v_restored);
end $function$;

-- CREATE OR REPLACE preserves the existing ACL, so this adds nothing to
-- anon_security_definer_function_executable. Revoked anyway so the intent is in the migration
-- rather than in a grant nobody can see.
revoke execute on function public.fn_reputation_recompute() from public, anon, authenticated;

-- TWO OF THE SIX REPUTATION DIMENSIONS SCORE NOISE, AND reputation_weekly DEMOTES ON IT AT 07:00.
--
-- fn_reputation_recompute runs `0 7 * * 1`. Tier < 50 is probation, and probation is a real
-- consequence: the function itself sets employee_authority.max_tier='gated', and fn_check_spend
-- enforces it. Predicted read-only against production at 03:15 UTC on 2026-08-10, before the run:
-- FIVE employees below 50 (legal 43.8, cpo 45.0, learning_dev_mgr 45.2, analytics 46.3,
-- ops_director 49.5), THREE of them newly demoted. Every one of the five is below the line because
-- of the two dimensions below, and no other reason — correctness, reliability and cost_efficiency
-- are NULL for all five (0 graded outcomes, 0 runs, 0 model calls).
--
-- 1. learning_speed STILL MEASURES A FROZEN SEED. Last session established that nothing in the
--    estate ever writes author_verified and nulled the dimension when an agent had ZERO validated
--    rows. That was half the fix. Measured today:
--        author_verified  292 rows, created 24-28 JULY ONLY, 4 owners, none since
--        unvalidated    1,694 rows, created 23 Jun -> 10 AUG (today), 23 owners, still growing
--    So the ratio is a frozen July seed over a denominator that grows every time an employee
--    learns anything. The score falls monotonically with work done, and an agent holding one
--    seeded row out of twenty-two scores 4.5 rather than NULL — the same backwards incentive the
--    previous fix named, one step removed. There is no validated_at column, so no data-driven
--    liveness guard is sound either.
--    FIX: NULL for everyone. The dimension cannot mean anything until something validates
--    knowledge. Building that validator is the real fix and is NOT done here — this only stops the
--    estate demoting people on a number that measures which seed batch they inherited.
--    Note this makes s32-reputation-six-dimensions HARDER, not easier: it can never read 6 of 6
--    until a validator exists. That is the honest state.
--
-- 2. collaboration COUNTS UNDECIDED DRAFTS AND OWNERSHIP MARKERS AS FAILED REVIEWS.
--    `count(*) filter (where decision='approve') / count(*)` over every review_chain row the agent
--    touched. But `decision` mixes verdicts with states, and `stage` proves it:
--        approve           747   dept_review / published / cos_review / approval   <- verdict
--        (null)            208   stage 'drafted', reviewer_agent NULL on ALL 208   <- never reviewed
--        owned             183   stage 'ownership', first appeared 6 Aug           <- ownership marker
--        hold               39   stage 'approval'                                  <- a state
--        request_revision    8   dept_review                                       <- verdict
--        reject              2   dept_review                                       <- verdict
--        required            1   stage 'collaboration'                             <- a marker
--    cpo has EIGHT rows, all 'owned', and scores 0.0% collaboration for having taken ownership of
--    eight things. ops_director has 30 approve, 2 request_revision, 1 reject and 34 'owned', and
--    scores 44.8% instead of 90.9%. The 'owned' stage landed on 6 Aug and began dragging scores
--    down four days later.
--    FIX: score over decided verdicts only — approve / (approve + reject + request_revision).
--    An agent with no verdicts scores NULL, exactly as the other dimensions do when unmeasured.
--
-- Predicted after both fixes, same read-only arithmetic: 60 standard, 6 trusted, ZERO on probation,
-- zero demotions. Nobody is on probation because nothing real has been measured about them yet;
-- a flat 50 is the honest answer and probation from noise is not.

create or replace function public.fn_reputation_recompute()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; n int := 0; v_score numeric; v_tier text;
  v_corr numeric; v_rel numeric; v_cost numeric; v_learn numeric; v_collab numeric;
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
  update employee_authority a set max_tier='gated'
   from agent_reputation p
  where p.agent_key=a.agent_key and p.tier='probation' and a.max_tier='autonomous';

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('reputation',now(),now(),'ok',jsonb_build_object('scored',n),
    'Reputation recomputed for '||n||' employee(s). Probation demotes autonomous authority to gated.');
  return jsonb_build_object('scored',n);
end $function$;

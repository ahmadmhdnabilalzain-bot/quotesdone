-- EVERY EMPLOYEE EARNS REPUTATION ON ALL SIX DIMENSIONS, FROM FACTS ALREADY RECORDED.
--
-- Measured 3 Sep 2026 on production: agent_reputation held 93 rows with decision_quality and
-- learning_speed NULL on all 93, correctness NULL on 77, cost_efficiency on 76, reliability on 76,
-- collaboration on 69 — last computed 12 Aug. Two causes, both in fn_reputation_recompute:
--
--   1. Every dimension was a rate over a 30-DAY WINDOW ending now(). A window is a clock, and a
--      clock cannot tell an idle employee from a bad one, which is why the routine had to pause
--      itself for the founder's stand-down and then wait 30 days after the resume. The dimensions
--      below are rates over EVENTS — every graded outcome, review, decision, task, training attempt
--      and model call the employee has on record — so an idle month adds no evidence and lowers
--      nothing, and no hold logic is needed to keep the score honest.
--   2. A dimension with no event was NULL, deliberately ("no training is not slow learning"). Right
--      in spirit, but it left the column unscorable and the spec asks for six dimensions on every
--      employee. The answer is a stated prior, not a hidden default: each dimension is the posterior
--      mean under a neutral prior of 50 with the weight of 5 observations,
--          dim = (50 * 5 + rate * n) / (5 + n)
--      and `evidence` records n per dimension beside it. An employee with no evidence reads exactly
--      50 with n = 0 on every axis, tier 'unmeasured', score NULL — the number says "prior" in as
--      many words, and the counts are what the founder sees. Nothing is fabricated: every n is a
--      count of rows that exist.
--
-- The six dimensions and their sources (the tables that already hold the facts):
--   correctness      outcome_record verdicts on the employee's actions (improved vs worse/no_change)
--                    + review_chain decisions on work it AUTHORED (approve vs reject/revision)
--   decision_quality decision_log rows by the employee that state a confidence, a source and a reason
--   learning_speed   agent_training_attempt graded rows it passed
--   cost_efficiency  ai_cost_log calls by the employee a cheaper model could NOT have served
--   collaboration    review_chain decisions it GAVE as reviewer that carry a reason (engaged review)
--   reliability      org_tasks assigned to it that reached done (vs escalated; cancelled excluded —
--                    the 16 Aug stand-down cancelled 527 at once and that is not the employee's doing)
--                    + agent_runs under its key that did not error, for the keys that have runs
--
-- Population: every org_agents row, active or not, so no existing reputation row is left with a
-- NULL. Weights unchanged (correctness .30, reliability .30, cost .15, learning .15, collaboration
-- .10); decision_quality stays measured-but-unweighted for the reason the 27 Aug note gave.
-- Probation still demotes autonomous authority to gated and recovery still restores it, both
-- audited in autonomy_control_audit. A hold that is actually open still pauses the routine; the
-- 30-day post-resume wait is gone because the dimensions no longer read a window.
--
-- reputation_weekly (job 161) is re-enabled as a traced kernel component; component
-- cron:reputation_weekly already carries ai_director / people_ops on production.
--
--   node scripts/apply_sql.mjs scripts/sql/reputation_six_dimensions_from_recorded_facts.sql --apply --ddl

alter table public.agent_reputation
  add column if not exists evidence jsonb not null default '{}'::jsonb;

comment on column public.agent_reputation.evidence is
  'Observation count per dimension behind the posterior mean (prior 50, weight 5). n = 0 means the dimension reads the prior, not a measurement.';

create or replace function public.fn_reputation_recompute()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  r record; n int := 0; v_score numeric; v_tier text;
  v_gated int := 0; v_restored int := 0; v_unmeasured int := 0;
  v_hold record;
  k_prior constant numeric := 5;    -- weight of the neutral prior, in observations
  k_mid   constant numeric := 50;   -- the prior itself
  -- per-dimension (hits, n)
  c_hit numeric; c_n numeric;  q_hit numeric; q_n numeric;  l_hit numeric; l_n numeric;
  e_hit numeric; e_n numeric;  b_hit numeric; b_n numeric;  y_hit numeric; y_n numeric;
  v_corr numeric; v_decq numeric; v_learn numeric; v_cost numeric; v_collab numeric; v_rel numeric;
  v_total numeric;
  post constant text := 'posterior';
begin
  -- A hold the founder actually holds open still pauses scoring; authority must not move under it.
  select s.id, s.stood_down_at into v_hold
    from public.company_stand_down s where s.resumed_at is null
   order by s.stood_down_at desc limit 1;
  if v_hold.id is not null then
    return jsonb_build_object('ok', false, 'status', 'PAUSED_BY_FOUNDER_STANDDOWN',
      'scored', 0, 'gated', 0, 'restored', 0, 'unmeasured', 0,
      'stand_down_id', v_hold.id, 'since', v_hold.stood_down_at,
      'note', 'No employee is scored, promoted or demoted while a stand-down is open.');
  end if;

  for r in select a.agent_key from public.org_agents a order by a.agent_key loop
    -- correctness: graded outcomes of its actions + review verdicts on work it authored
    select count(*) filter (where verdict = 'improved'),
           count(*) filter (where verdict in ('improved','no_change','worse'))
      into c_hit, c_n from public.outcome_record where actor = r.agent_key;
    select c_hit + count(*) filter (where decision = 'approve'),
           c_n + count(*)
      into c_hit, c_n from public.review_chain
     where author_agent = r.agent_key and decision in ('approve','reject','request_revision');

    -- decision quality: decisions a human could review (confidence + source + reason)
    select count(*) filter (where l.confidence is not null
                              and l.sources is not null and l.sources::text not in ('null','[]','{}','""')
                              and l.reasons is not null and l.reasons::text not in ('null','[]','{}','""')),
           count(*)
      into q_hit, q_n from public.decision_log l where l.actor = r.agent_key;

    -- learning speed: graded training attempts it passed
    select count(*) filter (where passed), count(*)
      into l_hit, l_n from public.agent_training_attempt
     where agent_key = r.agent_key and passed is not null;

    -- cost efficiency: calls a cheaper model could NOT have served
    select count(*) filter (where not coalesce(could_be_cheaper, false)), count(*)
      into e_hit, e_n from public.ai_cost_log where agent_key = r.agent_key;

    -- collaboration: reviews it gave as reviewer that carry a reason
    select count(*) filter (where nullif(btrim(coalesce(reason,'')), '') is not null), count(*)
      into b_hit, b_n from public.review_chain
     where reviewer_agent = r.agent_key and decision in ('approve','reject','request_revision','hold');

    -- reliability: assigned tasks that reached done (escalated counts against; cancelled excluded)
    -- + runs under its own key that did not error
    select count(*) filter (where status = 'done'), count(*)
      into y_hit, y_n from public.org_tasks
     where assigned_agent = r.agent_key and status in ('done','escalated');
    select y_hit + count(*) filter (where status <> 'error'), y_n + count(*)
      into y_hit, y_n from public.agent_runs where agent = r.agent_key;

    v_corr  := round((k_mid*k_prior + 100.0*c_hit) / (k_prior + c_n), 1);
    v_decq  := round((k_mid*k_prior + 100.0*q_hit) / (k_prior + q_n), 1);
    v_learn := round((k_mid*k_prior + 100.0*l_hit) / (k_prior + l_n), 1);
    v_cost  := round((k_mid*k_prior + 100.0*e_hit) / (k_prior + e_n), 1);
    v_collab:= round((k_mid*k_prior + 100.0*b_hit) / (k_prior + b_n), 1);
    v_rel   := round((k_mid*k_prior + 100.0*y_hit) / (k_prior + y_n), 1);
    v_total := c_n + q_n + l_n + e_n + b_n + y_n;

    if v_total = 0 then
      v_score := null; v_tier := 'unmeasured'; v_unmeasured := v_unmeasured + 1;
    else
      v_score := round(v_corr*0.30 + v_rel*0.30 + v_cost*0.15 + v_learn*0.15 + v_collab*0.10, 1);
      v_tier := case when v_score >= 85 then 'senior_trusted'
                     when v_score >= 70 then 'trusted'
                     when v_score >= 50 then 'standard' else 'probation' end;
    end if;

    insert into public.agent_reputation
      (agent_key, correctness, reliability, cost_efficiency, learning_speed, collaboration,
       decision_quality, score, tier, computed_at, evidence)
    values (r.agent_key, v_corr, v_rel, v_cost, v_learn, v_collab, v_decq, v_score, v_tier, now(),
            jsonb_build_object('method', post, 'prior', k_mid, 'prior_weight', k_prior,
              'correctness', c_n, 'decision_quality', q_n, 'learning_speed', l_n,
              'cost_efficiency', e_n, 'collaboration', b_n, 'reliability', y_n, 'total', v_total))
    on conflict (agent_key) do update set
      correctness = excluded.correctness, reliability = excluded.reliability,
      cost_efficiency = excluded.cost_efficiency, learning_speed = excluded.learning_speed,
      collaboration = excluded.collaboration, decision_quality = excluded.decision_quality,
      score = excluded.score, tier = excluded.tier, computed_at = now(), evidence = excluded.evidence;
    n := n + 1;
  end loop;

  -- probation is a real consequence: any agent below the floor loses autonomous authority.
  with demoted as (
    update public.employee_authority a set max_tier = 'gated'
      from public.agent_reputation p
     where p.agent_key = a.agent_key and p.tier = 'probation' and a.max_tier = 'autonomous'
    returning a.agent_key, a.action_class)
  insert into public.autonomy_control_audit (object, op, direction, old_value, new_value, reason)
  select 'employee_authority:' || agent_key || '/' || action_class, 'reputation_demote', 'tighten',
         'autonomous', 'gated', 'reputation tier fell to probation'
    from demoted;
  get diagnostics v_gated = row_count;

  -- ...and recovery is a real consequence too, only for a tier earned from a reading.
  with restored as (
    update public.employee_authority a set max_tier = 'autonomous'
      from public.agent_reputation p
     where p.agent_key = a.agent_key and a.max_tier = 'gated'
       and p.tier in ('standard','trusted','senior_trusted')
       and a.note = 'Advisory-safe action, may run autonomously'
    returning a.agent_key, a.action_class)
  insert into public.autonomy_control_audit (object, op, direction, old_value, new_value, reason)
  select 'employee_authority:' || agent_key || '/' || action_class, 'reputation_restore', 'loosen',
         'gated', 'autonomous',
         'reputation recovered above probation and the grant note records the action as advisory-safe'
    from restored;
  get diagnostics v_restored = row_count;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('reputation', now(), now(), 'ok',
    jsonb_build_object('scored', n, 'gated', v_gated, 'restored', v_restored, 'unmeasured', v_unmeasured),
    'Reputation recomputed for ' || n || ' employee(s) on six dimensions from recorded facts '
    || '(posterior mean, prior 50 with weight 5; evidence counts stored per dimension). '
    || v_unmeasured || ' have no evidence on any dimension and carry a NULL score. '
    || 'Probation demoted ' || v_gated || ' autonomous grant(s) to gated; recovery restored ' || v_restored || '.');
  return jsonb_build_object('ok', true, 'scored', n, 'gated', v_gated, 'restored', v_restored,
                            'unmeasured', v_unmeasured);
end
$function$;

-- The weekly cron runs again, traced through the kernel. The component row on production already
-- carries ai_director / people_ops; the wrap early-returns on a re-apply, so the role is reconciled.
select public.fn_kernel_wrap_and_enable_cron(161, 'ai_director', 'people_ops');
update public.phase_c_component c
   set accountable_role_id = 'ai_director', department_id = 'people_ops', activation_state = 'active'
  from public.phase_c_system_execution_wrapper w
 where w.jobid = 161 and c.component_id = w.component_id;

do $$
declare v_bad int;
begin
  select count(*) into v_bad
    from public.phase_c_system_execution_wrapper w
    join public.phase_c_component c on c.component_id = w.component_id
   where w.jobid = 161
     and not exists (select 1 from public.org_role o where o.role_id = c.accountable_role_id);
  if v_bad > 0 then
    raise exception 'reputation_weekly: accountable role does not resolve in org_role';
  end if;
end $$;

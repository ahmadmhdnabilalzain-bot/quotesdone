-- A TIER IS A CONSEQUENCE, AND A CONSEQUENCE NEEDS EVIDENCE: TEN OBSERVATIONS ON TWO DIMENSIONS.
--
-- The first run of the six-dimension recompute (reputation_six_dimensions_from_recorded_facts.sql,
-- 3 Sep 2026) put 12 employees on probation and demoted 8 autonomous grants. Read the evidence
-- column and eight of the twelve had exactly ONE observation — a single escalated task — and one
-- had 25 observations on cost efficiency alone, every one of them the router's choice of model, not
-- the employee's. A neutral prior sits on the probation line, so one bad event on one axis tips the
-- score under it. That is the "score that fell because the clock moved" shape with a prior instead
-- of a clock: the number was arithmetic, the consequence was not earned.
--
-- The rule now: a tier other than 'standard' — probation below, trusted and senior_trusted above —
-- needs at least 10 observations in total AND evidence on at least two dimensions. Below that the
-- employee is 'standard' and the evidence column says provisional=true, with the score still
-- computed and stored. Unmeasured (no evidence at all) is unchanged. Demotion and recovery then
-- act on tiers that were earned.
--
-- The eight grants the first run demoted are restored here by the same mechanism — a reputation
-- tier that is no longer probation lifts a demotion the recompute itself made — and each reversal
-- is written to autonomy_control_audit with the reason, so the ledger shows the demotion, the rule
-- change and the reversal in order. Nothing is deleted from the audit.
--
--   node scripts/apply_sql.mjs scripts/sql/reputation_tiers_need_ten_observations.sql --apply --ddl

create or replace function public.fn_reputation_recompute()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  r record; n int := 0; v_score numeric; v_tier text;
  v_gated int := 0; v_restored int := 0; v_unmeasured int := 0; v_provisional int := 0;
  v_hold record;
  k_prior constant numeric := 5;    -- weight of the neutral prior, in observations
  k_mid   constant numeric := 50;   -- the prior itself
  k_floor constant numeric := 10;   -- observations needed before a tier other than standard is assigned
  -- per-dimension (hits, n)
  c_hit numeric; c_n numeric;  q_hit numeric; q_n numeric;  l_hit numeric; l_n numeric;
  e_hit numeric; e_n numeric;  b_hit numeric; b_n numeric;  y_hit numeric; y_n numeric;
  v_corr numeric; v_decq numeric; v_learn numeric; v_cost numeric; v_collab numeric; v_rel numeric;
  v_total numeric; v_dims int; v_provisional_row boolean;
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
    v_dims  := (c_n > 0)::int + (q_n > 0)::int + (l_n > 0)::int + (e_n > 0)::int + (b_n > 0)::int + (y_n > 0)::int;
    v_provisional_row := false;

    if v_total = 0 then
      v_score := null; v_tier := 'unmeasured'; v_unmeasured := v_unmeasured + 1;
    else
      v_score := round(v_corr*0.30 + v_rel*0.30 + v_cost*0.15 + v_learn*0.15 + v_collab*0.10, 1);
      if v_total < k_floor or v_dims < 2 then
        v_tier := 'standard'; v_provisional_row := true; v_provisional := v_provisional + 1;
      else
        v_tier := case when v_score >= 85 then 'senior_trusted'
                       when v_score >= 70 then 'trusted'
                       when v_score >= 50 then 'standard' else 'probation' end;
      end if;
    end if;

    insert into public.agent_reputation
      (agent_key, correctness, reliability, cost_efficiency, learning_speed, collaboration,
       decision_quality, score, tier, computed_at, evidence)
    values (r.agent_key, v_corr, v_rel, v_cost, v_learn, v_collab, v_decq, v_score, v_tier, now(),
            jsonb_build_object('method', post, 'prior', k_mid, 'prior_weight', k_prior,
              'tier_floor', k_floor, 'provisional', v_provisional_row, 'dimensions_with_evidence', v_dims,
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

  -- ...and recovery is a real consequence too: a grant this routine demoted comes back when the
  -- tier is no longer probation, and an advisory-safe grant comes back on any earned tier.
  with restored as (
    update public.employee_authority a set max_tier = 'autonomous'
      from public.agent_reputation p
     where p.agent_key = a.agent_key
       and a.max_tier = 'gated'
       and p.tier in ('standard','trusted','senior_trusted')
       and (a.note = 'Advisory-safe action, may run autonomously'
            or exists (select 1 from public.autonomy_control_audit u
                        where u.op = 'reputation_demote'
                          and u.object = 'employee_authority:' || a.agent_key || '/' || a.action_class
                          and not exists (select 1 from public.autonomy_control_audit v
                                           where v.op = 'reputation_restore' and v.object = u.object and v.at > u.at)))
    returning a.agent_key, a.action_class)
  insert into public.autonomy_control_audit (object, op, direction, old_value, new_value, reason)
  select 'employee_authority:' || agent_key || '/' || action_class, 'reputation_restore', 'loosen',
         'gated', 'autonomous',
         'reputation tier is no longer probation (a tier below standard needs 10 observations on two dimensions); a demotion this routine made is lifted'
    from restored;
  get diagnostics v_restored = row_count;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('reputation', now(), now(), 'ok',
    jsonb_build_object('scored', n, 'gated', v_gated, 'restored', v_restored, 'unmeasured', v_unmeasured, 'provisional', v_provisional),
    'Reputation recomputed for ' || n || ' employee(s) on six dimensions from recorded facts '
    || '(posterior mean, prior 50 with weight 5; evidence counts stored per dimension). '
    || v_unmeasured || ' have no evidence on any dimension and carry a NULL score; ' || v_provisional
    || ' are provisional standard with fewer than 10 observations or evidence on one dimension only. '
    || 'Probation demoted ' || v_gated || ' autonomous grant(s) to gated; recovery restored ' || v_restored || '.');
  return jsonb_build_object('ok', true, 'scored', n, 'gated', v_gated, 'restored', v_restored,
                            'unmeasured', v_unmeasured, 'provisional', v_provisional);
end
$function$;

-- Re-score under the floor; the recovery clause lifts the demotions the first run made.
select public.fn_reputation_recompute();

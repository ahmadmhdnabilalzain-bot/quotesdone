-- Stages 8, 10 and 11 — freshness, the learning loop, and automatic remediation.

-- ─────────────────────────────────────────────────────────── freshness (Stage 8)
-- Knowledge that is past its review date is still returned, but it is returned LABELLED.
-- Silently serving an expired record as current is the failure this guards against; hiding
-- it would be a different failure, because the agent would then have no knowledge at all
-- and no reason to say so.
create or replace function fn_knowledge_freshness_sweep() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_stale int; v_fresh int;
begin
  update ops_knowledge set source_freshness = 'stale'
   where review_after is not null and review_after < current_date
     and source_freshness <> 'stale';
  get diagnostics v_stale = row_count;
  update ops_knowledge set source_freshness = 'stable'
   where source_freshness = 'stale'
     and (review_after is null or review_after >= current_date);
  get diagnostics v_fresh = row_count;
  return jsonb_build_object('marked_stale', v_stale, 'restored', v_fresh, 'swept_at', now());
end $$;
revoke all on function fn_knowledge_freshness_sweep() from public;

-- ──────────────────────────────────────────────────────── proposed lessons (Stage 10)
-- A single outcome does not establish a general lesson, and a poor outcome does not by
-- itself mean a poor decision. So a proposal must name the evidence it rests on, and it
-- lands as `proposed` — invisible to retrieval — until someone other than its author
-- validates it.
create or replace function fn_propose_lesson(
  p_agent_key   text,
  p_topic       text,
  p_statement   text,
  p_evidence    jsonb,
  p_confidence  numeric default 0.5,
  p_valid_until date default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_id bigint;
  v_obs int := coalesce(jsonb_array_length(p_evidence->'observations'), 0);
begin
  if p_agent_key is null or not exists (select 1 from org_agents where agent_key = p_agent_key) then
    raise exception 'unknown agent %', p_agent_key;
  end if;
  if coalesce(btrim(p_statement), '') = '' then
    raise exception 'a lesson needs a statement';
  end if;
  -- Two independent observations minimum. One outcome is an anecdote; the loop is allowed
  -- to record it as evidence but not to call it a lesson.
  if v_obs < 2 then
    return jsonb_build_object('accepted', false, 'reason', 'insufficient_evidence',
      'detail', format('a proposed lesson needs at least 2 observations; %s supplied', v_obs));
  end if;

  insert into agent_knowledge
    (agent_key, topic, content, priority, layer, source_ref, owner_agent, version,
     confidence, validation_status, review_due, valid_until, supporting_evidence)
  values (p_agent_key, p_topic, p_statement, 5, 'experience', 'learning_loop', p_agent_key, 1,
          least(coalesce(p_confidence, 0.5), 0.9), 'proposed',
          current_date + 30, p_valid_until, p_evidence::text)
  returning id into v_id;

  return jsonb_build_object('accepted', true, 'lesson_id', v_id, 'validation_status', 'proposed',
    'note', 'not retrievable until validated by someone other than its author');
end $$;
revoke all on function fn_propose_lesson(text, text, text, jsonb, numeric, date) from public;
grant execute on function fn_propose_lesson(text, text, text, jsonb, numeric, date) to service_role;

-- Validation. The proposer may not validate its own lesson; that is the whole separation.
create or replace function fn_validate_lesson(
  p_lesson_id bigint, p_validator text, p_verdict text, p_reason text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v agent_knowledge; v_mgr text;
begin
  select * into v from agent_knowledge where id = p_lesson_id;
  if v.id is null then raise exception 'unknown lesson %', p_lesson_id; end if;
  if v.validation_status <> 'proposed' then
    return jsonb_build_object('ok', false, 'reason', 'not_proposed', 'status', v.validation_status);
  end if;
  if p_validator = v.agent_key then
    return jsonb_build_object('ok', false, 'reason', 'self_validation_refused',
      'detail', 'the agent that proposed a lesson cannot be the one that validates it');
  end if;
  if p_verdict not in ('validated','rejected') then
    raise exception 'verdict must be validated or rejected, got %', p_verdict;
  end if;

  select manager_key into v_mgr from org_agents where agent_key = v.agent_key;
  update agent_knowledge
     set validation_status = p_verdict,
         updated_at = now(),
         supporting_evidence = coalesce(supporting_evidence, '') ||
           format(E'\n[%s by %s%s] %s', p_verdict, p_validator,
                  case when p_validator = v_mgr then ' (line manager)' else '' end,
                  coalesce(p_reason, ''))
   where id = p_lesson_id;
  return jsonb_build_object('ok', true, 'lesson_id', p_lesson_id, 'status', p_verdict,
                            'validator', p_validator, 'was_line_manager', p_validator = v_mgr);
end $$;
revoke all on function fn_validate_lesson(bigint, text, text, text) from public;
grant execute on function fn_validate_lesson(bigint, text, text, text) to service_role;

-- New evidence can retire an old lesson. Supersession is recorded, not overwritten, so the
-- history of what the company believed and when stays readable.
create or replace function fn_supersede_lesson(
  p_old bigint, p_new bigint, p_reason text
) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  update agent_knowledge set validation_status = 'superseded', supersedes_id = null,
         supporting_evidence = coalesce(supporting_evidence,'') || E'\n[superseded by ' || p_new || '] ' || coalesce(p_reason,''),
         updated_at = now()
   where id = p_old;
  update agent_knowledge set supersedes_id = p_old, updated_at = now() where id = p_new;
  return jsonb_build_object('ok', found, 'old', p_old, 'new', p_new);
end $$;
revoke all on function fn_supersede_lesson(bigint, bigint, text) from public;

-- ─────────────────────────────────────────────── automatic remediation (Stage 11)
-- Training cases are handed out, never listed. An agent that could enumerate the corpus
-- would learn the order rather than the competency, so selection is randomised and scoped,
-- and a case already seen for one purpose is not reused for the retest.
create or replace function fn_assign_training(
  p_agent_key    text,
  p_competency   text,
  p_purpose      text default 'practice',
  p_n            integer default 5
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_roles text[]; v_dept text; v_rows jsonb;
begin
  if p_purpose not in ('practice','retest','drift_check') then
    raise exception 'purpose must be practice, retest or drift_check';
  end if;
  select array_agg(packaged_role_id) into v_roles from org_role_identity where agent_key = p_agent_key;
  select packaged_department into v_dept from org_role_identity where agent_key = p_agent_key limit 1;
  if v_roles is null then
    return jsonb_build_object('assigned', 0, 'reason', 'agent has no role identity');
  end if;

  with pool as (
    select c.case_id, c.case_family, c.competency, c.scope_key
      from agent_training_case c
     -- The parentheses matter: AND binds tighter than OR, so without them the competency
     -- filter applied only to the department branch and every role case slipped past it.
     where ((c.scope_type = 'role' and c.scope_key = any(v_roles))
         or (c.scope_type = 'department' and c.scope_key = v_dept))
       and (p_competency is null or c.competency = p_competency)
  ), unseen as (
    select p.* from pool p
     where not exists (select 1 from agent_training_attempt a
                        where a.agent_key = p_agent_key and a.case_id = p.case_id)
     order by md5(p.case_id || p_agent_key || p_purpose)     -- stable per (agent,purpose), not an ordered list
     limit greatest(coalesce(p_n, 5), 1)
  ), ins as (
    insert into agent_training_attempt (agent_key, case_id, purpose, competency)
    select p_agent_key, case_id, p_purpose, competency from unseen
    on conflict (agent_key, case_id, purpose) do nothing
    returning id, case_id
  )
  select jsonb_agg(jsonb_build_object('attempt_id', i.id, 'case_id', i.case_id,
                                      'payload', c.payload))
    into v_rows
    from ins i join agent_training_case c on c.case_id = i.case_id;

  return jsonb_build_object('assigned', coalesce(jsonb_array_length(v_rows), 0),
                            'purpose', p_purpose, 'cases', coalesce(v_rows, '[]'::jsonb));
end $$;
revoke all on function fn_assign_training(text, text, text, integer) from public;
grant execute on function fn_assign_training(text, text, text, integer) to service_role;

create or replace function fn_open_remediation(
  p_agent_key text, p_failure_class text, p_competency text, p_detail jsonb default '{}'::jsonb
) returns bigint
language sql security definer set search_path = public as $$
  insert into agent_remediation (agent_key, failure_class, competency, detail, status, blocks_autonomy)
  values (p_agent_key, p_failure_class, p_competency, coalesce(p_detail,'{}'::jsonb), 'open',
          -- blocks_autonomy defaults true, but a KPI-miss remediation is a COACHING signal (it opens a
          -- task + assigns practice), NOT grounds to freeze the agent from all autonomous action.
          -- Blocking autonomy on a routine KPI-review flag freezes working agents wholesale — the first
          -- weekly review opened 30 such remediations (including cfo), and the autonomy guard then
          -- correctly refused those agents' actions, stalling the approval/dispatch path. Serious
          -- classes (security incidents, money, proven-harmful action) still block by default.
          p_failure_class not in ('kpi_miss'))
  returning id;
$$;
revoke all on function fn_open_remediation(text, text, text, jsonb) from public;
grant execute on function fn_open_remediation(text, text, text, jsonb) to service_role;

-- Close the loop: score a retest on cases the agent has not seen, compare with the baseline,
-- and keep autonomy blocked until it actually improves — within an attempt and cost ceiling,
-- after which it escalates instead of grinding.
create or replace function fn_remediation_step(
  p_id bigint, p_score numeric, p_cost_aed numeric default 0
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r agent_remediation;
begin
  select * into r from agent_remediation where id = p_id for update;
  if r.id is null then raise exception 'unknown remediation %', p_id; end if;

  update agent_remediation
     set attempts = attempts + 1,
         cost_aed = cost_aed + coalesce(p_cost_aed, 0),
         baseline_score = coalesce(baseline_score, p_score),
         latest_score = p_score,
         status = case
           when p_score >= 0.8 and coalesce(baseline_score, p_score) <= p_score then 'passed'
           when attempts + 1 >= max_attempts or cost_aed + coalesce(p_cost_aed,0) >= max_cost_aed then 'escalated'
           else 'retesting' end,
         blocks_autonomy = not (p_score >= 0.8 and coalesce(baseline_score, p_score) <= p_score),
         closed_at = case when p_score >= 0.8 then now() else null end
   where id = p_id
   returning * into r;

  return jsonb_build_object('id', r.id, 'status', r.status, 'attempts', r.attempts,
                            'baseline', r.baseline_score, 'latest', r.latest_score,
                            'blocks_autonomy', r.blocks_autonomy, 'cost_aed', r.cost_aed);
end $$;
revoke all on function fn_remediation_step(bigint, numeric, numeric) from public;
grant execute on function fn_remediation_step(bigint, numeric, numeric) to service_role;

-- The gate a consequential action must pass. An agent with an open remediation on a critical
-- competency is advisory until it clears.
create or replace function fn_agent_autonomy_blocked(p_agent_key text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'agent_key', p_agent_key,
    'blocked', exists (select 1 from agent_remediation
                        where agent_key = p_agent_key and blocks_autonomy and status <> 'passed'),
    'open_remediations', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'failure_class', failure_class, 'competency', competency, 'status', status))
      from agent_remediation where agent_key = p_agent_key and status <> 'passed'), '[]'::jsonb),
    'readiness', coalesce((select jsonb_agg(distinct readiness) from org_role_identity
                            where agent_key = p_agent_key), '[]'::jsonb));
$$;
revoke all on function fn_agent_autonomy_blocked(text) from public;
grant execute on function fn_agent_autonomy_blocked(text) to service_role;

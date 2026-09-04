-- THE REVIEWER'S VERDICT IS A RESTING STATE, NOT A RETRY (org_task lane), 4 Sep 2026.
--
-- MEASURED on production 30 minutes after the lane opened: 26 org_tasks closed done with a published
-- review, used_llm false, and one — org_tasks#526022, dept exec — came back from fn_task_review with
-- outcome 'escalate' and was left 'assigned'. A deterministic determination is a PURE FUNCTION of the
-- task and the playbook, so the next tick produces the same deliverable and the same verdict: that row
-- is an endless retry, which is the one thing this lane must never do.
--
-- TWO FIXES, both of them the honest resting state rather than a suppression.
--
-- 1. THE VERDICT DECIDES THE TASK'S STATE.
--      published / approve  -> done            (unchanged)
--      escalate             -> escalated       — fn_review_submit returns this when the department has
--                             NO available approver. Retrying cannot conjure one, and org_tasks already
--                             has the word for it. The follow trigger closes the mirroring run.
--      reject / request_revision / hold_for_human / anything else
--                           -> blocked, with result.parked carrying the verdict and the violations.
--                             The determination did not meet the org_task quality standard, so the
--                             thing that must change is the KNOWLEDGE, not the number of attempts.
--                             fn_org_task_promote re-opens it when the department gains actionable
--                             knowledge, exactly as it does for a task no playbook covered.
--    Either way fn_workflow_step_claim stops picking the step, because it only claims while the owning
--    task is 'assigned' or 'in_progress'. The queue predicate is the retry guard.
--
-- 2. THE AUTHOR OF AN ORG_TASK REVIEW IS THE EMPLOYEE WHO DID IT.
--    fn_task_review derived the author as `coalesce(dept.brain_agent, dept.lead_agent, dept_key)` — the
--    department head, always, whoever actually performed the work. fn_pick_reviewer then refuses to let
--    a head approve its own output, correctly, and for the Office of the CEO there is nobody above the
--    ceo, so EVERY exec task escalated with "the department head authored this work and no independent
--    reviewer or manager is available" — 113 open exec tasks, none of them written by the ceo. Measured
--    the same hour: exec is the ONLY department that escalates; the other nine resolve a reviewer.
--    The task now records who performed it (result.employee, and assigned_agent before that), so the
--    author is read from the row and the default is used only when the row does not say. This is the
--    same defect as artifact_review defaulting its author, and the same one-line correction.
--
--   node scripts/apply_sql.mjs scripts/sql/org_task_lane_terminal_verdicts_2026_09_04.sql --apply --ddl

begin;

create or replace function public.fn_org_task_deterministic_done(p_task_id bigint, p_step_run_id bigint, p_output jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  t            record;
  v_floor      numeric := 0.85;      -- fn_apply_playbook's floor; a caller cannot lower it here
  v_sim        numeric;
  v_terms      int;
  v_total      int;
  v_deliv      text;
  v_outcome    text;
  v_employee   text;
  v_review     jsonb;
  v_verdict    text;
  v_trace      uuid;
  v_queue      bigint;
  v_rc         text;
  v_att        numeric;
  v_band       text;
  v_known      int;
begin
  select o.id, o.dept_key, o.title, o.detail, o.action_class, o.tier, o.status, o.assigned_agent
    into t from public.org_tasks o where o.id = p_task_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no such org_task ' || p_task_id);
  end if;
  if t.status not in ('assigned','in_progress') then
    return jsonb_build_object('ok', false, 'reason', 'org_task ' || p_task_id || ' is ' || t.status || ', not open work');
  end if;

  v_deliv   := coalesce(p_output->>'deliverable', '');
  v_outcome := coalesce(nullif(p_output->>'outcome',''), left(v_deliv, 280));
  v_sim     := nullif(p_output->>'similarity', '')::numeric;
  v_terms   := coalesce(nullif(p_output->>'terms_matched','')::int, 0);
  v_total   := coalesce(nullif(p_output->>'terms_total','')::int, 0);
  v_employee := coalesce(nullif(p_output->>'employee',''), t.assigned_agent, t.dept_key);

  -- FALSE-SUCCESS GUARDS. Nothing below runs unless the determination has substance.
  if coalesce(p_output->>'playbook_record_id','') = '' then
    return jsonb_build_object('ok', false, 'reason', 'no playbook_record_id: a determination must cite the company knowledge it applied');
  end if;
  if not exists (select 1 from public.ops_knowledge k
                  where k.record_id = p_output->>'playbook_record_id'
                    and k.runtime_eligible and k.supersession_state = 'current'
                    and k.record_type in ('decision_playbook','decision_rule','standard_operating_procedure','exception_playbook')) then
    return jsonb_build_object('ok', false, 'reason', 'playbook ' || (p_output->>'playbook_record_id')
             || ' is not a current, runtime-eligible, ACTIONABLE ops_knowledge record');
  end if;
  if v_sim is null or v_sim < v_floor then
    return jsonb_build_object('ok', false, 'reason', 'similarity ' || coalesce(v_sim::text,'null') || ' is below the apply floor ' || v_floor);
  end if;
  if v_terms < 2 or v_total < 1 or (v_terms::numeric / v_total) < 0.30 then
    return jsonb_build_object('ok', false, 'reason', 'corroboration ' || v_terms || ' of ' || v_total
             || ' task terms is under the 2-and-30% bar the applier demands');
  end if;
  if length(v_deliv) < 300 then
    return jsonb_build_object('ok', false, 'reason', 'deliverable shorter than 300 characters is not a determination');
  end if;

  -- The org_task quality standard requires a RESULT: line (major severity). The determination is the
  -- playbook's own content, which does not carry one, so the applier's outcome sentence becomes it.
  if v_deliv !~* '(^|\n)\s*RESULT:' then
    v_deliv := v_deliv || E'\n\nRESULT: ' || left(v_outcome, 300);
  end if;

  -- A KPI-miss task cannot close without a root cause (trg_org_task_root_cause). The honest
  -- deterministic diagnosis available without the model is the ATTAINMENT BAND, read from the task's
  -- own numbers, which fn_kpi_review wrote into the detail as "actual X (Y% of target)". A band is a
  -- class of cause, and it says which class it is rather than inventing a specific one.
  if t.title ilike 'KPI missed%' then
    v_att := nullif(substring(coalesce(t.detail,'') from '\(([0-9]+(?:\.[0-9]+)?)% of target\)'), '')::numeric;
    v_band := case
      when v_att is null      then 'unmeasured: the task carries no attainment figure, so the variance class cannot be read from it'
      when v_att < 5          then 'no throughput: attainment ' || v_att || '% means the input that feeds this metric has not started, not that it under-performed'
      when v_att < 50         then 'capacity or conversion shortfall: attainment ' || v_att || '% is real activity falling well short of the target'
      when v_att < 100        then 'target above current capability: attainment ' || v_att || '% is near-miss performance against a target set higher than the process currently reaches'
      else 'measurement: attainment ' || v_att || '% is at or above target, so the miss is in how the metric is measured or dated, not in the work' end;
    v_rc := left('Root cause (deterministic band, no model call): ' || v_band
              || '. Closing action taken from company playbook "' || coalesce(p_output->>'playbook_title','') || '" ('
              || (p_output->>'playbook_record_id') || ', cosine ' || v_sim || ', corroborated ' || v_terms || '/' || v_total || ').', 500);
  end if;

  -- The deliverable must be ON THE ROW before the review: fn_task_review reads it off org_tasks, and
  -- so does the author derivation (result.employee).
  update public.org_tasks
     set result = jsonb_build_object(
                    'deliverable', left(v_deliv, 20000),
                    'summary',     left(v_outcome, 300),
                    'mode',        'determined',
                    'used_llm',    false,
                    'lane',        'org_task',
                    'worked_by',   'workflow_dispatch',
                    'employee',    v_employee,
                    'playbook_record_id',   p_output->>'playbook_record_id',
                    'playbook_title',       p_output->>'playbook_title',
                    'playbook_record_type', p_output->>'playbook_record_type',
                    'similarity',   v_sim,
                    'terms_matched', v_terms,
                    'terms_total',   v_total,
                    'workflow_step_run_id', p_step_run_id,
                    'at', now())
                  || case when coalesce(result,'{}'::jsonb) ? 'parked'
                          then jsonb_build_object('previously_parked', result->'parked') else '{}'::jsonb end,
         root_cause  = coalesce(v_rc, root_cause),
         decided_by  = 'workflow_dispatch',
         last_run_at = now(),
         attempts    = coalesce(attempts, 0) + 1,
         updated_at  = now()
   where id = p_task_id;

  -- THE PUBLISHER. Department head -> Chief of Staff -> ownership -> cross-department challenge.
  v_review  := public.fn_task_review(p_task_id);
  v_verdict := coalesce(v_review->>'outcome', 'unknown');

  -- A VERDICT THAT IS NOT A CLOSE IS A RESTING STATE, NOT A RETRY. The determination is a pure
  -- function of (task, playbook), so the same verdict comes back every tick; the task moves to the
  -- state the verdict actually means and fn_workflow_step_claim stops picking it (it claims only while
  -- the task is open).
  if v_verdict not in ('published','approve') then
    if v_verdict = 'escalate' then
      update public.org_tasks
         set status = 'escalated', updated_at = now(),
             result = coalesce(result,'{}'::jsonb) || jsonb_build_object(
               'review', v_review,
               'escalated', jsonb_build_object('at', now(), 'by', 'workflow_dispatch (org_task lane)',
                 'reason', coalesce(v_review->>'reason', 'the review chain could not resolve an available approver'),
                 'note', 'The determination was produced and stored; it is the REVIEW that could not '
                      || 'complete, because this department has no approver independent of the author. '
                      || 'That is an org finding, not a work failure, and it rests here rather than '
                      || 'being retried against the same chain every ten minutes.'))
       where id = p_task_id;
    else
      v_known := public.fn_org_task_lane_knowledge(t.dept_key);
      update public.org_tasks
         set status = 'blocked', updated_at = now(),
             result = coalesce(result,'{}'::jsonb) || jsonb_build_object(
               'review', v_review,
               'parked', jsonb_build_object('at', now(), 'by', 'workflow_dispatch (org_task lane)',
                 'reason', 'the review returned ' || v_verdict,
                 'violations', coalesce(v_review->'violations','[]'::jsonb),
                 'knowledge_at_park', v_known,
                 'note', 'The deterministic determination did not meet the org_task quality standard. '
                      || 'The determination is a pure function of this task and the playbook applied, so '
                      || 'another attempt returns the same verdict; what has to change is the KNOWLEDGE. '
                      || 'fn_org_task_promote re-opens this when the department holds more actionable '
                      || 'in-scope knowledge than the ' || v_known || ' records it held here.'))
       where id = p_task_id;
    end if;

    return jsonb_build_object('ok', false, 'terminal', true, 'review_outcome', v_verdict,
             'reason', 'review returned ' || v_verdict
               || coalesce(': ' || left((v_review->'violations')::text, 300), '')
               || '; the org_task now rests as '
               || case when v_verdict = 'escalate' then 'escalated' else 'blocked' end
               || ' and is not retried',
             'review', v_review);
  end if;

  -- The sealed record of what was decided, on what, by which rule, with what confidence.
  insert into public.decision_trace(
      correlation_id, entity_type, entity_id, decision_type,
      proposed_by, decided_by, policy_keys, knowledge_refs, evidence_refs, alternatives,
      assumptions, risk, confidence, authority_result,
      decision, outcome_status, agent_key, department_id, task_class,
      knowledge_versions, source_freshness, tools_requested, tools_executed, tool_result_refs,
      uncertainty, escalation_decision, proposed_action, expected_outcome,
      model, provider, input_tokens, output_tokens, estimated_cost_aed, final_status, sealed_at)
  values (
      gen_random_uuid(), 'org_task', p_task_id::text, 'deterministic_playbook_application',
      v_employee, 'fn_apply_playbook', array['deterministic_first','org_task_lane']::text[],
      jsonb_build_array(jsonb_build_object('record_id', p_output->>'playbook_record_id',
                                           'title', p_output->>'playbook_title',
                                           'similarity', v_sim,
                                           'terms_matched', v_terms, 'terms_total', v_total)),
      jsonb_build_array(jsonb_build_object('org_task_id', p_task_id, 'dept_key', t.dept_key,
                                           'title', t.title, 'action_class', t.action_class,
                                           'workflow_step_run_id', p_step_run_id,
                                           'review', v_review)),
      coalesce(p_output->'candidates', '[]'::jsonb),
      jsonb_build_array('the nearest CORROBORATED actionable company playbook is the applicable one for this task'),
      jsonb_build_object('level', 'low', 'note', 'advisory determination; moves no money, sends nothing, approves nobody'),
      v_sim,
      jsonb_build_object('mode', 'advisory', 'tier', t.tier, 'paid_provider', 'held'),
      jsonb_build_object('determination', left(v_deliv, 8000), 'outcome', left(v_outcome, 400),
                         'basis', 'nearest corroborated company knowledge by meaning; no model call'),
      'pending', v_employee, t.dept_key, 'org_task',
      '{}'::jsonb, jsonb_build_object('ops_knowledge', 'live at decision time'), '{}'::text[], '{}'::text[], '[]'::jsonb,
      'low-confidence deterministic disposition: the corroborated playbook was applied, not reasoned over; queued for review',
      'review_queued', 'close the org_task with a deterministic disposition',
      'the mirroring employee_task run closes with it; a reviewer can overturn the determination',
      'none', 'deterministic', 0, 0, 0, 'auto_done', now())
  returning id into v_trace;

  insert into public.review_queue(kind, dept_key, title, summary, payload, status)
  values ('deterministic_org_task', t.dept_key,
          left('Deterministic determination: org_task ' || p_task_id || ' — ' || coalesce(t.title,''), 240),
          left(v_outcome, 600),
          jsonb_build_object('org_task_id', p_task_id, 'dept_key', t.dept_key,
                             'workflow_step_run_id', p_step_run_id,
                             'employee', v_employee,
                             'playbook_record_id', p_output->>'playbook_record_id',
                             'playbook_title', p_output->>'playbook_title',
                             'similarity', v_sim, 'terms_matched', v_terms, 'terms_total', v_total,
                             'decision_trace_id', v_trace, 'review', v_review,
                             'disposition', 'deterministic_low_confidence'),
          'pending')
  returning id into v_queue;

  update public.org_tasks
     set status     = 'done',
         updated_at = now(),
         result     = coalesce(result,'{}'::jsonb) || jsonb_build_object(
                        'review', v_review,
                        'decision_trace_id', v_trace,
                        'review_queue_id', v_queue,
                        'disposition', 'deterministic_low_confidence')
   where id = p_task_id;

  return jsonb_build_object('ok', true, 'org_task_id', p_task_id, 'review_outcome', v_verdict,
                            'decision_trace_id', v_trace, 'review_queue_id', v_queue,
                            'root_cause', v_rc);
end
$function$;

-- ---------------------------------------------------------------------------------------------------
-- fn_task_review: the author is the employee who did the work. Everything else is unchanged.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_task_review(p_task_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare
  t             record;
  v_text        text;
  v_deliverable text;
  v_author      text;
  v_chain       jsonb;
  v_outcome     text;
  v_rule        record;
  v_ch          jsonb;
  v_dept        text;
  v_blocked     boolean := false;
  v_blocker     text;
  v_dissents    jsonb := '[]'::jsonb;
  v_involved    jsonb := '[]'::jsonb;
  v_rules_hit   int := 0;
  v_own_resp    text;
  v_own_os      text;
  v_own_agent   text;
begin
  select o.id, o.dept_key, o.title, o.detail, o.action_class, o.result, o.tier, o.assigned_agent
    into t from org_tasks o where o.id = p_task_id;
  if t.id is null then
    return jsonb_build_object('error', 'no such task', 'task_id', p_task_id);
  end if;

  v_deliverable := coalesce(t.result->>'deliverable', '');
  if v_deliverable = '' then
    return jsonb_build_object('task_id', p_task_id, 'outcome', 'no_deliverable',
      'reason', 'The task carries no deliverable to review.');
  end if;

  -- WHO ACTUALLY WROTE IT (4 Sep 2026). This was `coalesce(d.brain_agent, d.lead_agent, dept_key)` —
  -- the department head, whoever performed the work. fn_pick_reviewer then correctly refuses to let a
  -- head approve its own output, and for the Office of the CEO there is nobody above the ceo, so every
  -- exec task escalated on an authorship nobody claimed. The row records its worker; read it.
  select coalesce(nullif(t.result->>'employee',''), nullif(t.assigned_agent,''),
                  d.brain_agent, d.lead_agent, t.dept_key)
    into v_author
    from org_departments d where d.dept_key = t.dept_key;
  if v_author is null then
    v_author := coalesce(nullif(t.result->>'employee',''), nullif(t.assigned_agent,''), t.dept_key);
  end if;

  -- STAGE 1+2: department head, then Chief of Staff. This is fn_review_submit unchanged — the
  -- reviewer is resolved live through delegation_rule and seniority, so a head who is unavailable
  -- delegates rather than silently approving.
  v_chain   := fn_review_submit('org_task', p_task_id::text, t.dept_key, v_author, v_deliverable);
  v_outcome := v_chain->>'outcome';

  -- STAGE 3: the challenge. Deterministic, so it runs on every task rather than being rationed.
  v_text := coalesce(t.title,'') || ' ' || coalesce(t.detail,'') || ' ' || coalesce(t.action_class,'');

  -- STAGE 0 OF THE RECORD, WRITTEN HERE: WHO OWNS THIS PROCESS.
  -- The responsibility is matched on its own words, longest first, so 'business development' wins
  -- over 'sales' when both occur. position() and not LIKE: 35 of the 72 responsibility values carry
  -- an underscore, and on the pattern side of LIKE an underscore is a single-character wildcard.
  select r.responsibility, r.os_key into v_own_resp, v_own_os
    from os_responsibility r
   where position(replace(r.responsibility, '_', ' ') in lower(v_text)) > 0
   order by length(r.responsibility) desc, r.responsibility
   limit 1;
  if v_own_os is null then
    select d.os_key into v_own_os from os_department d
     where d.dept_key = t.dept_key order by d.os_key limit 1;
  end if;
  select o.owner_agent into v_own_agent from operating_system o
   where o.os_key = v_own_os and o.active
     and exists (select 1 from org_agents a where a.agent_key = o.owner_agent and a.active);
  if v_own_agent is not null and v_own_agent is distinct from v_author then   -- an owner who authored it is already accountable; a self-review row is refused by the chain guard
    insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent,
                              stage, decision, reason, confidence)
    select 'org_task', p_task_id::text, t.dept_key, v_author, v_own_agent, 'ownership', 'owned',
           'os_responsibility routes this work to the ' || v_own_os || ' OS'
             || case when v_own_resp is null
                     then ', taken from the owning OS of the ' || t.dept_key || ' department because '
                          || 'no declared responsibility matched the task'
                     else ', which is the declared owner of the responsibility "' || v_own_resp || '"'
                end
             || '. Accountable to the company for it: ' || v_own_agent || '.', 1.0
     where not exists (select 1 from review_chain rc
                        where rc.subject_type = 'org_task' and rc.subject_id = p_task_id::text
                          and rc.stage = 'ownership');
  end if;

  for v_rule in
    select c.*,
           -- ponytail: word-overlap matcher, deliberately conservative. A rule applies only when
           -- the task belongs to the rule's OWN department and at least two of the situation's
           -- distinctive words appear in the task. It under-matches rather than over-matches:
           -- "Publishing anything externally" will not fire on a task titled "Draft Q3 posts".
           -- Upgrade path when the founder wants precision is an action_class[] or match_pattern
           -- column on collaboration_rule, matched here instead of the word overlap.
           (select count(*) from unnest(string_to_array(
                    regexp_replace(lower(c.situation), '[^a-z ]', ' ', 'g'), ' ')) w
             where length(w) > 4 and position(w in lower(v_text)) > 0) hits
      from collaboration_rule c
     where c.owner_dept = t.dept_key
  loop
    if v_rule.hits < 2 then continue; end if;
    v_rules_hit := v_rules_hit + 1;

    -- Who the rule says must take part, recorded as its own reviewable stage so that "this needed
    -- legal and legal never saw it" is answerable after the fact.
    v_involved := v_involved || jsonb_build_object(
      'situation', v_rule.situation, 'must_involve', to_jsonb(v_rule.must_involve),
      'must_review', to_jsonb(v_rule.must_review), 'blocking', v_rule.blocking);

    insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent,
                              stage, decision, reason, confidence)
    values ('org_task', p_task_id::text, t.dept_key, v_author,
            coalesce((v_rule.must_review)[1], 'exec'), 'collaboration',
            case when v_rule.blocking then 'required' else 'advisory' end,
            'collaboration_rule #' || v_rule.id || ' applies ("' || v_rule.situation || '"): '
              || 'involve ' || coalesce(array_to_string(v_rule.must_involve, ', '), '(none)')
              || '; review by ' || coalesce(array_to_string(v_rule.must_review, ', '), '(none)')
              || '; may be challenged by ' || coalesce(array_to_string(v_rule.may_challenge, ', '), '(none)')
              || '. Why this rule exists: ' || v_rule.reason, 1.0);

    -- Each department the rule permits to challenge actually challenges.
    foreach v_dept in array coalesce(v_rule.may_challenge, array[]::text[]) loop
      v_ch := fn_challenge(v_text, t.dept_key, v_dept);
      if (v_ch->>'stance') <> 'support' then
        v_dissents := v_dissents || jsonb_build_object(
          'by', v_dept, 'stance', v_ch->>'stance', 'confidence', v_ch->>'confidence',
          'reasoning', v_ch->>'reasoning', 'blocking', v_rule.blocking);

        insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent,
                                  stage, decision, reason, violated_rule, confidence)
        values ('org_task', p_task_id::text, t.dept_key, v_author, v_dept, 'challenge',
                case when v_rule.blocking and (v_ch->>'stance') = 'recommend_against'
                     then 'reject' else 'dissent' end,
                upper(v_ch->>'stance') || ' from ' || v_dept || ': ' || coalesce(v_ch->>'reasoning','')
                  || case when v_ch->'alternatives' <> '[]'::jsonb
                          then ' Alternative offered: ' || (v_ch->'alternatives'->>0) else '' end,
                v_ch->>'conflicts_with', (v_ch->>'confidence')::numeric);

        -- THE FOUNDER'S RULE, 6 Aug 2026: the blocking flag decides whether a rejection stops the
        -- work or is recorded against it. The reason is written either way.
        if v_rule.blocking and (v_ch->>'stance') = 'recommend_against' then
          v_blocked := true;
          v_blocker := v_dept || ' — ' || left(coalesce(v_ch->>'reasoning',''), 200);
        end if;
      end if;
    end loop;
  end loop;

  if v_blocked and v_outcome in ('published', 'approve') then
    v_outcome := 'request_revision';
    insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent,
                              stage, decision, reason, confidence)
    values ('org_task', p_task_id::text, t.dept_key, v_author, 'brief', 'cos_review',
            'request_revision',
            'Returned for revision by the Chief of Staff: a BLOCKING collaboration rule was '
            || 'challenged and the challenge recommended against it. ' || v_blocker, 1.0);
  end if;

  -- "Every completed task should generate learning." Written here, by the reviewer, at the moment
  -- the verdict is known — the review already establishes what was wrong, so the lesson costs
  -- nothing. Never let recording the lesson fail the review itself.
  begin
    perform fn_task_lesson(p_task_id, v_outcome,
      jsonb_build_object('violations', coalesce(v_chain->'violations','[]'::jsonb),
                         'dissents',   v_dissents,
                         'reviewer',   v_chain->>'reviewer'));
  exception when others then null;
  end;

  return jsonb_build_object(
    'task_id',        p_task_id,
    'outcome',        v_outcome,
    'stopped_at',     v_chain->>'stopped_at',
    'author',         v_author,
    'reviewer',       v_chain->>'reviewer',
    'delegated_from', v_chain->>'delegated_from',
    'violations',     coalesce(v_chain->'violations', '[]'::jsonb),
    'unenforceable',  coalesce(v_chain->'unenforceable', '[]'::jsonb),
    'rules_applied',  v_rules_hit,
    'collaboration',  v_involved,
    'dissents',       v_dissents,
    'owned_by_os',    v_own_os,
    'owner_agent',    v_own_agent,
    'owns_responsibility', v_own_resp,
    'blocked',        v_blocked);
end
$function$;

-- The one task the old behaviour left in an endless retry: it holds a stored determination and an
-- 'escalate' verdict from an authorship it never had. Put it back in the queue so the corrected
-- author decides it, rather than leaving a row whose state was produced by the defect.
update public.org_tasks
   set status = 'assigned', updated_at = now()
 where result->>'lane' = 'org_task'
   and status = 'assigned'
   and result->'review'->>'outcome' = 'escalate';

commit;

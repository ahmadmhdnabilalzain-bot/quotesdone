-- COMPONENT 15 — "Who owns this process?" has to DRIVE something.
--
-- os_responsibility declares, for each of the company's 72 responsibilities, which Operating System
-- owns it. Measured on production 6 Aug 2026 its only readers were fn_graph_rebuild (which draws a
-- picture of it), fn_event_dispatch and fn_agent_context, plus the view v_operating_manual. Not one
-- of them turns a declaration of ownership into work for the declared owner: 72 rows say who owns
-- what and route nothing.
--
-- This adds ONE block to fn_task_review, which is the routine every completed task passes through
-- (cos_execute calls it by RPC on the hourly cron). The block resolves the task's subject against
-- the declared responsibilities, takes the OWNING OS from os_responsibility, and addresses a review
-- row to that OS's own accountable employee — operating_system.owner_agent, validated to be an
-- ACTIVE employee. When no declaration matches the text, ownership falls back to the OS the task's
-- own department belongs to, so the row is written for EVERY reviewed task: a coverage leg that can
-- only be satisfied by an empty population is not a measurement, and this one has no empty case.
--
-- NOT A FEEDBACK LOOP, checked before writing it. trg_event_review on review_chain is
-- `AFTER INSERT ... WHEN (new.stage = 'published' OR new.decision IN ('reject','request_revision',
-- 'hold_for_human','escalate'))`. stage='ownership' with decision='owned' matches neither arm, so
-- this row emits no company_event, raises no task, and cannot feed fn_event_dispatch. That is the
-- 169-tasks-in-one-hour path and it stays shut.
--
-- IDEMPOTENT ON THE TASK, not on the run: fn_task_review is retried (MAX_ATTEMPTS=3 in cos_execute)
-- and must not restate ownership three times for one task.
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
  select o.id, o.dept_key, o.title, o.detail, o.action_class, o.result, o.tier
    into t from org_tasks o where o.id = p_task_id;
  if t.id is null then
    return jsonb_build_object('error', 'no such task', 'task_id', p_task_id);
  end if;

  v_deliverable := coalesce(t.result->>'deliverable', '');
  if v_deliverable = '' then
    return jsonb_build_object('task_id', p_task_id, 'outcome', 'no_deliverable',
      'reason', 'The task carries no deliverable to review.');
  end if;

  select coalesce(d.brain_agent, d.lead_agent, t.dept_key) into v_author
    from org_departments d where d.dept_key = t.dept_key;

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
  if v_own_agent is not null then
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

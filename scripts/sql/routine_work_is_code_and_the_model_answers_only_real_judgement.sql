-- ROUTINE WORK IS CODE; THE MODEL ANSWERS ONLY REAL JUDGEMENT.
-- Seat: it_engineer. 24 Sep 2026. Founder rules: routine work is code, the LLM only for real judgement, 90 %+ coded;
-- ledger 890: no word matching to infer meaning. Prepared before the OpenRouter top-up on 25 Sep 2026.
--
-- WHAT WAS MEASURED (production htdblwldjkcgjvmqkbeh, reasoning_held_question, 24 Sep 2026)
--   * it_engineer.knowledge_exam (seat_duty, daily): 12 questions a day filed to think() (2 per seat), each answer
--     then graded by a high-stakes it_engineer.knowledge_grade decision (another family verifies) - about AED 4.8/day.
--   * ceo.task_responsibility: 5 questions / 24h, one per task review, choosing an os_responsibility for the task.
--   * learning.distil: 6 questions in one weekly run (2 groups x 3 seats), each high stakes with a cross-family verify.
--   * ceo.management_review / pricing_monitor / target_forecast (weekly): each filed at high stakes (decide + verify),
--     the review with six free-text fields, and every non-hold call also challenged by the accountant (another call).
--
-- WHAT THIS CHANGES
--   1. The model knowledge exam is retired: its seat_duty row is disabled, fn_it_engineer_duty_knowledge_exam files
--      nothing, and the exam questions still held are expired. The brief named knowledge_exam_retrieval_daily as the
--      model-free exam that stays; that job exists on neither production (cron.job, seat_duty, resilience_step and
--      pg_proc searched 24 Sep 2026) nor this repository, so NO exam runs after this until a retrieval exam is built.
--      Nothing is dropped (fn_it_engineer_knowledge_exam and its apply doors stay for rows already answered), so
--      DROPPED.txt gets no line.
--   2. fn_task_review routes ownership by structure (model_policy 'workflow_routing' is tier none): the department's
--      operating system owns the task via fn_task_ownership_record, no question filed. An answer already reasoned
--      under the old key is honoured. The ceo.task_responsibility questions still held are expired and their tasks
--      get the structural owner now.
--   3. Lessons: the grouping (vector distance, SQL) runs hourly with no model (resilience step learningGroup,
--      _shared/learning_loop.ts reason:false); the weekly learningDistil reasons only the groups that crossed the
--      threshold (fn_lesson_clusters_to_reason: 5+ cases, 3 a week, not already asked).
--   4. The weekly CEO reports stay SQL metric maths plus at most ONE think() call each, at normal stakes: the review
--      asks only the verdict and the binding constraint; the accountant's cross-family challenge is kept only for
--      calls that go to the founder (propose_change, tell_founder).
-- Canonical bodies started from: fn_task_review <- routing_and_ceo_decisions_are_reasoned_not_word_matched.sql;
-- fn_ceo_target_forecast, fn_ceo_management_review <- the_ceo_runs_the_company_on_the_founders_year_one_targets.sql;
-- fn_ceo_pricing_monitor, fn_ceo_review_applies <- the_ceo_reviews_the_week_watches_pricing_and_forecasts_the_target.sql;
-- fn_it_engineer_duty_knowledge_exam <- the_it_engineer_watches_licences_and_every_seats_knowledge.sql.
-- Pending: scripts/sql/pending/routine_work_is_code_and_the_model_answers_only_real_judgement.txt.
-- Proved by: node --test scripts/checks/routine_work_never_goes_back_to_the_model.test.mjs
--            deno test --allow-all supabase/functions/_shared/learning_loop.test.ts

-- ── 1. the model knowledge exam is retired ───────────────────────────────────────────────────────────────
update public.seat_duty set enabled = false,
       what = 'RETIRED 24 Sep 2026 (it_engineer): the think()-asked, model-graded exam cost about AED 4.8/day for routine work. '
           || 'See scripts/sql/routine_work_is_code_and_the_model_answers_only_real_judgement.sql.'
 where duty = 'it_engineer.knowledge_exam';

create or replace function public.fn_it_engineer_duty_knowledge_exam()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select jsonb_build_object('asked', 0, 'retired', 'the model exam files no question (24 Sep 2026)') $fn$;
revoke execute on function public.fn_it_engineer_duty_knowledge_exam() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_duty_knowledge_exam() to service_role;

update public.reasoning_held_question set status = 'expired'
 where status = 'held' and (surface like '%.knowledge_exam' or surface = 'it_engineer.knowledge_grade');

-- ── 2. task ownership is routed, not reasoned ────────────────────────────────────────────────────────────
create or replace function public.fn_task_review(p_task_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 set search_path to 'public', 'pg_temp'
AS $function$
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
  v_own jsonb; v_resp_key text; v_resp_choice text; v_rule_key text; v_rule_choice text; v_held bigint;
  v_block_wait boolean := false;
  v_awaiting jsonb := '[]'::jsonb;   -- meaning questions filed with the CEO seat (23 Sep 2026)
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
  -- ROUTED, NOT REASONED (24 Sep 2026, it_engineer). model_policy task_class 'workflow_routing' is tier none:
  -- ownership follows the structure (the task's department and its operating system, via
  -- fn_task_ownership_record with no named responsibility), never a model and never a word. An answer the
  -- CEO seat already reasoned under the old path (ceo.task_responsibility) is still honoured by its key;
  -- no new question is filed. Was 5 think() calls / 24h (inventory 24 Sep 2026).
  v_resp_key := 'task_resp:' || p_task_id || ':' || md5(v_text);
  v_resp_choice := coalesce(public.fn_reason_route_answer(v_resp_key), 'none');
  v_own := public.fn_task_ownership_record(p_task_id, t.dept_key, v_author, nullif(v_resp_choice, 'none'));
  v_own_os := v_own->>'owned_by_os'; v_own_agent := v_own->>'owner_agent'; v_own_resp := v_own->>'owns_responsibility';
  for v_rule in
    select c.* from collaboration_rule c where c.owner_dept = t.dept_key
  loop
    -- WHETHER THE RULE'S SITUATION IS THIS TASK, REASONED (23 Sep 2026). Two shared long words decided it
    -- before. Measured 23 Sep 2026: collaboration_rule holds 0 rows, so this loop runs for nobody today.
    -- A rule reasoned to apply AFTER this review ran is recorded, with its challenges, by its apply routine;
    -- a BLOCKING one still waiting holds publication (v_block_wait below).
    v_rule_key := 'task_rule:' || p_task_id || ':' || v_rule.id || ':' || md5(v_text);
    v_rule_choice := public.fn_reason_route_answer(v_rule_key);
    if v_rule_choice is null then
      v_held := public.fn_reason_route_ask('ceo', 'ceo.task_collaboration_rule', v_text,
        jsonb_build_array(jsonb_build_object('id', 'applies', 'meaning', 'the task is the situation this rule governs: ' || v_rule.situation),
                          jsonb_build_object('id', 'does_not_apply', 'meaning', 'the task is not that situation')),
        jsonb_build_object('task_id', p_task_id, 'rule_id', v_rule.id, 'dept_key', t.dept_key, 'author', v_author), v_rule_key);
      v_awaiting := v_awaiting || jsonb_build_object('surface', 'ceo.task_collaboration_rule', 'rule_id', v_rule.id, 'held_id', v_held);
      if v_rule.blocking then v_block_wait := true; end if;
      continue;
    end if;
    if v_rule_choice <> 'applies' then continue; end if;
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

  -- A BLOCKING rule whose situation is still being reasoned holds publication: the task rests until the
  -- answer (fn_reason_apply_ceo__task_collaboration_rule) records the rule and its challenges.
  if v_block_wait and not v_blocked and v_outcome in ('published', 'approve') then
    v_outcome := 'awaiting_reasoning';
  end if;

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
    'blocked',        v_blocked,
    'awaiting_reasoning', v_awaiting);
end
$function$;
revoke execute on function public.fn_task_review(bigint) from public, anon, authenticated;
grant execute on function public.fn_task_review(bigint) to service_role;

-- The questions already waiting: expired, and each task gets its structural owner now.
do $blk$
declare h record;
begin
  for h in update public.reasoning_held_question set status = 'expired'
            where status = 'held' and surface = 'ceo.task_responsibility' returning subject
  loop
    if (h.subject->>'task_id') is not null then
      perform public.fn_task_ownership_record((h.subject->>'task_id')::bigint, h.subject->>'dept_key', h.subject->>'author', null);
    end if;
  end loop;
end $blk$;

-- ── 3. lessons: grouped hourly in SQL, reasoned weekly over what crossed the threshold ───────────────────
-- Claimed groups (fn_lesson_clusters) with no lesson yet and no question already filed, of p_min_cases or more,
-- largest first. Same shape as fn_lesson_clusters, so learning_loop.ts reasons them unchanged.
create or replace function public.fn_lesson_clusters_to_reason(p_min_cases integer default 5, p_limit integer default 3)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('seat', c.seat, 'cluster_key', c.cluster_key, 'cases',
           (select jsonb_agg(jsonb_build_object('case_id', m.id, 'case_kind', m.case_kind, 'situation', left(m.situation, 500),
                    'decision', left(m.decision, 300), 'outcome', left(m.outcome, 300), 'finalised', m.finalised,
                    'correction', m.correction) order by m.id)
              from public.seat_case_memory m where m.id = any(c.case_ids)))), '[]'::jsonb)
    from (select * from public.seat_lesson_cluster c
           where c.candidate_id is null and cardinality(c.case_ids) >= greatest(3, coalesce(p_min_cases, 5))
             and not exists (select 1 from public.reasoning_held_question h where h.dedupe_key = 'lesson:' || c.cluster_key)
           order by cardinality(c.case_ids) desc, c.filed_at
           limit greatest(1, least(coalesce(p_limit, 3), 10))) c;
$fn$;
revoke execute on function public.fn_lesson_clusters_to_reason(integer, integer) from public, anon, authenticated;
grant execute on function public.fn_lesson_clusters_to_reason(integer, integer) to service_role;

insert into public.resilience_step (step, every, budget_ms, place, rank, note, owner_seat) values
  ('learningGroup', interval '1 hour', 5000, 'plan', 0,
   'hourly, no model: new lessons embedded (gte-small, free) and cases with outcomes grouped by vector distance (fn_lesson_clusters)',
   'it_engineer'),
  ('learningDistil', interval '7 days', 20000, 'plan', 0,
   'weekly: only the groups that crossed the threshold (fn_lesson_clusters_to_reason) are distilled into lessons by think(), verified by another model family',
   'it_engineer')
on conflict (step) do update set every = excluded.every, budget_ms = excluded.budget_ms, place = excluded.place,
                                rank = excluded.rank, note = excluded.note, owner_seat = excluded.owner_seat;

-- ── 4. the weekly CEO reports: metric maths plus one reasoned line ───────────────────────────────────────
create or replace function public.fn_ceo_target_forecast()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare c record; v jsonb; v_all jsonb := '[]'::jsonb; v_rev jsonb; v_week date := public.fn_ceo_review_week(); v_held bigint;
begin
  for c in select id, contract_key from public.target_contract where status = 'active' and measure_sql is not null order by priority, id loop
    v := public.fn_target_feasibility(c.id, true);
    v_all := v_all || jsonb_build_object('contract', c.contract_key, 'verdict', v->>'verdict', 'verdict_reason', v->>'verdict_reason',
                                         'remaining', v->'remaining_outcome', 'days_remaining', v->'days_remaining',
                                         'required_run_rate_per_day', v->'required_run_rate_per_day', 'binding_stage', v->>'binding_stage',
                                         'what_must_change', v->'what_must_change');
    if c.contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' then v_rev := v; end if;   -- the founder's year-one targets (24 Sep 2026)
  end loop;

  insert into public.ceo_review (kind, period, facts) values ('target_forecast', v_week, jsonb_build_object('verdicts', v_all))
  on conflict (kind, period) do update set facts = excluded.facts;

  if v_rev is not null and coalesce(v_rev->>'verdict', '') <> 'ON_TRACK'
     and (select held_id from public.ceo_review where kind = 'target_forecast' and period = v_week) is null then
    v_held := public.fn_seat_duty_reason('ceo', 'ceo.target_forecast',
      'This week''s forecast says the founder''s year-one target (about 500 verified suppliers by 31 August 2027, on the monthly path per seat) is not on track. '
        || 'As the chief executive, decide the company''s response, and say what must change and who owns it.',
      ('[{"id":"hold_course","meaning":"the plan in force is right; the gap is expected at this stage and closes as it runs"},'
      || '{"id":"change_plan","meaning":"the plan must change: a different binding constraint, channel or sequence"},'
      || '{"id":"tell_founder","meaning":"the gap needs a decision only the founder holds (money, a commercial rule, his intent)"}]')::jsonb,
      jsonb_build_object('forecast', v_rev - 'chain', 'all_contracts', v_all, 'year_plan', public.fn_ceo_year_plan_status(now())),
      jsonb_build_object('kind', 'target_forecast', 'period', v_week), 'ceo_forecast:' || v_week);
    -- ONE CALL PER REPORT (24 Sep 2026, it_engineer): normal stakes, so think() runs no second-family verify on it.
    update public.reasoning_held_question set request = request || '{"stakes":"normal"}'::jsonb where id = v_held;
    update public.ceo_review set held_id = v_held where kind = 'target_forecast' and period = v_week;
  end if;
  return jsonb_build_object('week', v_week, 'verdicts', v_all, 'reasoning_filed', v_held is not null);
end $fn$;
revoke execute on function public.fn_ceo_target_forecast() from public, anon, authenticated;
grant execute on function public.fn_ceo_target_forecast() to service_role;

create or replace function public.fn_ceo_management_review()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_week date := public.fn_ceo_review_week(); v_facts jsonb; v_held bigint;
begin
  if (select held_id from public.ceo_review where kind = 'management_review' and period = v_week) is not null then
    return jsonb_build_object('week', v_week, 'already_filed', true);
  end if;
  select jsonb_build_object(
    'seats', (select jsonb_object_agg(r.role_id, jsonb_build_object(
        'duties', (select coalesce(jsonb_agg(jsonb_build_object('duty', d.duty, 'last_ok_at', d.last_ok_at, 'failures', d.failures, 'last_result', d.last_result)), '[]'::jsonb)
                     from public.seat_duty d where d.owner_seat = r.role_id),
        'open_findings', (select count(*) from public.it_engineer_finding f where f.closed_at is null
                            and coalesce(f.evidence->>'owner_seat', f.raised_by) = r.role_id),
        'reasoning_waiting', (select count(*) from public.reasoning_held_question h where h.seat = r.role_id and h.status = 'held'),
        'handoffs_pending', (select count(*) from public.agent_actions a where a.agent = r.role_id and a.kind = 'handoff' and a.status = 'pending'),
        -- the seat reports against its own year-one targets and its month directive
        'targets', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(public.fn_ceo_year_plan_status(now())->'metrics') x
                     where x->>'owner_seat' = r.role_id),
        'month_directive', (select jsonb_build_object('actions', d.actions, 'targets', d.targets, 'handoff_id', d.handoff_id, 'status', d.status)
                              from public.ceo_seat_directive d where d.seat = r.role_id and d.month = date_trunc('month', now() at time zone 'Asia/Dubai')::date),
        'improvements_open', (select count(*) from public.ceo_improvement i where i.seat = r.role_id and i.status in ('open', 'assigned'))))
      from public.org_role r where r.status = 'active'),
    'duties_unhealthy', public.fn_seat_duty_health(),
    'week_revenue_aed', (select coalesce(sum(reveal_fee), 0) from public.transactions where fee_status in ('paid', 'collected', 'succeeded') and revealed_at > now() - interval '7 days'),
    'requests_7d', (select count(*) from public.inquiries where created_at > now() - interval '7 days'),
    'customers', (select count(*) from public.customers where not coalesce(is_demo, false)),
    'suppliers_approved', (select count(*) from public.leads where approval_status = 'approved' and not coalesce(is_demo, false)),
    'forecast', (select facts from public.ceo_review where kind = 'target_forecast' and period = v_week),
    'last_review', (select jsonb_build_object('week', period, 'verdict', decision, 'fields', fields) from public.ceo_review
                     where kind = 'management_review' and period < v_week and decision is not null order by period desc limit 1))
  into v_facts;
  insert into public.ceo_review (kind, period, facts) values ('management_review', v_week, v_facts)
  on conflict (kind, period) do update set facts = excluded.facts;

  v_held := public.fn_seat_duty_reason('ceo', 'ceo.management_review',
    'The weekly management review. Read each seat''s week — its duties, failures, open findings, what waits in its '
      || 'reasoning queue, and its own targets and month directive on the founder''s year-one path — against last week''s review. Give the verdict and name the one '
      || 'binding constraint.',
    ('[{"id":"on_track","meaning":"the company is on its plan this week"},'
    || '{"id":"at_risk","meaning":"the plan holds but something material is slipping"},'
    || '{"id":"off_track","meaning":"the plan is not working and must change"}]')::jsonb,
    v_facts, jsonb_build_object('kind', 'management_review', 'period', v_week), 'ceo_mreview:' || v_week);
  -- ONE VERDICT LINE (24 Sep 2026, it_engineer): the per-seat week is the SQL facts above (duties, failures,
  -- findings, queue, targets, directive); the model gives only the verdict and the one binding constraint, at
  -- normal stakes, so the review is one think() call. The five per-seat direction fields it wrote before are gone.
  update public.reasoning_held_question
     set request = jsonb_set(request || '{"stakes":"normal"}'::jsonb, '{decision,fields}', jsonb_build_array(
           jsonb_build_object('key', 'binding_constraint', 'question', 'the one constraint that most limits progress this week')))
   where id = v_held;
  update public.ceo_review set held_id = v_held where kind = 'management_review' and period = v_week;
  return jsonb_build_object('week', v_week, 'filed', v_held);
end $fn$;
revoke execute on function public.fn_ceo_management_review() from public, anon, authenticated;
grant execute on function public.fn_ceo_management_review() to service_role;

create or replace function public.fn_ceo_pricing_monitor()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_week date := public.fn_ceo_review_week(); v_ev jsonb; v_quoted int; v_held bigint;
begin
  with q as (
    select i.id, (select count(*) from public.quotes x where x.inquiry_id = i.id) as quotes
      from public.inquiries i where i.created_at > now() - interval '90 days'
  )
  select jsonb_build_object(
    'pricing_config', (select to_jsonb(p) - 'id' - 'updated_at' from public.pricing_config p order by id limit 1),
    'requests_90d', (select count(*) from q),
    'quoted_requests_90d', (select count(*) from q where quotes > 0),
    'reveals_90d', (select count(*) from public.transactions where revealed_at > now() - interval '90 days'),
    'refunds_90d', (select count(*) from public.transactions where refund_requested_at > now() - interval '90 days'),
    'avg_quote_aed', (select round(avg(quote_amount), 2) from public.quotes where created_at > now() - interval '90 days' and quote_amount > 0),
    'avg_reveal_fee_aed', (select round(avg(reveal_fee), 2) from public.transactions where revealed_at > now() - interval '90 days'),
    'nonresponse_refunds', (select coalesce(sum(rv_nonresponse_refunds), 0) from public.leads),
    'supplier_fee_paying', (select count(*) from public.leads where registration_paid_at is not null),
    'competitors_on_file', (select count(*) from public.competitor))
  into v_ev;
  v_quoted := (v_ev->>'quoted_requests_90d')::int;
  insert into public.ceo_review (kind, period, facts, decision) values ('pricing_monitor', v_week, v_ev,
    case when v_quoted < 20 then 'insufficient_evidence' end)
  on conflict (kind, period) do update set facts = excluded.facts,
    decision = case when ceo_review.decided_at is null then excluded.decision else ceo_review.decision end;

  -- UNDER 20 QUOTED REQUESTS THE EVIDENCE CANNOT SUPPORT A PRICE CALL: recorded, not reasoned, not proposed.
  if v_quoted >= 20 and (select held_id from public.ceo_review where kind = 'pricing_monitor' and period = v_week) is null then
    v_held := public.fn_seat_duty_reason('ceo', 'ceo.pricing_monitor',
      'The weekly pricing review. From 90 days of evidence, decide whether our pricing (the supplier annual fee, the caps, '
        || 'the promotion window and the non-response charge) should stay as it is or whether an evidence-based change should '
        || 'be proposed to the founder. The 3 per cent reveal fee paid by the buyer is the founder''s fixed rule and is not in scope.',
      ('[{"id":"keep","meaning":"the evidence supports the current pricing"},'
      || '{"id":"propose_change","meaning":"the evidence supports proposing a specific change to the founder"}]')::jsonb,
      v_ev, jsonb_build_object('kind', 'pricing_monitor', 'period', v_week), 'ceo_pricing:' || v_week);
    update public.reasoning_held_question
       set request = jsonb_set(request, '{decision,fields}', jsonb_build_array(
             jsonb_build_object('key', 'proposal', 'question', 'the exact change proposed, if any, with the figure'),
             jsonb_build_object('key', 'evidence', 'question', 'the measured evidence it rests on')))
     where id = v_held;
    -- ONE CALL PER REPORT (24 Sep 2026, it_engineer): normal stakes, so think() runs no second-family verify on it.
    update public.reasoning_held_question set request = request || '{"stakes":"normal"}'::jsonb where id = v_held;
    update public.ceo_review set held_id = v_held where kind = 'pricing_monitor' and period = v_week;
  end if;
  return jsonb_build_object('week', v_week, 'quoted_requests_90d', v_quoted, 'reasoning_filed', v_held is not null);
end $fn$;
revoke execute on function public.fn_ceo_pricing_monitor() from public, anon, authenticated;
grant execute on function public.fn_ceo_pricing_monitor() to service_role;

create or replace function public.fn_ceo_review_applies(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_kind text; v_period date;
  rv public.ceo_review; v_review jsonb; v_notice jsonb; v_fields jsonb;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_kind := r.subject->>'kind'; v_period := (r.subject->>'period')::date;
  if v_choice is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v_choice) then
    -- fn_reason_held_resolve marks a row applied whenever its apply returns, so a non-answer RAISES and is reasoned again.
    raise exception 'CHOICE_NOT_AN_OPTION: % is not an option of % (held question %)', coalesce(v_choice, 'no choice'), r.surface, p_id;
  end if;
  select * into rv from public.ceo_review where kind = v_kind and period = v_period for update;
  if not found then return jsonb_build_object('applied', false, 'reason', 'no review row'); end if;
  if rv.decided_at is not null then return jsonb_build_object('applied', true, 'already', v_kind || ' ' || v_period); end if;
  select coalesce(jsonb_object_agg(k, v->>'value'), '{}'::jsonb) into v_fields from jsonb_each(coalesce(p_result->'decision'->'fields', '{}'::jsonb)) f(k, v);

  -- THE CHALLENGE (narrowed 24 Sep 2026, it_engineer): only a call that goes to the founder - a pricing proposal or
  -- "tell the founder" - is challenged by the accountant on a model of another family. An internal verdict is one call.
  if v_choice in ('propose_change', 'tell_founder') then
    v_review := public.fn_seat_duty_cross_review('ceo.' || v_kind, 'ceo', 'accountant',
      case v_kind when 'management_review' then 'Challenge the chief executive''s reading of the company''s week.'
                  when 'pricing_monitor' then 'Challenge the chief executive''s pricing call before it reaches the founder.'
                  else 'Challenge the chief executive''s response to the revenue forecast.' end,
      -- seat_deliberation.evidence is capped at 60,000 characters; a week that outgrows it is passed as text, cut.
      case when length(rv.facts::text) <= 50000 then jsonb_build_object('facts', rv.facts)
           else jsonb_build_object('facts_cut_at_50000_chars', left(rv.facts::text, 50000)) end,
      jsonb_build_object('call', v_choice, 'fields', v_fields, 'reasoning', left(coalesce(p_result->>'answer', ''), 3000)),
      p_result, 'ceo_review', v_kind || ':' || v_period);
  end if;
  update public.ceo_review set decision = v_choice, fields = v_fields, reasoning = left(coalesce(p_result->>'answer', ''), 6000),
         model = p_result->>'model', review = v_review, decided_at = now()
   where kind = v_kind and period = v_period;

  if (v_kind = 'pricing_monitor' and v_choice = 'propose_change') or (v_kind = 'target_forecast' and v_choice = 'tell_founder') then
    v_notice := public.fn_ceo_review_tells_founder(v_kind, v_period,
      case when v_kind = 'pricing_monitor' then 'CEO pricing proposal (evidence-based) for the week of ' || v_period
           else 'CEO: the AED 1M revenue forecast needs your decision (week of ' || v_period || ')' end,
      left(coalesce(v_fields->>'proposal', '') || E'\n\n' || coalesce(v_fields->>'evidence', '') || E'\n\n' || coalesce(p_result->>'answer', ''), 4000)
        || E'\n\nThe accountant is challenging this on a model of another family (seat_deliberation '
        || coalesce(v_review->>'deliberation_id', 'not opened: ' || coalesce(v_review->>'error', '?')) || ').',
      case when v_kind = 'pricing_monitor' then 'founder_brief' else 'business_health_at_risk' end);
  end if;
  return jsonb_build_object('applied', true, 'kind', v_kind, 'period', v_period, 'choice', v_choice, 'review', v_review, 'founder', v_notice);
end $fn$;
revoke execute on function public.fn_ceo_review_applies(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_ceo_review_applies(bigint, jsonb) to service_role;

-- ── probe ────────────────────────────────────────────────────────────────────────────────────────────────
select case when not (select enabled from public.seat_duty where duty = 'it_engineer.knowledge_exam')
             and position('ceo.task_responsibility''' in pg_get_functiondef('public.fn_task_review(bigint)'::regprocedure)) = 0
             and (select every from public.resilience_step where step = 'learningGroup') = interval '1 hour'
             and position('"stakes":"normal"' in pg_get_functiondef('public.fn_ceo_management_review()'::regprocedure)) > 0
            then 'PROBE OK' else 'PROBE FAILED' end as verdict;

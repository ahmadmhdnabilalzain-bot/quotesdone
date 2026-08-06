-- THE REVIEW CHAIN NEVER RAN. Work shipped whenever a deliverable exceeded 60 characters.
--
-- Spec file #1 "Every Task Has a Review Process": author -> department head reviews -> poor quality
-- returns for revision -> acceptable goes to the Chief of Staff -> CoS checks brand, objectives,
-- business value, quality, timing, compliance -> approved -> published. And "Employees Challenge
-- Each Other": departments review one another's work, healthy disagreement encouraged.
--
-- Every piece of that was already built and none of it was called:
--   fn_review_submit   — the whole four-stage chain, quality gates, fail-closed on unenforceable
--                        critical criteria, writes review_chain. ZERO callers.
--   fn_pick_reviewer   — department head, with delegation_rule and a seniority fallback. Called
--                        only by fn_review_submit, which nothing called.
--   fn_challenge       — 8 challenge_heuristic patterns + prior outcomes from institutional_memory.
--   collaboration_rule — 10 rows of must_involve / must_review / may_challenge and a blocking flag.
--                        ZERO readers.
-- Meanwhile cos_execute:233 decided the whole question with `deliverable.length > 60`.
--
-- TWO THINGS MAKE THIS AFFORDABLE. fn_challenge is deterministic SQL — heuristic patterns and
-- recorded outcomes, no model call — so cross-department challenge is free and can run on EVERY
-- task rather than being rationed. And collaboration_rule's ten situations are rare by design, so
-- the department-involvement branch fires seldom.
--
-- BLOCKING VS DISSENT IS collaboration_rule.blocking, the founder's own column (6 Aug 2026: the
-- schema already anticipated it). A matching rule with blocking=true turns a recommend_against
-- into a returned revision; everything else records the dissent and lets the work proceed. Either
-- way the REASON is written — no rejection and no dissent is valid without one.

-- ---------------------------------------------------------------------------------------------
-- 1. The quality bar for a department deliverable.
--
-- fn_review_submit holds for a human when no quality_standard exists for the work type, so without
-- this row wiring the chain in would have parked every task — the exact defect just fixed on the
-- other side. Every criterion here is EXECUTABLE (fn_review_submit treats an uncheckable critical
-- criterion as a hold, never a pass) and every one restates something the cos_execute work-order
-- prompt already demands, so this is the existing bar written down, not a new one.
insert into public.quality_standard (work_type, criteria, owner_dept)
values ('org_task', '[
  {"rule":"is_actual_work",
   "severity":"critical",
   "why":"A department that cannot reach its specialist returns a courteous sentence. Those are 60-90 characters and sailed past the old length check, marking the task done with an apology stored as the work product. A false success is worse than an escalation: an escalation gets looked at.",
   "pattern":"(?i)(could not reach|couldn.t reach|unable to reach|not reachable|ai_unreachable|ai (service|is) (unavailable|unreachable)|try again in a moment|no ai key|ai not reachable|service unavailable)",
   "fails_when":"match"},
  {"rule":"is_substantive",
   "severity":"critical",
   "why":"The prompt asks for the ACTUAL deliverable - the real draft, analysis, recommendation or plan - not a description of what would be done. 60 characters cannot be any of those.",
   "pattern":".{200,}",
   "fails_when":"no_match"},
  {"rule":"states_its_result",
   "severity":"major",
   "why":"The work order ends with: End with a one-line RESULT: summarising what you produced. Its absence means the model did not follow the brief, and resultLine() then silently falls back to the first 160 characters.",
   "pattern":"(?i)RESULT:",
   "fails_when":"no_match"},
  {"rule":"grounded_in_this_business",
   "severity":"minor",
   "why":"The work order says: Be concrete and specific to QuotesDone and the UAE market. A deliverable that never names the company, the currency or the market is usually generic advice. MINOR, not major, and the demotion was measured: org_tasks#49 is an HR task about wiring org_agents schema bindings, where demanding UAE-market language is the wrong bar. 47 of 95 completed deliverables trip this, so at major severity it would return half of all work for revision and be muted inside a week. Recorded and visible; it does not block.",
   "pattern":"(?i)\\y(QuotesDone|UAE|Dubai|Abu Dhabi|AED|Emirat)",
   "fails_when":"no_match"}
]'::jsonb, 'exec')
on conflict (work_type) do update
  set criteria = excluded.criteria, owner_dept = excluded.owner_dept, updated_at = now();

-- ---------------------------------------------------------------------------------------------
-- 2. The reviewer.
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
    'blocked',        v_blocked);
end
$function$;

comment on function public.fn_task_review(bigint) is
  'Runs a department deliverable through the review chain the spec requires: department head '
  '(fn_review_submit, reviewer resolved live via fn_pick_reviewer/delegation_rule), then Chief of '
  'Staff, then the cross-department challenge from collaboration_rule + fn_challenge. '
  'collaboration_rule.blocking decides whether a recommend_against returns the work for revision '
  'or is recorded as a dissent; the reason is written in both cases.';
